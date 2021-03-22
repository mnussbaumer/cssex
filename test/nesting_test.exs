defmodule CSSEx.Nesting.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  test "complex nestings" do
    css = """

    .div_1 {
      color: red;
      .div_1_a, .div_1_b {
        color: blue;
      }

      &.div_2_a, .div_2_b {
        width: 100%;
      	&.div_2_a_a {
      	  height: 100%;
            .inner-inner {
               display: block;
      	    }
        }
      	padding: 5px;
      }
      
      .div_1_a, &.div_3_b {
        margin: 10px;
      }
    }

    .box-1, .box-2, .box-3 {
      color: magenta;
      &.box-4, .box-5 {
        height: 50px;
      }
    }
    """

    assert {:ok, _, parsed} = Parser.parse(css)

    assert parsed =~ ".div_1{color:red;}"
    assert parsed =~ ".div_1 .div_1_a{color:blue;margin:10px;}"
    assert parsed =~ ".div_1 .div_1_b{color:blue;}"
    assert parsed =~ ".div_1.div_2_a{width:100%;padding:5px;}"
    assert parsed =~ ".div_1.div_2_a.div_2_a_a{height:100%;}"
    assert parsed =~ ".div_1.div_2_a.div_2_a_a .inner-inner{display:block;}"
    assert parsed =~ ".div_1.div_3_b{margin:10px;}"

    # this needs to be better 
    assert parsed =~ ".box-1, .box-2, .box-3{color:magenta;}"
    assert parsed =~ ".box-1.box-4{height:50px;}"
    assert parsed =~ ".box-1 .box-5{height:50px;}"

    assert parsed =~ ".box-2.box-4{height:50px;}"
    assert parsed =~ ".box-2 .box-5{height:50px;}"

    assert parsed =~ ".box-3.box-4{height:50px;}"
    assert parsed =~ ".box-3 .box-5{height:50px;}"
  end
end
