defmodule CSSEx.HSLA do
  alias CSSEx.Unit

  @moduledoc """
  Struct and helper functions for generating HSLA values.
  """
  defstruct h: %Unit{value: 0, unit: nil},
            s: %Unit{value: 0, unit: "%"},
            l: %Unit{value: 0, unit: "%"},
            a: 1

  @type t() :: %CSSEx.HSLA{
          h: non_neg_integer,
          s: non_neg_integer,
          l: non_neg_integer,
          a: non_neg_integer
        }

  @colors CSSEx.Helpers.Colors.colors_tuples()

  @doc """
  Accepts any value in the form of a binary `"hsla(0, 10%, 20%, 0.5)"` or `"hsl(0, 10%, 20%)"`, any hexadecimal representation in binary in the form of `"#xxx"`, `"#xxxx"`, `"#xxxxxx"` or `"#xxxxxxxx"`, rgb/a as `"rgba(100,100,100,0.1)"` or `"rgb(10,20,30)"`, or any literal color name defined as web colors (CSSEx.Colors) - returns a `%CSSEx.HSLA{}` struct.
  """
  @spec new_hsla(String.t()) :: {:ok, %CSSEx.HSLA{}} | {:error, term}
  def new_hsla(<<"hsla", values::binary>>) do
    case Regex.run(~r/\((.+),(.+),(.+),(.+)\)/, values) do
      [_, h, s, l, a] ->
        new(
          String.trim(h),
          String.trim(s),
          String.trim(l),
          String.trim(a)
        )

      _ ->
        {:error, :invalid}
    end
  end

  def new_hsla(<<"hsl", values::binary>>) do
    case Regex.run(~r/\((.+),(.+),(.+)\)/, values) do
      [_, h, s, l] ->
        new(
          String.trim(h),
          String.trim(s),
          String.trim(l),
          "1"
        )

      _ ->
        {:error, :invalid}
    end
  end

  def new_hsla(<<"rgb", _::binary>> = full) do
    case CSSEx.RGBA.new_rgba(full) do
      {:ok, rgba} -> from_rgba(rgba)
      error -> error
    end
  end

  def new_hsla(<<"#", _::binary>> = full) do
    case CSSEx.RGBA.new_rgba(full) do
      {:ok, rgba} -> from_rgba(rgba)
      error -> error
    end
  end

  Enum.each(@colors, fn [color, rgba] ->
    def new_hsla(unquote(color)) do
      case CSSEx.RGBA.new_rgba(unquote(rgba)) do
        {:ok, new_rgba} -> from_rgba(new_rgba)
        error -> error
      end
    end
  end)

  @doc """
  Converts an existing `%CSSEx.RGBA{}` struct into a `%CSSEx.HSLA{}` struct.
  Taken from https://www.niwa.nu/2013/05/math-behind-colorspace-conversions-rgb-hsl/
  """
  @spec from_rgba(%CSSEx.RGBA{}) :: {:ok, %CSSEx.HSLA{}}
  def from_rgba(%CSSEx.RGBA{r: r, g: g, b: b, a: a}) do
    n_r = r / 255
    n_g = g / 255
    n_b = b / 255

    {min, max} = Enum.min_max([n_r, n_g, n_b])

    luminance = (min + max) / 2 * 100

    saturation =
      case {min, max} do
        {same, same} -> 0
        {min, max} when luminance <= 50 -> (max - min) / (max + min) * 100
        {min, max} -> (max - min) / (2 - max - min) * 100
      end

    hue =
      case {n_r, n_g, n_b} do
        {same, same, same} -> 0
        {n_r, n_g, n_b} when n_r > n_g and n_r > n_b -> (n_g - n_b) / (max - min)
        {n_r, n_g, n_b} when n_g > n_r and n_g > n_b -> 2 + (n_b - n_r) / (max - min)
        {n_r, n_g, _n_b} -> 4 + (n_r - n_g) / (max - min)
      end

    hue_2 =
      case hue * 60 do
        new_hue when new_hue < 0 -> new_hue + 360
        new_hue -> new_hue
      end

    {:ok,
     %__MODULE__{
       h: %Unit{value: round(hue_2), unit: nil},
       s: %Unit{value: round(saturation), unit: "%"},
       l: %Unit{value: round(luminance), unit: "%"},
       a: a
     }}
  end

  @doc """
  Generates a `%CSSEx.HSLA{}` wrapped in an :ok tuple, from the values of h, s, l, and alpha. All values are treated as decimal.
  """
  def new(h, s, l, a),
    do: {
      :ok,
      %__MODULE__{
        h: new_hue(h),
        s: new_saturation(s),
        l: new_luminance(l),
        a: alpha_value(a, 10)
      }
    }

  @doc false
  def new_hue(val) when is_binary(val) do
    case Integer.parse(val, 10) do
      {parsed, _} -> valid_hue_val(parsed)
      :error -> %Unit{value: 0, unit: nil}
    end
  end

  def new_hue(val) when is_integer(val) or is_float(val), do: valid_hue_val(val)

  @doc false
  def new_saturation(val) when is_binary(val) do
    case Integer.parse(val, 10) do
      {parsed, _} -> valid_saturation_val(parsed)
      :error -> %Unit{value: 0, unit: "%"}
    end
  end

  def new_saturation(val) when is_integer(val) or is_float(val),
    do: valid_saturation_val(val)

  @doc false
  def new_luminance(val) when is_binary(val) do
    case Integer.parse(val, 10) do
      {parsed, _} -> valid_luminance_val(parsed)
      :error -> %Unit{value: 0, unit: "%"}
    end
  end

  def new_luminance(val) when is_integer(val) or is_float(val),
    do: valid_luminance_val(val)

  @doc false
  def alpha_value(val, 10) do
    case Float.parse(val) do
      {parsed, _} -> valid_alpha_val(parsed)
      :error -> 1
    end
  end

  @doc false
  def valid_hue_val(n) when n <= 360 and n >= 0, do: %Unit{value: n, unit: nil}
  def valid_hue_val(_n), do: %Unit{value: 0, unit: nil}

  @doc false
  def valid_saturation_val(n) when n <= 100 and n >= 0, do: %Unit{value: n, unit: "%"}
  def valid_saturation_val(_n), do: %Unit{value: 0, unit: "%"}

  @doc false
  def valid_luminance_val(n) when n <= 100 and n >= 0, do: %Unit{value: n, unit: "%"}
  def valid_luminance_val(_n), do: %Unit{value: 0, unit: "%"}

  @doc false
  def valid_alpha_val(n) when n > 0 and n <= 1, do: n
  def valid_alpha_val(_n), do: 1
end

defimpl String.Chars, for: CSSEx.HSLA do
  def to_string(%CSSEx.HSLA{
        h: %CSSEx.Unit{value: h},
        s: %CSSEx.Unit{value: s} = su,
        l: %CSSEx.Unit{value: l} = lu,
        a: a
      }),
      do: "hsla(#{round(h)},#{%{su | value: round(s)}},#{%{lu | value: round(l)}},#{a})"
end
