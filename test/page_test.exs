defmodule CSSEx.Page.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  test "@supports" do
    assert {:ok, _,
            "@page{margin:2cm;@top-left-corner{content:\"A\"}}@page :first{margin-top:4cm;@top-left-corner{text-align:start}}\n"} =
             Parser.parse("""
             @page {
               margin: 2cm;
               @top-left-corner {
                 content: "A"
               }
               @page :first {
                 margin-top: 4cm;
                 @top-left-corner {
                   text-align: start;
                 }
               }
             }
             """)
  end
end
