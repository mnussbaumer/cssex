defmodule CSSEx.Charset.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  @valid_charset ~s(@charset "UTF-8";)
  @invalid_charset """
  div { color: white; }

  @charset "UTF-8";
  """

  test "outputs the @charset rule as the first element of the spreadsheet" do
    assert {:ok, %{charset: "\"UTF-8\""}, "@charset \"UTF-8\";\n"} = Parser.parse(@valid_charset)
  end

  test "doesn't output the @charset rule if it's invalidly placed and emits warning" do
    assert {:ok, %{warnings: [warning]}, "div{color:white}\n"} = Parser.parse(@invalid_charset)

    assert warning =~ "@charset declaration must be the first rule in a spreadsheet"
  end
end
