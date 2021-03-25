defmodule CSSEx.Function.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  @basic """
  @fn lighten_test(color, percentage) {
    {:ok, %CSSEx.HSLA{l: %CSSEx.Unit{value: l} = l_unit} = hsla} = 
                                                       CSSEx.HSLA.new_hsla(color)

    {percentage, _} = Float.parse(percentage)

    new_l = 
      case l + percentage do
         n_l when n_l <= 100 and n_l >= 0 -> n_l
  n_l when n_l > 100 -> 100
  n_l when n_l < 0 -> 0
      end

    {:ok, %CSSEx.HSLA{hsla | l: %CSSEx.Unit{l_unit | value: new_l}} |> to_string}
  };

  @!red red;
  .test{color: @fn::lighten_test(<$red$>, 10)}
  .test{color: @fn::lighten_test(#fdf, 10);}
  """

  test "basic declaration & works" do
    assert {
             :ok,
             _,
             ".test{color:hsla(0,100%,60%,1.0);color:hsla(300,7%,15%,1.0);}\n"
           } = Parser.parse(@basic)
  end

  test "'native' lighten" do
    assert {
             :ok,
             _,
             "div{color:hsla(0,100%,60%,1.0);}\n"
           } =
             Parser.parse("""
             @!test @fn::lighten(red, 10);
             div { color: <$test$>;}
             """)
  end

  test "'native' darken" do
    assert {
             :ok,
             _,
             "div{color:hsla(0,100%,40%,1.0);}\n"
           } =
             Parser.parse("""
             @!test @fn::darken(red, 10);
             div { color: <$test$>;}
             """)
  end

  test "'native' opacity" do
    assert {
             :ok,
             _,
             "div{color:rgba(255,0,0,0.6);}\n"
           } =
             Parser.parse("""
             @!test @fn::opacity(red, 0.6);
             div { color: <$test$>;}
             """)
  end
end
