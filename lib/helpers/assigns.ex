defmodule CSSEx.Helpers.Assigns do
  @moduledoc """
  Helpers for parsing a CSSEx assign, given it can be any elixir term/expression to be evaluated it has different rules and should keep all characters until the termination mark, afterwards it should be validated and return either an updated {rem, %CSSEx.Parser{valid?: true}} or {rem, %CSSEx.Parser{valid?: false}} with the error field populated.
  """

  import CSSEx.Helpers.Shared, only: [inc_col: 1, inc_line: 1]
  @line_terminators CSSEx.Helpers.LineTerminators.code_points()

  # termination when parsing the assign
  Enum.each(@line_terminators, fn char ->
    def parse(
          <<?;, unquote(char), rem::binary>>,
          %{current_assign: current_key, current_value: current_value, line: line} = data
        ) do
      ckey = IO.iodata_to_binary(current_key)
      cval = String.trim_trailing(IO.iodata_to_binary(current_value))
      {final_val, _} = Code.eval_string(cval, [], line: line)

      new_data =
        data
        |> add_assign(ckey, final_val)
        |> inc_line()

      {rem, new_data}
    rescue
      error ->
        description =
          case error do
            %{description: description} -> description
            error when is_binary(error) -> error
            _ -> "Error: #{inspect(error)}"
          end

        {rem, %{data | valid?: false, error: "#{description} :: section line end: #{line}"}}
    end

    def parse(<<unquote(char), rem::binary>>, %{current_value: cval} = data),
      do: parse(rem, inc_line(%{data | current_value: [cval | unquote(char)]}))
  end)

  # acc the assign, given this is elixir we accumulate any char, we'll validate once we try to compile it
  def parse(<<char::binary-size(1), rem::binary>>, %{current_value: cval} = data),
    do: parse(rem, inc_col(%{data | current_value: [cval | char]}))

  def add_assign(
        %{current_scope: :global, assigns: assigns, local_assigns: local_assigns} = data,
        key,
        val
      ),
      do: %{
        data
        | assigns: Map.put(assigns, key, val),
          local_assigns: Map.put(local_assigns, key, val)
      }

  def add_assign(%{current_scope: :local, local_assigns: local_assigns} = data, key, val),
    do: %{data | local_assigns: Map.put(local_assigns, key, val)}

  def add_assign(
        %{current_scope: :conditional, assigns: assigns, local_assigns: local_assigns} = data,
        key,
        val
      ) do
    case Map.get(assigns, key) do
      nil ->
        case Map.get(local_assigns, key) do
          nil -> %{data | local_assigns: Map.put(local_assigns, key, val)}
          _ -> data
        end

      _ ->
        data
    end
  end
end
