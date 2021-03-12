defmodule CSSEx.Helpers.Shared do
  # increment the column token count
  def inc_col(%{column: column} = data, amount \\ 1),
    do: %{data | column: column + amount}

  # increment the line and reset the column
  def inc_line(%{line: line} = data, amount \\ 1),
    do: %{data | column: 0, line: line + amount}

  def generate_prefix(%{current_chain: cc, prefix: nil}), do: cc
  def generate_prefix(%{current_chain: cc, prefix: prefix}), do: prefix ++ cc

  def ampersand_join(initial), do: ampersand_join(initial, [])
  def ampersand_join([head, <<"&", rem::binary>> | t], acc),
    do: ampersand_join([head <> rem | t], acc)

  def ampersand_join([head | t], acc), do: ampersand_join(t, [acc | [head]])

  def ampersand_join([], acc), do: :lists.flatten(acc)
end
