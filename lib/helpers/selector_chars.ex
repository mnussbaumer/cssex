defmodule CSSEx.Helpers.SelectorChars do
  @moduledoc false

  @white_spaces CSSEx.Helpers.WhiteSpace.code_points()

  @appendable_first_char [?., ?#, ?+, ?>, ?~, ?:, ?[, ?| | @white_spaces]

  def appendable_first_char(), do: @appendable_first_char
end
