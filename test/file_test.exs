defmodule CSSEx.File.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  test "parses a file" do
    {:ok, cwd} = File.cwd()
    final_path = Path.join([cwd, "test", "files", "originals", "test_1.cssex"])

    assert {:ok, _, parsed} = Parser.parse_file(final_path)
    IO.inspect(parsed)
  end
end
