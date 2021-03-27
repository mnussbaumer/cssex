defmodule CSSEx.Comments.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  test "double slash comments" do
    assert {
             :ok,
             _,
             "div.test{color:blue;}div.test.another-one{color:black;font-family:sans-serif;}div .test{color:green;}div{color:red;}\n"
           } =
             Parser.parse("""
             @!width: 567px; // comment 0
             // comment 1
             div{
               color: red;
               &.test {
                 color: blue;
                 &.another-one {
                   color: black;
                 } // comment 2
               }
               .test {
                 color: green; // comment 3
               }
             }

             div.test.another-one{font-family: sans-serif;}
             """)
  end

  test "double slash and multi-line comments" do
    assert {
             :ok,
             _,
             "div.test{color:blue;}div.test.another-one{color:black;font-family:sans-serif;}div .test{color:green;}div{color:red;}\n"
           } =
             Parser.parse("""
             @!width: 567px; /* comment 0
             // comment 1
             */
             div{
               color: red;
               &.test {
                 color: blue;
                 &.another-one { /* comment 2

             */
                   color: black;
                 } // comment 4
               }
               .test { /* comment 5 */
                 color: green; // comment 3
               }
             }

             div.test.another-one{font-family: sans-serif;}
             """)
  end
end
