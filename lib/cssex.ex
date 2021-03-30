defmodule CSSEx do
  @behaviour :gen_statem

  require Logger

  @timeout 15_000

  defstruct [
    :entry_points,
    pretty_print: false,
    file_watch: false,
    watchers: %{},
    no_start: false,
    dependency_graph: %{},
    monitors: %{},
    reply_to: []
  ]

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

    new_data =
      %{data | dependency_graph: new_dg}
      |> synch_watchers()

    {:keep_state, new_data, [{:next_event, :internal, :start}]}
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
        %{entry_points: entries, monitors: monitors} = data
      ) do
    self_pid = self()
    final_file = Map.get(entries, file_path)

    {_pid, monitor} =
      Process.spawn(__MODULE__, :parse_file, [file_path, final_file, self_pid], [:monitor])

    new_monitors = Map.put(monitors, monitor, file_path)

    {:next_state, :processing, %{data | monitors: new_monitors},
     [{:next_event, :internal, :set_status}, @timeout]}
  end

  def handle_event(:internal, {:post_process, parser}, _, _data) do
    case parser do
      %CSSEx.Parser{valid?: true, warnings: [], file: file} ->
        Logger.info(
          IO.ANSI.green() <> "\nCSSEx PROCESSED file :: #{file}\n" <> IO.ANSI.default_color()
        )

        {:keep_state_and_data, []}

      %CSSEx.Parser{valid?: true, warnings: warnings} ->
        Enum.each(warnings, fn warning ->
          Logger.warn(warning)
        end)

        {:keep_state_and_data, []}

      %CSSEx.Parser{valid?: false, error: error} ->
        Logger.error(error)
        {:keep_state_and_data, []}
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
      case Map.get(dependency_graph, file_path) do
        [_ | _] = deps ->
          Enum.reduce(deps, [], fn dep, acc ->
            case Map.get(eps, dep) do
              nil -> acc
              _ -> [{:next_event, :internal, {:process, dep}} | acc]
            end
          end)
          |> Enum.uniq()

        _ ->
          [{:next_event, :internal, :set_status}]
      end

    {:keep_state_and_data, events}
  end

  def handle_event(:info, {:DOWN, ref, :process, _, reason}, _, %{monitors: monitors} = data) do
    {_path, new_monitors} = Map.pop(monitors, ref)

    case reason do
      %CSSEx.Parser{error: error, file_list: file_list, dependencies: deps, file: original_file} =
          parser
      when not is_nil(error) ->
        new_data =
          data
          |> add_dependencies(original_file, :lists.flatten([file_list | deps]))
          |> synch_watchers()

        {:keep_state, new_data,
         [
           {:next_event, :internal, {:post_process, parser}},
           {:next_event, :internal, :set_status}
         ]}

      _ ->
        {:keep_state, %{data | monitors: new_monitors}, [{:next_event, :internal, :set_status}]}
    end
  end

  # TODO
  # we should keep track of the deps in an additional way in order to have a full
  # mapping of the files after a sucessful parse
  # as it is it sets everything correctly but if one dependency is removed from the
  # stylesheets the watchers will still be running for its directory - usually it
  # won't be much of a problem since it gets reset whenever the server is started
  # but ideally it would compare the previous dependencies with the new ones
  # [old, ones] -- [new, ones]
  # if it's different than [] it means those remaining can be removed
  # to decide it just has to check if any current depedency overlaps with the same
  # directory - if not then it's safe to turn off the watcher for that directory,
  # if yes then we keep the watcher
  def handle_event(:info, {:parsed, parsed}, _, data) do
    case parsed do
      {:ok, %CSSEx.Parser{dependencies: deps, file: original_file} = parser, _} ->
        new_data =
          data
          |> add_dependencies(original_file, deps)
          |> synch_watchers()

        {:keep_state, new_data, [{:next_event, :internal, {:post_process, parser}}]}

      {:error, %CSSEx.Parser{dependencies: deps, file: original_file} = parser} ->
        new_data =
          data
          |> add_dependencies(original_file, deps)
          |> synch_watchers()

        {:keep_state, new_data, [{:next_event, :internal, {:post_process, parser}}]}
    end
  end

  def handle_event(:info, {:file_event, _worker_pid, {file_path, events}}, _, data) do
    case (:modified in events and :closed in events) or :closed in events do
      false ->
        {:keep_state_and_data, []}

      true ->
        {:next_state, :processing, data, [{:next_event, :internal, {:maybe_process, file_path}}]}
    end
  end

  def handle_event(:info, {:file_event, worker_pid, :stop}, _, %{watchers: watchers} = data) do
    new_data =
      case Map.pop(watchers, worker_pid) do
        {path, new_watchers} when is_binary(path) ->
          {_, final_watchers} = Map.pop(new_watchers, path)
          %{data | watchers: final_watchers}

        {nil, _} ->
          data
      end
      |> synch_watchers()

    {:keep_state, new_data, [{:next_event, :internal, :set_status}]}
  end

  def handle_event(:info, :retry_watchers, _, data) do
    new_data =
      data
      |> synch_watchers()

    {:keep_state, new_data, []}
  end

  def handle_event({:call, from}, :status, state, %{reply_to: reply_to} = data) do
    case state do
      :ready -> {:keep_state_and_data, [{:reply, from, :ready}]}
      _ -> {:keep_state, %{data | reply_to: [from | reply_to]}, []}
    end
  end

  @doc false
  def add_dependencies(%{dependency_graph: dg} = data, file, dependencies) do
    new_dg =
      dependencies
      |> Enum.reduce(dg, fn dep, acc ->
        Map.update(acc, dep, [file], fn paths -> [file | paths] end)
      end)
      |> Map.update(file, [file], fn paths -> [file | paths] end)
      |> Enum.reduce(%{}, fn {k, v}, acc -> Map.put(acc, k, Enum.uniq(v)) end)

    %{data | dependency_graph: new_dg}
  end

  @doc false
  def synch_watchers(%{dependency_graph: dg, watchers: watchers} = data) do
    unique_watch_paths =
      dg
      |> Enum.reduce([], fn {k, v}, acc -> [k, v | acc] end)
      |> Enum.map(fn full_path -> Path.dirname(full_path) end)
      |> Enum.uniq()

    new_watchers =
      Enum.reduce(unique_watch_paths, watchers, fn path, acc ->
        case File.exists?(path) do
          true ->
            case Map.get(acc, path) do
              nil ->
                {:ok, pid} = FileSystem.start_link(dirs: [path])
                FileSystem.subscribe(pid)

                acc
                |> Map.put(path, pid)
                |> Map.put(pid, path)

              _ ->
                acc
            end

          false ->
            Logger.error("CSSEx Watcher: #{path} doesn't exist, retrying in 2secs")
            Process.send_after(self(), :retry_watchers, 2000)
            acc
        end
      end)

    %{data | watchers: new_watchers}
  end

  @doc false
  def parse_file(path, final_file, self_pid) do
    result = CSSEx.Parser.parse_file(nil, Path.dirname(path), Path.basename(path), final_file)

    send(self_pid, {:parsed, result})
  end

  @doc false
  # TODO check use cases with expand, perhaps it's not warranted?
  # when it's an absolute path probably not
  def assemble_path(<<"/", _::binary>> = path, _cwd), do: Path.expand(path)

  # but here yes, because files through plain "imports" in css/cssex might refer to relative paths, such as those in node_modules but also others using relative paths to indicate their source
  def assemble_path(path, cwd),
    do: Path.join([cwd, path]) |> Path.expand()
end
