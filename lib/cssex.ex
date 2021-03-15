defmodule CSSEx do
  @behaviour :gen_statem

  require Logger

  @timeout 15_000

  @enforce_keys [:entry_points]
  defstruct [
    :entry_points,
    watchers: %{},
    pretty_print: false,
    file_watch: false,
    dependency_graph: %{},
    monitors: %{},
    no_start: false,
    reply_to: []
  ]

  

  def start_link(%__MODULE__{} = config) do
    :gen_statem.start_link(__MODULE__, config, [])
  end

  @impl :gen_statem
  def callback_mode(), do: :handle_event_function

  @impl :gen_statem
  def init(%__MODULE__{} = config) do
    {:ok, :starting, config, [{:next_event, :internal, :start}]}
  end

  @impl :gen_statem
  def handle_event(:internal, :start, _, %{entry_points: entries} = data) do
    cwd = File.cwd!()
    self_pid = self()
    {new_monitors, new_entries}  =
      Enum.reduce(entries, {%{}, %{}}, fn({path, final}, {monitors_acc, entries_acc}) ->
	expanded_base =
	  case path do
	    "/" <> _ -> path
	    _ -> Path.expand(Path.join([cwd, path]))
	  end

	case !File.exists?(expanded_base) do
	  true ->
	    msg = "Couldn't find entry point #{expanded_base}" |> IO.inspect(label: "error")
	    Logger.error(msg)
	    exit(msg)
	  _ -> :ok
	end
	
	expanded_final =
	  case final do
	    "/" <> _ -> final
	    _ -> Path.expand(Path.join([cwd, final]))
	  end
	
	{_pid, monitor} = Process.spawn(
	  fn() ->
	    result = CSSEx.Parser.parse_file(Path.dirname(expanded_base), Path.basename(expanded_base))
	    send(self_pid, {:parsed, result})
	  end,
	  [:monitor]
	)

	{Map.put(monitors_acc, monitor, expanded_base), Map.put(entries_acc, expanded_base, expanded_final)}
      end)

    {:next_state, :processing, %{data | monitors: new_monitors, entry_points: new_entries}, [@timeout]}
  end

  def handle_event(:internal, {:process, file_path}, _, %{monitors: monitors} = data) do
    self_pid = self()
    {_pid, monitor} = Process.spawn(
      fn() ->
	result = CSSEx.Parser.parse_file(Path.dirname(file_path), Path.basename(file_path))
	send(self_pid, {:parsed, result})
      end,
      [:monitor]
    )
    
    new_monitors = Map.put(monitors, monitor, file_path)
    {:next_state, :processing, %{data | monitors: new_monitors}, [@timeout]}
  end

  def handle_event(:internal, {:post_process, parser, file_contents}, _, _data) do
    case parser do
      %CSSEx.Parser{valid?: true, warnings: [], file: file} ->
	{:keep_state_and_data, [{:next_event, :internal, {:save_file, file, file_contents}}]}
      %CSSEx.Parser{valid?: true, warnings: warnings, file: file} ->
	Enum.each(warnings, fn(warning) ->
	  Logger.warn(warning)
	end)
	{:keep_state_and_data, [{:next_event, :internal, {:save_file, file, file_contents}}]}
      %CSSEx.Parser{valid?: false, error: error} ->

	Logger.error(error)
	{:keep_state_and_data, []}
    end
  end

  def handle_event(:internal, {:save_file, file, file_contents}, _, %{entry_points: eps} = _data) do
    
    final_path = Map.get(eps, file)
    IO.inspect(final_path, label: "save_file")
    IO.inspect(file_contents, label: "file contents")
    case File.mkdir_p(Path.dirname(final_path)) do
      :ok ->
	case File.write(final_path, file_contents, [:write]) do
	  :ok -> {:keep_state_and_data, []}
	  {:error, error} ->
	    Logger.error("Error writing #{file} CSSEx output to #{final_path} ::: #{error}")
	    {:keep_state_and_data}
	end
      {:error, error} ->
	Logger.error("Error creating directories for #{file} CSSEx output to #{final_path} ::: #{error}")
	{:keep_state_and_data}
    end
  end

  def handle_event(:internal, :set_status, _, %{monitors: monitors} = data) do
    case monitors == %{} do
      true -> {:next_state, :ready, data, [{:next_event, :internal, :maybe_reply}]}
      _ -> {:next_state, :processing, data, []}
    end
  end

  def handle_event(:internal, :maybe_reply, :ready, %{reply_to: reply_to}) do
    to_reply = Enum.map(reply_to, fn(from) -> {:reply, from, :ready} end)

    {:keep_state_and_data, to_reply}
  end

  def handle_event(:internal, :maybe_reply, _, _), do: {:keep_state_and_data, []}

  def handle_event(:internal, {:maybe_process, file_path}, _, %{dependency_graph: dependency_graph, entry_points: eps}) do
    events =
      case Map.get(dependency_graph, file_path) do
	[] -> []
	deps ->
	  Enum.reduce(deps, [], fn(dep, acc) ->
	    case Map.get(eps, dep) do
	      nil -> acc
	      _-> [{:next_event, :internal, {:process, dep}} | acc]
	    end
	  end)
	  |> Enum.uniq()
      end

    {:keep_state_and_data, events}
  end

  def handle_event(:info, {:DOWN, ref, :process, _, _reason}, _, %{monitors: monitors} = data) do
    {_, new_monitors} = Map.pop(monitors, ref)
    {:keep_state, %{data | monitors: new_monitors}, [{:next_event, :internal, :set_status}]}
  end

  def handle_event(:info, {:parsed, parsed}, _, data) do
    case parsed do
      {:ok, %CSSEx.Parser{dependencies: dependencies, file: original_file} = parser, file_contents} ->
	new_data = (
	  data 
	  |> add_dependencies(original_file, dependencies)
	  |> synch_watchers()
	)

	{:keep_state, new_data, [{:next_event, :internal, {:post_process, parser, file_contents}}]}
				 
    end
  end

  def handle_event(:info, {:file_event, _worker_pid, {file_path, events}}, _, data) do
    case :modified in events do
      false -> {:keep_state_and_data, []}
      true -> {:next_state, :processing, data, [{:next_event, :internal, {:maybe_process, file_path}}]}
    end
  end


  def handle_event({:call, from}, :status, state, %{reply_to: reply_to} = data) do
    case state do
      :ready -> {:keep_state_and_data, [{:reply, from, :ready}]}
      _ -> {:keep_state, %{data | reply_to: [from | reply_to]}, []}
    end
  end

  def add_dependencies(%{dependency_graph: dg} = data, file, dependencies) do
    new_dg = (
      dependencies
      |> Enum.reduce(dg, fn(dep, acc) ->
	Map.update(acc, dep, [file], fn(paths) -> [file | paths] end)
      end)
      |> Map.update(file, [file], fn(paths) -> [file | paths] end)
      |> Enum.reduce(%{}, fn({k, v}, acc) -> Map.put(acc, k, Enum.uniq(v)) end)
    )

    %{data | dependency_graph: new_dg}
  end

  def synch_watchers(%{dependency_graph: dg, watchers: watchers} = data) do
    
    unique_watch_paths =
      Enum.reduce(dg, [], fn({_k, v}, acc) -> [v | acc] end)
      |> Enum.map(fn(full_path) -> Path.dirname(full_path) end)
      |> Enum.uniq()

    new_watchers =
      Enum.reduce(unique_watch_paths, watchers, fn(path, acc) ->
	case Map.get(acc, path) do
	  nil ->
	    {:ok, pid} = FileSystem.start_link(dirs: [path])
	    FileSystem.subscribe(pid)
	    Map.put(acc, path, pid)
	  _ ->
	    acc
	end
      end)

    %{data | watchers: new_watchers}
  end
  
end
