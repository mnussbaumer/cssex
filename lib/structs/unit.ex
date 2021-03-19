defmodule CSSEx.Unit do
  @enforce_keys [:unit, :value]
  defstruct [:unit, :value]

  @values ~w(px em rem % vw vh cm mm in pt pc ex ch vmin vmax)
  @values_map Enum.reduce(@values, %{}, fn val, acc ->
                Map.put(acc, val, String.to_atom(val))
              end)

  def new_unit(unit) do
    case Float.parse(unit) do
      {"", _} ->
        {:error, :invalid_value}

      {val, ""} ->
        %__MODULE__{value: val, unit: nil}

      {val, unit} when unit in @values ->
        %__MODULE__{value: val, unit: @values_map[unit]}

      _ ->
        {:error, :invalid_unit}
    end
  end
end

defimpl String.Chars, for: CSSEx.Unit do
  def to_string(%CSSEx.Unit{value: value, unit: unit}), do: "#{value}#{unit || ""}"
end
