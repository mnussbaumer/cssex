defmodule CSSEx.Unit do
  @moduledoc """
  A basic representation to use for CSS units.
  """
  @enforce_keys [:unit, :value]
  defstruct [:unit, :value]

  @values ~w(px em rem % vw vh cm mm in pt pc ex ch vmin vmax)
  @values_map Enum.reduce(@values, %{}, fn val, acc ->
                Map.put(acc, val, String.to_atom(val))
              end)

  @doc """
  Accepts a String.t and Generates a `%CSSEx.Unit{}` with an appropriate unit set if it matches any of the predefined units, otherwise a struct with unit set to nil when there's no unit, or an error if there's a unit but isn't a valid one.
  If the argument can't be parsed as a float it returns an `:error` tuple
  """
  @spec new_unit(String.t()) :: %CSSEx.Unit{} | {:error, atom}
  def new_unit(unit) do
    case Float.parse(unit) do
      {"", _} ->
        {:error, :invalid_value}

      {val, unit} ->
        case String.trim(unit) do
          trimmed when trimmed in @values ->
            %__MODULE__{value: val, unit: @values_map[trimmed]}

          "" ->
            %__MODULE__{value: val, unit: nil}

          _ ->
            {:error, :invalid_unit}
        end
    end
  end
end

defimpl String.Chars, for: CSSEx.Unit do
  def to_string(%CSSEx.Unit{value: value, unit: unit}), do: "#{value}#{unit || ""}"
end
