defmodule CSSEx.Task.Test do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  @root "test/files/task"
  @base "original.cssex"
  @base_2 "original_2.cssex"
  @dest_path "finished/base.css"
  @dest_path_2 "finished/base_2.css"
  @dest_same String.replace(@base, ".cssex", ".css")
  @no_bueno_path "/no/bueno/path.cssex"

  setup do
    {:ok, cwd} = File.cwd()

    root = Path.join([cwd, @root])

    base_path = Path.join([root, @base])
    assert File.exists?(base_path)

    base_path_2 = Path.join([root, @base_2])
    assert File.exists?(base_path_2)

    dest_path = Path.join([root, @dest_path])
    dest_path_2 = Path.join([root, @dest_path_2])
    dest_same_path = Path.join([root, @dest_same])

    assert {:ok, _} = File.rm_rf(dest_path)
    assert {:ok, _} = File.rm_rf(dest_path_2)
    assert {:ok, _} = File.rm_rf(dest_same_path)

    refute File.exists?(dest_path)
    refute File.exists?(dest_path_2)
    refute File.exists?(dest_same_path)

    base_without_cwd = Path.join(["../../../..", @root, @base])
    base_2_without_cwd = Path.join(["../../../..", @root, @base_2])
    dest_without_cwd = Path.join(["../../../..", @root, @dest_path])
    dest_2_without_cwd = Path.join(["../../../..", @root, @dest_path_2])

    entry_points_1 = [{base_without_cwd, dest_without_cwd}]
    entry_points_2 = [{base_2_without_cwd, dest_2_without_cwd} | entry_points_1]

    {:ok,
     %{
       base_path: base_path,
       base_path_2: base_path_2,
       dest_path: dest_path,
       dest_path_2: dest_path_2,
       dest_same_dest: dest_same_path,
       base_without: base_without_cwd,
       dest_without: dest_without_cwd,
       entry_points_1: entry_points_1,
       entry_points_2: entry_points_2
     }}
  end

  test "processing with flag --c works", %{
    entry_points_1: eps,
    base_path: base_path,
    dest_path: dest_path
  } do
    Application.put_env(:cssex, CSSEx, entry_points: eps)

    assert capture_log(fn ->
             Mix.Tasks.Cssex.Parser.run(["--c", "cssex"])
           end) =~ "PROCESSED :: #{base_path} into \"#{dest_path}"

    assert {:ok, "div.test{color:red}\n"} = File.read(dest_path)
  end

  test "processing with flag --c and multiple entry points works", %{
    entry_points_2: eps,
    base_path: base_path,
    dest_path: dest_path,
    base_path_2: base_path_2,
    dest_path_2: dest_path_2
  } do
    Application.put_env(:cssex, CSSEx, entry_points: eps)

    assert capture =
             capture_log(fn ->
               Mix.Tasks.Cssex.Parser.run(["--c", "cssex"])
             end)

    assert capture =~ "PROCESSED :: #{base_path} into \"#{dest_path}"
    assert capture =~ "PROCESSED :: #{base_path_2} into \"#{dest_path_2}"

    assert {:ok, "div.test{color:red}\n"} = File.read(dest_path)
    assert {:ok, "div.test{color:blue}\n"} = File.read(dest_path_2)
  end

  test "processing with flag --c and multiple entry points, one of which bad, exits with error",
       %{
         entry_points_2: eps,
         base_path: base_path,
         dest_path: dest_path,
         base_path_2: base_path_2,
         dest_path_2: dest_path_2
       } do
    new_eps = [{@no_bueno_path, String.replace(@no_bueno_path, ".cssex", ".css")} | eps]
    Application.put_env(:cssex, CSSEx, entry_points: new_eps)

    assert capture =
             capture_log(fn ->
               try do
                 Mix.Tasks.Cssex.Parser.run(["--c", "cssex"])
               catch
                 :exit, {:shutdown, 1} -> :ok
               end
             end)

    assert capture =~ "PROCESSED :: #{base_path} into \"#{dest_path}"
    assert capture =~ "PROCESSED :: #{base_path_2} into \"#{dest_path_2}"
    assert capture =~ "ERROR :: \"\\\"unable to find file"
    assert capture =~ @no_bueno_path

    assert {:ok, "div.test{color:red}\n"} = File.read(dest_path)
    assert {:ok, "div.test{color:blue}\n"} = File.read(dest_path_2)
  end

  test "processing with flag --e works", %{base_path: base_path, dest_path: dest_path} do
    assert capture_log(fn ->
             Mix.Tasks.Cssex.Parser.run(["--e", "#{base_path}=#{dest_path}"])
           end) =~ "PROCESSED :: #{base_path} into \"#{dest_path}"

    assert {:ok, "div.test{color:red}\n"} = File.read(dest_path)
  end

  test "processing with flag --e and --a works", %{
    base_path: base_path,
    base_without: base_without,
    dest_without: dest_without,
    dest_path: dest_path
  } do
    assert capture_log(fn ->
             Mix.Tasks.Cssex.Parser.run(["--e", "#{base_without}=#{dest_without}", "--a", "cssex"])
           end) =~ "PROCESSED :: #{base_path} into \"#{dest_path}"

    assert {:ok, "div.test{color:red}\n"} = File.read(dest_path)
  end

  test "processing with flag --e and only origin path works", %{
    base_path: base_path,
    dest_same_dest: dest_path
  } do
    assert capture_log(fn ->
             Mix.Tasks.Cssex.Parser.run(["--e", "#{base_path}"])
           end) =~ "PROCESSED :: #{base_path} into \"#{dest_path}"

    assert {:ok, "div.test{color:red}\n"} = File.read(dest_path)
  end

  test "processing with flag --e and --a and only origin path works", %{
    base_path: base_path,
    base_without: base_without,
    dest_same_dest: dest_path
  } do
    assert capture_log(fn ->
             Mix.Tasks.Cssex.Parser.run(["--e", "#{base_without}", "--a", "cssex"])
           end) =~ "PROCESSED :: #{base_path} into \"#{dest_path}"

    assert {:ok, "div.test{color:red}\n"} = File.read(dest_path)
  end

  test "errors out with invalid paths" do
    assert capture =
             capture_log(fn ->
               try do
                 Mix.Tasks.Cssex.Parser.run(["--e", @no_bueno_path, "--a", "cssex"])
               catch
                 :exit, {:shutdown, 1} -> :ok
               end
             end)

    assert capture =~ "ERROR :: \"\\\"unable to find file"
    assert capture =~ @no_bueno_path
  end

  test "errors out without options" do
    assert captured =
             capture_log(fn ->
               try do
                 Mix.Tasks.Cssex.Parser.run([])
               catch
                 :exit, {:shutdown, 64} -> :ok
               end
             end)

    assert captured =~ "ERROR ::"
    assert captured =~ "specify the file paths"
  end

  test "errors with invalid options" do
    assert captured =
             capture_log(fn ->
               try do
                 Mix.Tasks.Cssex.Parser.run(["--d"])
               catch
                 :exit, {:shutdown, 64} -> :ok
               end
             end)

    assert captured =~ "ERROR ::"
    assert captured =~ "no paths given"
  end
end
