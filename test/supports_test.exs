defmodule CSSEx.Supports.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  test "@supports" do
    assert {:ok, _,
            "@supports (display:grid){div{display:grid}}@supports (display:grid) and (not (display:inline-grid)){div{display:flex}}\n"} =
             Parser.parse("""
             @supports (display: grid) {
               div {
                  display: grid;
               }

               @supports and (not (display: inline-grid)) {
                 div { display: flex }
               }
             }

             """)
  end
end
