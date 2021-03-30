defmodule CSSEx.EEx.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  test "eex code blocks work" do
    assert {
             :ok,
             _,
             ".btn-op-1{background-color:rgba(255,0,0,0.1)}.btn-op-2{background-color:rgba(255,0,0,0.2)}.btn-op-3{background-color:rgba(255,0,0,0.3)}.btn-op-4{background-color:rgba(255,0,0,0.4)}.btn-op-5{background-color:rgba(255,0,0,0.5)}.btn-op-6{background-color:rgba(255,0,0,0.6)}.btn-op-7{background-color:rgba(255,0,0,0.7)}.btn-op-8{background-color:rgba(255,0,0,0.8)}.btn-op-9{background-color:rgba(255,0,0,0.9)}.btn-op-10{background-color:rgba(255,0,0,1.0)}\n"
           } =
             Parser.parse("""
             $!primary red;
             <%= for n <- 1..10, reduce: "" do
               acc ->
             [acc, ".btn-op-\#{n}", "{",
             	    "background-color: @fn::opacity(<$primary$>, \#{Float.round(n * 0.1, 1)})",
             	  "}"]
             end %>
             """)
  end

  test "eex block exceptions result in errors" do
    assert {:error, %Parser{error: error}} =
             Parser.parse("""
             <%= for n <- 1..0.1, reduce: "" do
               acc -> [acc, "\#{n}"]
             %>
             """)

    assert error =~ "invalid :eex declaration at l:1 col:1"
  end
end
