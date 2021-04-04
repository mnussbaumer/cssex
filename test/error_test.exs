defmodule CSSEx.Error.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  test "non terminating assign" do
    css = """
    $!width "576px"
    div { color: red; }
    """

    assert {:error, %{error: error}} = Parser.parse(css)
    assert error =~ "invalid :variable declaration at l:1 col:1 to\" :: l:1 c:12"
  end

  test "invalid parens" do
    css_1 = """
    div[data-role=" { 
       color: red;
    }
    """

    assert {:error, %{error: error}} = Parser.parse(css_1)
    assert error =~ "unable to find terminator for \\\" at l:1 col:14 to\" :: l:4 c:0"

    css_2 = """
    div[data-role="test" { 
       color: red;
    }
    """

    assert {:error, %{error: error}} = Parser.parse(css_2)
    assert error =~ "unable to find terminator for [ at l:1 col:3 to\" :: l:4 c:0"
  end

  test "no close eex tag" do
    css = """
    div{color: orange;}
    <%= fuiuu

    sodjfjfgjg
    end
    """

    assert {:error, %{error: error}} = Parser.parse(css)
    assert error =~ "invalid :eex declaration at l:2 col:0 to\" :: l:6 c:0"
  end

  test "variable" do
    css = """
    $!test 1
    $!test 2;
    """

    assert {:error, %{error: error}} = Parser.parse(css)
    assert error =~ "invalid :variable declaration at l:1 col:1 to\" :: l:1 c:6"
  end

  test "nested media bug #8 should provide an error" do
    assert {:error, %{error: error}} =
             Parser.parse("""
             @media only screen {
               header nav a {
                 display: block;
             	color: white;
             	text-decoration: none;

                 a:focus, a:hover {
                   color: #000;
             	};
               }
             }
             """)

    assert error =~ "unexpected token: ;  \" :: l:10 c:0"
  end

  test "it should error when nesting an html tag to another html tag" do
    assert {:error, %{error: error}} =
             Parser.parse("""
             div {
               &.test {
                 &p { color: red; }
               }
             }
             """)

    assert error =~
             "you're tring to concat an html element p to another html element div.test\" :: l:3 c:5"
  end

  test "it should error when & is used without being nested" do
    assert {:error, %{error: error}} =
             Parser.parse("""
             &.test {
               p { color: red; }
             }
             """)

    assert error =~ "\"you're tring to concat .test outside of a block\" :: l:2 c:3"
  end

  test "it should error when a postfix & is used without being nested" do
    assert {:error, %{error: error}} =
             Parser.parse("""
             .test& {
               &p { color: red; }
             }
             """)

    assert error =~ "\"you're tring to concat p.test outside of a block\" :: l:2 c:3"
  end

  test "invalid key val declarations" do
    assert {:error, %Parser{error: error}} = Parser.parse("div{color:}")

    assert error =~
             "invalid declaration of css rule where key -> color <- and value ->  <-\" :: l:1 c:4"

    assert {:error, %Parser{error: error}} = Parser.parse("div{:color:}")

    assert error =~ "\"unexpected token: color\" :: l:1 c:4"
  end
end
