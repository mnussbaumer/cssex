defmodule CSSEx.Keyframes.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  @basic """
  .test{
    color: red;
    font-family: Arial, sans-serif;
  }

  @keyframes mysummer {
    0% { top:0px;left: 20px; }
    100%{left:0px; top:20px}
  }

  @keyframes mywinter {
    0% { top:0px;left: 20px; }
    100%{left:0px; top:20px}
  }

  div{color: blue;}
  """

  test "basic keyframes test" do
    assert {:ok, _,
            ".test{color:red;font-family:Arial, sans-serif}div{color:blue}@keyframes mysummer{0%{top:0px;left:20px}100%{left:0px;top:20px}}@keyframes mywinter{0%{top:0px;left:20px}100%{left:0px;top:20px}}\n"} =
             Parser.parse(@basic)
  end
end
