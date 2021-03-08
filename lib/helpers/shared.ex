defmodule CSSEx.Helpers.Shared do
  # increment the column token count
  def inc_col(%{column: column} = data, amount \\ 1),
    do: %{data | column: column + amount}

  # increment the line and reset the column
  def inc_line(%{line: line} = data, amount \\ 1),
    do: %{data | column: 0, line: line + amount}

end
