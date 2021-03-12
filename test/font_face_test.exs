defmodule CSSEx.FontFace.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  @basic_font_face """
  div {
    color: black;
  }
  @font-face {
    font-family: "Open-Sans";
    src: url("/test.ttf") format("ttf");
  }
  .test{
    color: red;
  }

  @font-face {
    font-family: "Test";
    src: url("/test.woff") format("woff");
  }
  """
  test "top-level declarations of font-faces work correctly" do
    assert {:ok, _, "@font-face{font-family:\"Test\";src:url(\"/test.woff\") format(\"woff\");}@font-face{font-family:\"Open-Sans\";src:url(\"/test.ttf\") format(\"ttf\");}.test{color:red;}div{color:black;}\n"} = Parser.parse(@basic_font_face)
  end
end
