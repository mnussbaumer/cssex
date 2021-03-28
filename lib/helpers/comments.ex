defmodule CSSEx.Helpers.Comments do
  import CSSEx.Helpers.Shared, only: [inc_col: 1, inc_col: 2, inc_line: 1]
  @line_terminators CSSEx.Helpers.LineTerminators.code_points()

  def parse(
        '*/' ++ rem,
        data,
        '/*'
      ),
      do: {:ok, {inc_col(data, 2), rem}}

  Enum.each(@line_terminators, fn char ->
    def parse([unquote(char) | rem], data, '//'),
      do: {:ok, {inc_line(data), rem}}

    def parse([unquote(char) | rem], data, '/*' = ctype),
      do: parse(rem, inc_line(data), ctype)
  end)

  def parse([_ | rem], data, comment_type),
    do: parse(rem, inc_col(data), comment_type)

  def parse([], data, _comment_type), do: {:ok, {data, []}}
end
