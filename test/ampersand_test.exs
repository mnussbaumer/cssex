defmodule CSSEx.Ampersand.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  @basic """
  @!width: 567px;
  div{
    color: red;
    &.test {
      color: blue;
      &.another-one {
        color: black;
      }
    }
    .test {
      color: green;
    }
  }

  div.test.another-one{font-family: sans-serif;}
  """

  test "basic & works" do
    assert {:ok, _,
            "div.test{color:blue;}div.test.another-one{color:black;font-family:sans-serif;}div .test{color:green;}div{color:red;}\n"} =
             Parser.parse(@basic)
  end
end
