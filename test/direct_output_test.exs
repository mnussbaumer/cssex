defmodule CSSEx.DirectOutput.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  setup do
    {:ok, cwd} = File.cwd()
    final_base = Path.join([cwd, "test", "files", "direct_output"])

    assert {:ok, _} = File.rm_rf(final_base)
    refute File.exists?(final_base)

    assert :ok = File.mkdir(final_base)
    assert File.exists?(final_base)

    final_file = Path.join([final_base, "final.css"])

    on_exit(fn -> File.rm_rf!(final_base) end)

    {:ok, %{base_path: final_base, final_file: final_file}}
  end

  test "parsing with direct output to file", %{final_file: final_file} do
    assert {:ok, _, []} = Parser.parse(nil, "div{color:red;}", final_file)
    assert File.read!(final_file) =~ "div{color:red}\n"
  end
end
