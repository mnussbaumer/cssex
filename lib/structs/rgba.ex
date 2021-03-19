defmodule CSSEx.RGBA do
  defstruct [r: 0, g: 0, b: 0, a: 1]

  @colors CSSEx.Helpers.Colors.colors_tuples()
  

  def new_rgba(<<"rgba", values::binary>>) do
    case Regex.run(~r/\((.+),(.+),(.+),(.+)\)/, values) do
      [_, r, g, b, a] ->
	new(
	  String.trim(r),
	  String.trim(g),
	  String.trim(b),
	  String.trim(a)
	)
	_ -> {:error, :invalid}
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
	_ -> {:error, :invalid}
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
	_ -> {:error, :invalid}
    end
  end

  Enum.each(@colors, fn([color, rgba]) ->
    def new_rgba(unquote(color)), do: new_rgba(unquote(rgba))
  end)

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

  def color_value(val, base) when is_binary(val) do
    case Integer.parse(val, base) do
      {parsed, _} -> valid_rgb_val(parsed)
      :error -> 0
    end
  end
  
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

  def valid_rgb_val(n) when n <= 255 and n >= 0, do: n
  def valid_rgb_val(n) when n > 255, do: 255
  def valid_rgb_val(n) when n < 0, do: 0

  def valid_alpha_val(n) when n > 0 and n <= 1, do: n
  def valid_alpha_val(_n), do: 1

end

defimpl String.Chars, for: CSSEx.RGBA do
  def to_string(%CSSEx.RGBA{r: r, g: g, b: b, a: a}), do: "rgba(#{r},#{b},#{g},#{a})"
end
