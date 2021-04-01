defmodule CSSEx do
  @behaviour :gen_statem

  require Logger

  @timeout 15_000

  defstruct entry_points: [],
            pretty_print: false,
            file_watch: false,
            watchers: %{},
            no_start: false,
            dependency_graph: %{},
            monitors: %{},
            reply_to: [],
            reprocess: []

  @type t :: %__MODULE__{
          entry_points: list(Keyword.t()),
          pretty_print: boolean,
          file_watch: boolean,
          no_start: boolean
        }

  @doc """
  Generate a `%CSSEx{}` struct from a keyword list or a map. Its only relevant use case is to "parse" app config environment values. You can also pass a directory as the last argument where it will be joined to the paths in the `:entry_points`.
  Whatever the final path it will be expanded when this config is passed as the argument to `start_link/1`
  """
  @spec make_config(Keyword.t() | Map.t(), base_dir :: String.t()) :: %__MODULE__{}
  def make_config(opts, dir \\ nil) when is_list(opts) do
    Enum.reduce(opts, %__MODULE__{}, fn {k, v}, acc ->
      case k do
        :entry_points ->
          new_entries =
            Enum.map(v, fn {orig, final} ->
              case dir do
                nil ->
                  {orig, final}

                _ ->
                  {Path.join([dir, orig]), Path.join([dir, final])}
              end
            end)

          struct(acc, [{k, new_entries}])

        _ ->
          struct(acc, [{k, v}])
      end
    end)
  end

  @doc """
  Start a watcher responsible for automatically processing cssex files into css files.
  Define in the application config something as:

  ```
  config :yourapp_web, CSSEx,
    entry_points: [
      {"../../../../apps/yourapp_web/assets/cssex/app.cssex", "../../../../apps/yourapp_web/assets/css/app.css"}
  ]
  ```

  With as many `:entry_points` as necessary specified as tuples of `{"source", "dest"}`
  Then,

  ```
  Application.get_env(:yourapp_web, CSSEx)
  |> CSSEx.make_config(Application.app_dir(:your_app_web))
  |> CSSEx.start_link()
  ```

  Or add it to a supervision tree. Refer to the README.md file.
  """
  @spec start_link(%__MODULE__{}) :: {:ok, pid} | {:error, term}
  def start_link(%__MODULE__{} = config) do
    :gen_statem.start_link(__MODULE__, config, [])
  end

  @impl :gen_statem
  def callback_mode(), do: :handle_event_function

  @impl :gen_statem
  def init(%__MODULE__{} = config) do
    {:ok, :starting, config, [{:next_event, :internal, :prepare}]}
  end

  @impl :gen_statem
  # parse and set up the correct paths in case they're relative and substitute the entry_points field with those updated, trigger the :setup event
  def handle_event(:internal, :prepare, _, %{entry_points: entries} = data) do
    cwd = File.cwd!()

    new_entries =
      Enum.reduce(entries, %{}, fn {path, final}, acc ->
        expanded_base = assemble_path(path, cwd)
        expanded_final = assemble_path(final, cwd)
        Map.put(acc, expanded_base, expanded_final)
      end)

    {:keep_state, %{data | entry_points: new_entries}, [{:next_event, :internal, :setup}]}
  end

  # create the basic depedency graph, in this case it will just be for the entry points base paths, trigger the :start event
  def handle_event(:internal, :setup, _, %{entry_points: entries, dependency_graph: dg} = data) do
    new_dg =
      Enum.reduce(entries, dg, fn {path, _}, acc ->
        Map.put(acc, path, [path])
      end)

    {:keep_state, %{data | dependency_graph: new_dg},
     [{:next_event, :internal, :synch_watchers}, {:next_event, :internal, :start}]}
  end

  # for each entry point check if it exists, if it does start a parser under a monitor, if it not log an error
  def handle_event(:internal, :start, _, %{entry_points: entries} = data) do
    self_pid = self()

    new_monitors =
      Enum.reduce(entries, %{}, fn {path, final}, monitors_acc ->
        case File.exists?(path) do
          true ->
            {_pid, monitor} =
              Process.spawn(__MODULE__, :parse_file, [path, final, self_pid], [:monitor])

            Map.put(monitors_acc, monitor, path)

          false ->
            Logger.error("CSSEx Watcher: Couldn't find entry point #{path}")
            monitors_acc
        end
      end)

    {:next_state, :processing, %{data | monitors: new_monitors},
     [{:next_event, :internal, :set_status}, @timeout]}
  end

  def handle_event(
        :internal,
        {:process, file_path},
        _,
        %{entry_points: entries, monitors: monitors, reprocess: reprocess} = data
      ) do
    case Map.get(monitors, file_path) do
      nil ->
        self_pid = self()
        final_file = Map.get(entries, file_path)

        {_pid, monitor} =
          Process.spawn(__MODULE__, :parse_file, [file_path, final_file, self_pid], [:monitor])

        new_monitors = Map.put(monitors, monitor, file_path)
        new_reprocess = Enum.filter(reprocess, fn path -> file_path == path end)

        {:next_state, :processing, %{data | monitors: new_monitors, reprocess: new_reprocess},
         [@timeout]}

      _ ->
        case file_path in reprocess do
          true ->
            {:keep_state_and_data, [{:next_event, :internal, :set_status}]}

          false ->
            {:keep_state, %{data | reprocess: [file_path | reprocess]},
             [{:next_event, :internal, :set_status}]}
        end
    end
  end

  def handle_event(:internal, {:post_process, parser}, _, _data) do
    case parser do
      %CSSEx.Parser{valid?: true, warnings: [], file: file} ->
        Logger.info(
          IO.ANSI.green() <> "CSSEx PROCESSED file :: #{file}\n" <> IO.ANSI.default_color()
        )

        {:keep_state_and_data, [{:next_event, :internal, :set_status}]}

      %CSSEx.Parser{valid?: true, warnings: warnings, file: file} ->
        Enum.each(warnings, fn warning ->
          Logger.warn("CSSEx warning when processing #{file} ::\n\n #{warning}\n")
        end)

        {:keep_state_and_data, [{:next_event, :internal, :set_status}]}

      {original_file, %CSSEx.Parser{valid?: false, error: error}} ->
        Logger.error("CSSEx ERROR when processing #{original_file} :: \n\n #{error}\n")
        {:keep_state_and_data, [{:next_event, :internal, :set_status}]}
    end
  end

  def handle_event(:internal, :set_status, _, %{monitors: monitors} = data) do
    case monitors == %{} do
      true -> {:next_state, :ready, data, [{:next_event, :internal, :maybe_reply}]}
      _ -> {:next_state, :processing, data, []}
    end
  end

  def handle_event(:internal, :maybe_reply, :ready, %{reply_to: reply_to}) do
    to_reply = Enum.map(reply_to, fn from -> {:reply, from, :ready} end)
    {:keep_state_and_data, to_reply}
  end

  def handle_event(:internal, :maybe_reply, _, _), do: {:keep_state_and_data, []}

  def handle_event(:internal, {:maybe_process, file_path}, _, %{
        dependency_graph: dependency_graph,
        entry_points: eps
      }) do
    events =
      Enum.reduce(eps, [], fn {entry, _}, acc ->
        deps = Map.get(dependency_graph, entry)

        case file_path in deps || file_path == entry do
          true -> [{{:timeout, {:to_process, entry}}, 50, nil} | acc]
          false -> acc
        end
      end)
      |> Enum.uniq()

    {:keep_state_and_data, events}
  end

  def handle_event({:timeout, {:to_process, entry}}, _, _, _data) do
    {:keep_state_and_data, [{:next_event, :internal, {:process, entry}}]}
  end

  def handle_event(
        :internal,
        {:refresh_dependencies,
         %CSSEx.Parser{valid?: true, file: original_file, dependencies: dependencies}},
        _state,
        %{dependency_graph: d_g} = data
      ) do
    new_d_g = clean_up_deps(d_g, original_file, dependencies)

    {:keep_state, %{data | dependency_graph: new_d_g},
     [{:next_event, :internal, :synch_watchers}]}
  end

  def handle_event(
        :internal,
        {:refresh_dependencies,
         {original_file, %CSSEx.Parser{file: error_file, dependencies: dependencies}}},
        _state,
        %{dependency_graph: d_g} = data
      ) do
    new_d_g = clean_up_deps(d_g, original_file, [error_file | dependencies])

    {:keep_state, %{data | dependency_graph: new_d_g},
     [{:next_event, :internal, :synch_watchers}]}
  end

  def handle_event(:internal, :synch_watchers, _, %{watchers: watchers} = data) do
    watch_paths = watch_list(data)
    new_watchers = synch_watchers(watch_paths, watchers)
    new_data = maybe_start_watchers(watch_paths, %{data | watchers: new_watchers})
    {:keep_state, new_data, []}
  end

  def handle_event(
        :info,
        {:DOWN, ref, :process, _, _reason},
        _,
        %{monitors: monitors, reprocess: reprocess} = data
      )
      when is_map_key(monitors, ref) do
    {path, new_monitors} = Map.pop(monitors, ref)
    new_data = %{data | monitors: new_monitors}

    case path in reprocess do
      false ->
        {:keep_state, new_data, [{:next_event, :internal, :set_status}]}

      true ->
        {:keep_state, new_data, [{{:timeout, {:to_process, path}}, 50, nil}]}
    end
  end

  def handle_event(:info, {:DOWN, _, _, _, _}, _, _data),
    do: {:keep_state_and_data, []}

  def handle_event(:info, {:parsed, parsed}, _, _data) do
    {:keep_state_and_data,
     [
       {:next_event, :internal, {:refresh_dependencies, parsed}},
       {:next_event, :internal, {:post_process, parsed}}
     ]}
  end

  def handle_event(:info, {:file_event, _worker_pid, {file_path, events}}, _, _data) do
    case (:modified in events and :closed in events) or :closed in events do
      false ->
        {:keep_state_and_data, []}

      true ->
        {:keep_state_and_data, [{:next_event, :internal, {:maybe_process, file_path}}]}
    end
  end

  def handle_event(:info, {:file_event, worker_pid, :stop}, _, %{watchers: watchers} = data) do
    {path, new_watchers} = Map.pop(watchers, worker_pid)
    {_, final_watchers} = Map.pop(new_watchers, path)
    new_data = %{data | watchers: final_watchers}

    {:keep_state, new_data, [{:next_event, :internal, {:retry_watchers, [path]}}]}
  end

  def handle_event(:info, {:retry_watchers, paths}, _, data) do
    new_data = maybe_start_watchers(paths, data)

    {:keep_state, new_data, []}
  end

  def handle_event({:call, from}, :status, state, %{reply_to: reply_to} = data) do
    case state do
      :ready -> {:keep_state_and_data, [{:reply, from, :ready}]}
      _ -> {:keep_state, %{data | reply_to: [from | reply_to]}, []}
    end
  end

  @doc false
  def clean_up_deps(d_graph, original_file, dependencies) do
    Enum.reduce(dependencies, d_graph, fn dep, acc ->
      case Map.get(acc, dep) do
        nil ->
          Map.put(acc, dep, [original_file])

        deps ->
          case original_file in deps do
            true -> acc
            false -> Map.put(acc, dep, [original_file | deps])
          end
      end
    end)
    |> Enum.reduce(d_graph, fn {file, deps}, acc ->
      case original_file do
        ^file ->
          Map.put(acc, file, dependencies)

        parent ->
          case file in dependencies do
            true ->
              case parent in deps do
                true -> Map.put(acc, file, deps)
                false -> Map.put(acc, file, [parent | deps])
              end

            false ->
              case parent in deps do
                true -> Map.put(acc, file, Enum.filter(deps, fn d -> d != parent end))
                false -> acc
              end
          end
      end
    end)
    |> Enum.reduce(%{}, fn {file, deps}, acc ->
      case deps do
        [] -> acc
        _ -> Map.put(acc, file, Enum.uniq(deps))
      end
    end)
  end

  @doc false
  def watch_list(%{dependency_graph: dg} = _data) do
    Enum.reduce(dg, [], fn {k, deps}, acc ->
      Enum.reduce(deps, [Path.dirname(k) | acc], fn dep, acc_i ->
        [Path.dirname(dep) | acc_i]
      end)
    end)
    |> Enum.uniq()
  end

  @doc false
  def synch_watchers(paths, watchers) do
    Enum.reduce(watchers, %{}, fn {k, v}, acc ->
      case Map.get(acc, k) do
        nil ->
          case is_pid(k) do
            true ->
              case v in paths do
                true ->
                  acc
                  |> Map.put(k, v)
                  |> Map.put(v, k)

                _ ->
                  Process.exit(k, :normal)
                  acc
              end

            false ->
              case k in paths do
                true ->
                  acc
                  |> Map.put(k, v)
                  |> Map.put(v, k)

                false ->
                  Process.exit(v, :normal)
                  acc
              end
          end

        _ ->
          acc
      end
    end)
  end

  @doc false
  def maybe_start_watchers(paths, %{dependency_graph: dg, watchers: watchers} = data) do
    dg_paths =
      Enum.reduce(dg, [], fn {k, _}, acc ->
        [Path.dirname(k) | acc]
      end)
      |> Enum.uniq()

    new_watchers =
      Enum.reduce(paths, watchers, fn path, acc ->
        case Map.get(watchers, path) do
          pid when is_pid(pid) ->
            acc

          nil ->
            case path in dg_paths do
              false ->
                acc

              _ ->
                case File.exists?(path) do
                  false ->
                    Logger.error("CSSEx Watcher: #{path} doesn't exist, retrying in 3secs")
                    Process.send_after(self(), {:retry_watchers, [path]}, 3000)
                    acc

                  true ->
                    {:ok, pid} = FileSystem.start_link(dirs: [path])
                    FileSystem.subscribe(pid)

                    acc
                    |> Map.put(path, pid)
                    |> Map.put(pid, path)
                end
            end
        end
      end)

    %{data | watchers: new_watchers}
  end

  @doc false
  def parse_file(path, final_file, self_pid) do
    case CSSEx.Parser.parse_file(nil, Path.dirname(path), Path.basename(path), final_file) do
      {:ok, parser, _} -> send(self_pid, {:parsed, parser})
      {:error, parser} -> send(self_pid, {:parsed, {path, parser}})
    end
  end

  @doc false
  # TODO check use cases with expand, perhaps it's not warranted?
  # when it's an absolute path probably not
  def assemble_path(<<"/", _::binary>> = path, _cwd), do: Path.expand(path)

  # but here yes, because files through plain "imports" in css/cssex might refer to relative paths, such as those in node_modules but also others using relative paths to indicate their source
  def assemble_path(path, cwd) do
    Path.join([cwd, path]) |> Path.expand()
  end
end
