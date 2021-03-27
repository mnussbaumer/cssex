defmodule CSSEx.Media.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  test "nested media generates the correct css rules and doesn't generate a media query nested into a selector" do
    assert {:ok, _, parsed} =
             Parser.parse("""
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
             """)

    assert parsed =~
             "@media screen and (max-width:600px){.test div.example{display:none;}.test{font-family:Arial;background-color:black;}}\n"

    assert parsed =~ ".test{color:red;}"
  end

  test "replacement of variables inside media works correctly" do
    assert {:ok, _,
            "@media print and (max-width:565px and min-width:300px), (min-width:565px){.test{color:blue;}}\n"} =
             Parser.parse("""
             @!max-width 565px;
             .test {
               @media print and (max-width: @$$max-width and min-width: 300px), (min-width: @$$max-width) {
                 color: blue;
               }
             }
             """)
  end

  test "nested media components compose" do
    assert {:ok, _,
            "@media print and (max-width:565px){.test{color:red;}}@media print and (max-width:565px) and (min-width:300px){.test.inner{color:blue;}.test{color:orange;}}\n"} =
             Parser.parse("""
             @!color orange;
             @!min_width 300px;
             @media print and (max-width: 565px) {
               .test { color: red;
             	@media and (min-width: <$min_width$>) {
                  &.inner { color: blue; }
             	   color: <$color$>;
               }
             }}
             """)
  end
end
