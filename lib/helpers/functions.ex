defmodule CSSEx.Helpers.Functions do
  @moduledoc false

  def lighten(_ctx_content, color, percentage) do
    {
      :ok,
      %CSSEx.HSLA{l: %CSSEx.Unit{value: l} = l_unit} = hsla
    } = CSSEx.HSLA.new_hsla(color)

    {percentage, _} = Float.parse(percentage)

    new_l =
      case l + percentage do
        n_l when n_l <= 100 and n_l >= 0 -> n_l
        n_l when n_l > 100 -> 100
        n_l when n_l < 0 -> 0
      end

    %CSSEx.HSLA{hsla | l: %CSSEx.Unit{l_unit | value: new_l}}
    |> to_string
  end

  def darken(_ctx_content, color, percentage) do
    {
      :ok,
      %CSSEx.HSLA{l: %CSSEx.Unit{value: l} = l_unit} = hsla
    } = CSSEx.HSLA.new_hsla(color)

    {percentage, _} = Float.parse(percentage)

    new_l =
      case l - percentage do
        n_l when n_l <= 100 and n_l >= 0 -> n_l
        n_l when n_l > 100 -> 100
        n_l when n_l < 0 -> 0
      end

    %CSSEx.HSLA{hsla | l: %CSSEx.Unit{l_unit | value: new_l}}
    |> to_string
  end

  def opacity(_ctx_content, color, alpha) do
    {:ok, %CSSEx.RGBA{} = rgba} = CSSEx.RGBA.new_rgba(color)

    {parsed_alpha, _} = Float.parse(alpha)

    n_alpha =
      case parsed_alpha do
        n when n <= 1 and n >= 0 -> n
        n when n > 1 -> 1
        n when n < 0 -> 0
      end

    %CSSEx.RGBA{rgba | a: n_alpha}
    |> to_string()
  end
end
