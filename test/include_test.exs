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
    assert {:ok, _,
            ".test:required,.test:invalid,.test:enabled,.test:disabled,.test:focus,.test:active,.test:hover{outline:0;border:0;box-shadow:0;}.btn-lg{font-size:24px;line-height:24px;height:38.4px;min-height:38.4px;}.btn-md{font-size:18px;line-height:18px;height:28.8px;min-height:28.8px;}.btn-sm{font-size:12px;line-height:12px;height:19.2px;min-height:19.2px;}.test{outline:0;border:0;box-shadow:0;}.btn-xxl{font-size:40px;line-height:40px;height:64.0px;min-height:64.0px;}:root{--black:black;--error:#ff2100;--info:#00A6E0;--primary:#ee483e;--secondary:#2d4049;--success:#4ad887;--tertiary:rgb(255, 235, 155);--text:#152734;--warning:#E07000;--white:white;}.btn-xl{font-size:36px;line-height:36px;height:57.6px;min-height:57.6px;}\n"} =
             Parser.parse_file(base_path, original_file)
  end
end
