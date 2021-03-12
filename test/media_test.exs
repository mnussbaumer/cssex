defmodule CSSEx.Media.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  @base_nested """
  .test {
    @media screen and (max-width: 600px) {
      div.example {
        display: none;
      }

      font-family: Arial;
    }
        	
    color: red;
  }

  @media screen and (max-width: 600px) {
    .test { background-color: black; }
  }
  """

  @vars_in_media_declaration """
  @!max-width 565px;
  .test {
    @media print and (max-width: @$$max-width and min-width: 300px), (min-width: @$$max-width) {
      color: blue;
    }
  }
  """
  
  test "nested media generates the correct css rules and doesn't generate a media query nested into a selector" do

    assert {:ok, _, parsed} = Parser.parse(@base_nested)
    
    [
      "@media screen and (max-width:600px){.test{font-family:Arial;background-color:black;}.test div.example{display:none;}}\n",
      ".test{color:red;}",
    ]
    |> Enum.each(fn(verification) ->
      assert parsed =~ verification
    end)
  end

  test "replacement of variables inside media works correctly" do
    assert {:ok, _, "@media print and (max-width:565px and min-width:300px), (min-width:565px){.test{color:blue;}}\n"} = Parser.parse(@vars_in_media_declaration)
  end
end
