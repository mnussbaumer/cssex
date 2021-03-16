defmodule CSSEx.Helpers.Media do
  import CSSEx.Helpers.Shared, only: [inc_col: 1]
  @line_terminators CSSEx.Helpers.LineTerminators.code_points()

  defstruct column: 0, acc: [], parenthesis: 0, p_acc: %{}

  def parse(rem, data) do
    case do_parse(rem, data, %__MODULE__{}) do
      {:ok, {_, _} = result} -> result
      {:error, new_data} -> {rem, new_data}
    end
  end

  def do_parse(<<>>, data, %{acc: acc, parenthesis: 0} = _state) do
    parsed = IO.iodata_to_binary(acc)
    {:ok, {parsed, data}}
  end

  # we found an opening parenthesis (,
  def do_parse(<<40, rem::binary>>, data, %{parenthesis: p, p_acc: p_acc} = state) do
    new_p = p + 1
    new_p_acc = Map.put(p_acc, new_p, [])
    do_parse(rem, inc_col(data), %{state | parenthesis: new_p, p_acc: new_p_acc})
  end

  # we found a closing parenthesis )
  def do_parse(<<41, rem::binary>>, data, %{acc: acc, parenthesis: p, p_acc: p_acc} = state)
      when p > 0 do
    {accumulator, new_p_acc} = Map.pop(p_acc, p)
    processed = process_parenthesis_content(accumulator, data)
    previous_p = p - 1
    new_state = inc_col(%{state | parenthesis: previous_p})

    new_state_2 =
      case Map.pop(new_p_acc, previous_p) do
        # this means we're on the first opened parenthesis
        {nil, new_p_acc_2} ->
          %{new_state | p_acc: new_p_acc_2, acc: [acc | ["(", processed, ")"]]}

        {previous_acc, new_p_acc_2} ->
          %{
            new_state
            | p_acc: Map.put(new_p_acc_2, previous_p, [previous_acc | ["(", processed, ")"]])
          }
      end

    do_parse(rem, data, new_state_2)
  end

  Enum.each(@line_terminators, fn char ->
    def do_parse(<<unquote(char), _rem::binary>>, _data, _state), do: {:error, :newline}
  end)

  def do_parse(
        <<char::binary-size(1), rem::binary>>,
        data,
        %{parenthesis: p, p_acc: p_acc} = state
      )
      when p > 0 do
    p_acc_inner = Map.fetch!(p_acc, p)
    new_p_acc = Map.put(p_acc, p, [p_acc_inner | char])
    do_parse(rem, data, inc_col(%{state | p_acc: new_p_acc}))
  end

  def do_parse(<<char::binary-size(1), rem::binary>>, data, %{parenthesis: 0, acc: acc} = state),
    do: do_parse(rem, data, inc_col(%{state | acc: [acc | char]}))

  def do_parse(<<41, _rem::binary>>, data, %{parenthesis: 0}),
    do: {:error, %{data | valid?: false, error: "Unexpected closing parenthesis"}}

  def process_parenthesis_content(accumulator, data) do
    acc = IO.iodata_to_binary(accumulator)

    Regex.split(~r/\s(and|or)\s/, acc, include_captures: true)
    |> Enum.map(fn value ->
      trimmed = String.trim(value)

      case trimmed do
        "and" ->
          "and"

        "or" ->
          "or"

        declaration ->
          String.split(declaration, ~r/:/, trim: true)
          |> Enum.map(fn token ->
            case CSSEx.Parser.maybe_replace_val(String.trim(token), data) do
              {:ok, new_token} -> new_token
              {:error, _} -> raise "#{token} was not declared"
            end
          end)
          |> Enum.join(":")
      end
    end)
    |> Enum.join(" ")
  end
end
