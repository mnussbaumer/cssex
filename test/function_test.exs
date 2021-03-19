defmodule CSSEx.Function.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  @basic """
  @fn lighten(color, percentage) {
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
  .test{color: @fn::lighten(<$red$>, 10)}
  .test{color: @fn::lighten(#fdf, 10);}
  """

  test "basic & works" do
    assert {
      :ok,
      _,
      ".test{color:hsla(0,100%,60%,1.0);color:hsla(300,7%,15%,1.0);}\n"
    } = Parser.parse(@basic)
  end
end
