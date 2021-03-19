defmodule CSSEx.Error.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  test "non terminating var" do
    css = """
    %!width 576px
    div { color: red; }
    """
    
    assert {:error, {_, %{error: error}}} = Parser.parse(css)
    assert error =~ "invalid :assign declaration at l:1 col:1 to\" :: l:3 c:0"
  end

  test "invalid parens" do
    css_1 = """
    div[data-role=" { 
       color: red;
    }
    """
    
    assert {:error, {_, %{error: error}}} = Parser.parse(css_1)
    assert error =~ "unable to find terminator for \\\" at l:1 col:14 to\" :: l:4 c:0"

    css_2 = """
    div[data-role="test" { 
       color: red;
    }
    """
    
    assert {:error, {_, %{error: error}}} = Parser.parse(css_2)
    assert error =~ "unable to find terminator for [ at l:1 col:3 to\" :: l:4 c:0"
  end

  test "no close eex tag" do
    css = """
    div{color: orange;}
    <%= fuiuu

    sodjfjfgjg
    end
    """
    assert {:error, {_, %{error: error}}} = Parser.parse(css)
    assert error =~ "invalid :eex declaration at l:2 col:0 to\" :: l:6 c:0"
  end

  test "assign" do
    css = """
    @!test 1
    @!test 2;
    """

    assert {:error, {_, %{error: error}}} = Parser.parse(css)
    assert error =~ "invalid :variable declaration at l:1 col:1 to\" :: l:1 c:6"
  end

end
