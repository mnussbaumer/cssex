defmodule CSSEx.Helpers.AtParser do
  @moduledoc false

  import CSSEx.Helpers.Shared, only: [inc_col: 1]
  import CSSEx.Helpers.Error, only: [error_msg: 1]
  import CSSEx.Parser, only: [add_error: 2]

  @line_terminators CSSEx.Helpers.LineTerminators.code_points()
  @var_replacement_split ~r/(?<maybe_var_1>\$::)?.+(?<split>:).+(?<maybe_var_2>\$::)|(?<split_2>:)/
  @parenthesis_separators ~r/\s(and|or|not)\s/

  @enforce_keys [:type]
  defstruct [:type, column: 0, acc: [], parenthesis: 0, p_acc: %{}]

  def parse(rem, data, type) do
    case do_parse(rem, data, %__MODULE__{type: type}) do
      {:ok, {_, _} = result} -> result
      {:error, new_data} -> {rem, new_data}
    end
  end

  def do_parse([], data, %{acc: acc, parenthesis: 0} = _state) do
    parsed = IO.chardata_to_string(acc)

    {:ok, {parsed, data}}
  end

  # we found an opening parenthesis (,
  def do_parse([40 | rem], data, %{parenthesis: p, p_acc: p_acc} = state) do
    new_p = p + 1
    new_p_acc = Map.put(p_acc, new_p, [])
    do_parse(rem, inc_col(data), %{state | parenthesis: new_p, p_acc: new_p_acc})
  end

  # we found a closing parenthesis )
  def do_parse([41 | rem], data, %{acc: acc, parenthesis: p, p_acc: p_acc} = state)
      when p > 0 do
    {accumulator, new_p_acc} = Map.pop(p_acc, p)

    try do
      processed = process_parenthesis_content(accumulator, data, state)
      previous_p = p - 1
      new_state = inc_col(%{state | parenthesis: previous_p})

      new_state_2 =
        case Map.pop(new_p_acc, previous_p) do
          # this means we're on the first opened parenthesis
          {nil, new_p_acc_2} ->
            %{new_state | p_acc: new_p_acc_2, acc: [acc, [40, processed, 41]]}

          {previous_acc, new_p_acc_2} ->
            %{
              new_state
              | p_acc: Map.put(new_p_acc_2, previous_p, [previous_acc, [40, processed, 41]])
            }
        end

      do_parse(rem, data, new_state_2)
    catch
      {:error, _} = error ->
        {:error, add_error(data, error_msg(error))}
    end
  end

  Enum.each(@line_terminators, fn char ->
    def do_parse([unquote(char) | _rem], data, %{type: type} = _state),
      do: {:error, add_error(data, error_msg({:invalid, "@#{type}", :newline}))}
  end)

  def do_parse(
        [char | rem],
        data,
        %{parenthesis: p, p_acc: p_acc} = state
      )
      when p > 0 do
    p_acc_inner = Map.fetch!(p_acc, p)
    new_p_acc = Map.put(p_acc, p, [p_acc_inner, char])
    do_parse(rem, data, inc_col(%{state | p_acc: new_p_acc}))
  end

  def do_parse([char | rem], data, %{parenthesis: 0, acc: acc} = state),
    do: do_parse(rem, data, inc_col(%{state | acc: [acc, char]}))

  def do_parse([41, _rem], data, %{parenthesis: 0}),
    do: {:error, add_error(data, error_msg({:unexpected, ")"}))}

  def process_parenthesis_content(accumulator, data, %{type: type} = _state) do
    case type do
      :media -> process_parenthesis_base(accumulator, data)
      :page -> throw({:error, :no_page})
      :supports -> process_parenthesis_base(accumulator, data)
    end
  end

  def process_parenthesis_base(accumulator, data) do
    acc = IO.chardata_to_string(accumulator)

    Regex.split(@parenthesis_separators, acc, include_captures: true)
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
