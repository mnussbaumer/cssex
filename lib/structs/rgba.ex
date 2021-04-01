defmodule CSSEx.RGBA do
  @moduledoc """
  Struct and helper functions for generating RGBA values.
  """

  @colors CSSEx.Helpers.Colors.colors_tuples()
  alias CSSEx.Unit

  defstruct r: 0, g: 0, b: 0, a: 1

  @type t() :: %CSSEx.RGBA{
          r: non_neg_integer,
          g: non_neg_integer,
          b: non_neg_integer,
          a: non_neg_integer
        }

  @doc """
  Accepts any value in the form of a binary `"hsla(0, 10%, 20%, 0.5)"` or `"hsl(0, 10%, 20%)"`, any hexadecimal representation in binary in the form of `"#xxx"`, `"#xxxx"`, `"#xxxxxx"` or `"#xxxxxxxx"`, rgb/a as `"rgba(100,100,100,0.1)"` or `"rgb(10,20,30)"`, or any literal color name defined as web colors (CSSEx.Colors) - returns a `%CSSEx.HSLA{}` struct.
  """
  def new_rgba(<<"rgba", values::binary>>) do
    case Regex.run(~r/\((.+),(.+),(.+),(.+)\)/, values) do
      [_, r, g, b, a] ->
        new(
          String.trim(r),
          String.trim(g),
          String.trim(b),
          String.trim(a)
        )

      _ ->
        {:error, :invalid}
    end
  end

  def new_rgba(<<"rgb", values::binary>>) do
    case Regex.run(~r/\((.+),(.+),(.+)\)/, values) do
      [_, r, g, b] ->
        new(
          String.trim(r),
          String.trim(g),
          String.trim(b),
          "1"
        )

      _ ->
        {:error, :invalid}
    end
  end

  def new_rgba(<<"hsla", _::binary>> = full) do
    case CSSEx.HSLA.new_hsla(full) do
      {:ok, %CSSEx.HSLA{} = hsla} -> from_hsla(hsla)
      error -> error
    end
  end

  def new_rgba(<<"hsl", _::binary>> = full) do
    case CSSEx.HSLA.new_hsla(full) do
      {:ok, %CSSEx.HSLA{} = hsla} -> from_hsla(hsla)
      error -> error
    end
  end

  def new_rgba(<<"#", hex::binary>>) do
    case hex do
      <<r::binary-size(2), g::binary-size(2), b::binary-size(2), a::binary-size(2)>> ->
        new(r, g, b, a, 16)

      <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>> ->
        new(r, g, b, "100", 16)

      <<r::binary-size(1), g::binary-size(1), b::binary-size(1), a::binary-size(1)>> ->
        new(r, g, b, a, 16)

      <<r::binary-size(1), g::binary-size(1), b::binary-size(1)>> ->
        new(r, g, b, "100", 16)

      _ ->
        {:error, :invalid}
    end
  end

  Enum.each(@colors, fn [color, rgba] ->
    def new_rgba(unquote(color)), do: new_rgba(unquote(rgba))
  end)

  @doc """
  Converts an existing `%CSSEx.HSLA{}` struct into a `%CSSEx.RGBA{}` struct.
  Taken from https://www.niwa.nu/2013/05/math-behind-colorspace-conversions-rgb-hsl
  """
  def from_hsla(%CSSEx.HSLA{s: %Unit{value: 0}, l: %Unit{value: l}, a: a}) do
    gray = l / 100 * 255
    {:ok, %CSSEx.RGBA{r: gray, g: gray, b: gray, a: a}}
  end

  def from_hsla(%CSSEx.HSLA{h: %Unit{value: h}, s: %Unit{value: s}, l: %Unit{value: l}, a: a}) do
    n_l = (l / 100) |> Float.round(3)
    n_s = (s / 100) |> Float.round(3)

    convert_val_1 =
      case n_l >= 0.5 do
        true -> n_l + n_s - n_l * n_s
        _ -> n_l * (1 + n_s)
      end
      |> Float.round(3)

    convert_val_2 = (2 * n_l - convert_val_1) |> Float.round(3)
    hue_norm = (h / 360) |> Float.round(3)

    r = hue_norm + 0.333
    r_1 = if(r >= 0, do: if(r > 1, do: r - 1, else: r), else: r + 1)
    g = hue_norm
    g_1 = if(g >= 0, do: if(g > 1, do: g - 1, else: g), else: g + 1)
    b = hue_norm - 0.333
    b_1 = if(b >= 0, do: if(b > 1, do: b - 1, else: b), else: b + 1)

    red = convert_color_chan(convert_val_1, convert_val_2, r_1) * 255
    green = convert_color_chan(convert_val_1, convert_val_2, g_1) * 255
    blue = convert_color_chan(convert_val_1, convert_val_2, b_1) * 255

    {:ok,
     %__MODULE__{
       r: round(red),
       g: round(green),
       b: round(blue),
       a: a
     }}
  end

  @doc """
  Generates a `%CSSEx.RGBA{}` wrapped in an :ok tuple, from the values of r, g, b, and alpha. All values are treated as decimal by default but another base can be provided as an optional argument.
  """
  def new(r, g, b, a, base \\ 10),
    do: {
      :ok,
      %__MODULE__{
        r: color_value(r, base),
        g: color_value(g, base),
        b: color_value(b, base),
        a: alpha_value(a, base)
      }
    }

  @doc false
  def color_value(val, base) when is_binary(val) do
    case Integer.parse(val, base) do
      {parsed, _} -> valid_rgb_val(parsed)
      :error -> 0
    end
  end

  @doc false
  def alpha_value(val, 10) do
    case Float.parse(val) do
      {parsed, _} -> valid_alpha_val(parsed)
      :error -> 1
    end
  end

  def alpha_value(val, 16) do
    case Integer.parse(val, 16) do
      {parsed, _} -> valid_alpha_val(parsed / 256)
      :error -> 1
    end
  end

  @doc false
  def valid_rgb_val(n) when n <= 255 and n >= 0, do: n
  def valid_rgb_val(n) when n > 255, do: 255
  def valid_rgb_val(n) when n < 0, do: 0

  @doc false
  def valid_alpha_val(n) when n > 0 and n <= 1, do: n
  def valid_alpha_val(_n), do: 1

  @doc false
  def convert_color_chan(pass_1, pass_2, temp_color) do
    case {6 * temp_color < 1, 2 * temp_color < 1, 3 * temp_color < 2} do
      {true, _, _} -> pass_2 + (pass_1 - pass_2) * 6 * temp_color
      {_, true, _} -> pass_1
      {_, _, true} -> pass_2 + (pass_1 - pass_2) * (0.666 - temp_color) * 6
      _ -> pass_2
    end
  end
end

defimpl String.Chars, for: CSSEx.RGBA do
  def to_string(%CSSEx.RGBA{r: r, g: g, b: b, a: a}), do: "rgba(#{r},#{b},#{g},#{a})"
end
