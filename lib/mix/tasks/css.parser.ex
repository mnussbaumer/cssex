defmodule Mix.Tasks.Cssex.Parser do
  use Mix.Task
  require Logger

  @moduledoc """
  Task to parse cssex files into css files.
  You can use two types of flags, --e (and additionally --a) or --c.

  For the --e flag you use any number of

  --e path/to_cssex/file.cssex=path/to_css/output.css

  And if you want those paths to be relative to some application you can pass it with --m

  --a myapp_web

  arguments to specify each entry and its output file, or a single path to the cssex where the output file will be in the same directory, with the same file name but the extension css added to it

  --e path/to_cssex/file.cssex

  The --c flag is used to indicate an entry in the config of the application, in order to read the entry points from there

  --c myapp_web
  """
  def run([]),
    do:
      error(
        "either specify the file paths with --e cssex/file.cssex=output/file.css, and/or the --a application flag or a module from where to load a CSSEx config, with --c myapp_web",
        64
      )

  def run(["--c", app_string]) do
    app = String.to_atom(app_string)
    dir = Application.app_dir(app)
    env = Application.get_env(app, CSSEx)

    case not is_nil(env) && CSSEx.make_config(env, dir) do
      %CSSEx{entry_points: [_ | _]} = config ->
        do_run(config)

      _ ->
        error(
          "loading default entry points for app: #{app}. The retrieved config was: #{env} - where instead it was expected a keyword list with an :entry_points entry specifying at least one file",
          1
        )
    end
  end

  def run(args) do
    {options, _, _} = OptionParser.parse(args, strict: [e: :keep, a: :string])

    {module, opts} = Keyword.pop_first(options, :a, false)

    eps =
      Enum.reduce(opts, [], fn {_, paths}, acc ->
        case String.split(paths, "=", trim: true) do
          [from, to] ->
            [{from, to} | acc]

          [from] ->
            [{from, String.replace(from, ".cssex", ".css")} | acc]

          _ ->
            error("invalid paths #{paths}", 64)
        end
      end)

    dir =
      case module do
        false ->
          nil

        _ ->
          String.to_atom(module)
          |> Application.app_dir()
      end

    case length(eps) > 0 do
      true ->
        CSSEx.make_config([entry_points: eps], dir)
        |> do_run()

      false ->
        error("no paths given", 64)
    end
  end

  defp do_run(%CSSEx{entry_points: eps}) do
    cwd = File.cwd!()

    tasks =
      for {path, final} <- eps do
        expanded_base = CSSEx.assemble_path(path, cwd)
        expanded_final = CSSEx.assemble_path(final, cwd)

        Task.async(fn ->
          result =
            CSSEx.Parser.parse_file(Path.dirname(expanded_base), Path.basename(expanded_base))

          {result, expanded_base, expanded_final}
        end)
      end

    processed = Task.yield_many(tasks, 60_000)

    Enum.map(processed, fn
      {_, {:ok, {{:ok, %{valid?: true}, content}, base, final}}} ->
        try_write(base, final, content)

      {_, {:ok, {{:error, %{error: error}}, _, _}}} ->
        error(error)

      error ->
        error(error)
    end)

    case Enum.all?(processed, fn
           {_, {task_res, {{processed_res, _, _}, _, _}}} ->
             task_res == :ok and processed_res == :ok

           _ ->
             false
         end) do
      true -> :ok
      _ -> exit({:shutdown, 1})
    end
  end

  defp try_write(base, path, content) do
    with(
      :ok <- File.mkdir_p(Path.dirname(path)),
      :ok <- File.write(path, content, [:write])
    ) do
      ok(base, path)
    else
      error ->
        error(error)
    end
  end

  defp error(msg, code) do
    error(msg)
    exit({:shutdown, code})
  end

  defp error(msg), do: Logger.error("ERROR :: #{inspect(msg)}")
  defp ok(base, file), do: Logger.info("PROCESSED :: #{base} into #{inspect(file)}")
end
