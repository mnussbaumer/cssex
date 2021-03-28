defmodule CSSEx.Include.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  setup do
    {:ok, cwd} = File.cwd()
    root = Path.join([cwd, "test", "files", "includes", "simples"])
    final_base = Path.join([root, "output"])

    assert {:ok, _} = File.rm_rf(final_base)
    refute File.exists?(final_base)

    original_file = Path.join([root, "simples.cssex"])
    final_file = Path.join([final_base, "simples.css"])

    assert {:ok, _} = File.rm_rf(final_base)
    refute File.exists?(final_base)

    assert :ok = File.mkdir(final_base)
    assert File.exists?(final_base)

    {:ok, %{base_path: root, original_file: original_file, final_file: final_file}}
  end

  test "parsing simples", %{
    base_path: base_path,
    original_file: original_file,
    final_file: final_file
  } do
    assert {:ok, _, result} = Parser.parse_file(base_path, original_file)

    # IO.inspect(result, limit: :infinity, printable_limit: :infinity)
  end
end
