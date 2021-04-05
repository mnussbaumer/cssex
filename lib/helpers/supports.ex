defmodule CSSEx.Helpers.Supports do
  @moduledoc false

  @line_terminators CSSEx.Helpers.LineTerminators.code_points()
  @var_replacement_split ~r/(?<maybe_var_1>\$::)?.+(?<split>:).+(?<maybe_var_2>\$::)|(?<split_2>:)/
  @supports_separators ~r/\s(and|or|not)\s/

  def process_parenthesis_content(accumulator, data) do
    acc = IO.chardata_to_string(accumulator)

    Regex.split(@supports_separators, acc, include_captures: true)
    |> Enum.map(fn value ->
      trimmed = String.trim(value)

      case trimmed do
        "and" ->
          "and"

        "or" ->
          "or"

        "not" ->
          "not"

        declaration ->
          String.split(declaration, @var_replacement_split, trim: true, on: [:split, :split_2])
          |> Enum.map(fn token ->
            case CSSEx.Helpers.Interpolations.maybe_replace_val(String.trim(token), data) do
              {:ok, new_token} ->
                new_token

              {:error, _} = error ->
                throw(error)
            end
          end)
          |> Enum.join(":")
      end
    end)
    |> Enum.join(" ")
  end
end
