defmodule CSSEx.Helpers.Assigns do
  @moduledoc false

  import CSSEx.Parser, only: [close_current: 1, add_error: 1, add_error: 2]
  import CSSEx.Helpers.Shared, only: [inc_col: 1, inc_line: 1]
  import CSSEx.Helpers.Error, only: [error_msg: 1]
  import CSSEx.Helpers.EEX, only: [build_bindings: 1]
  @line_terminators CSSEx.Helpers.LineTerminators.code_points()

  # termination when parsing the assign
  Enum.each(@line_terminators, fn char ->
    def parse(
          [?;, unquote(char) | rem],
          %{current_assign: current_key, current_value: current_value, line: line} = data
        ) do
      ckey = IO.chardata_to_string(current_key)
      cval = String.trim_trailing(IO.chardata_to_string(current_value))

      {final_val, _} = Code.eval_string(cval, build_bindings(data), line: line)

      new_data =
        data
        |> add_assign(ckey, final_val)
        |> close_current()
        |> inc_line()

      {rem, new_data}
    rescue
      error ->
        {rem, add_error(data, error_msg({:assigns, error}))}
    end

    def parse([unquote(char) | rem], %{current_value: cval} = data),
      do: parse(rem, inc_line(%{data | current_value: [cval, unquote(char)]}))
  end)

  # acc the assign, given this is elixir we accumulate any char, we'll validate once we try to compile it
  def parse([char | rem], %{current_value: cval} = data),
    do: parse(rem, inc_col(%{data | current_value: [cval, char]}))

  def parse([], data),
    do: {[], add_error(data)}

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
