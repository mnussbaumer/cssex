defmodule CSSEx.Helpers.LineTerminators do
  @moduledoc """
  Helpers for matching on line terminator characters (and 1 sequence) according to the Unicode std.
  https://en.wikipedia.org/wiki/Newline#Unicode
  """

  @line_terminators_unicode [
                              "\u000A",
                              "\u000B",
                              "\u000C",
                              "\u000D",
                              "\u000D\u000A",
                              "\u0085",
                              "\u2028",
                              "\u2029"
                            ]
                            |> Enum.reduce([], fn char, acc ->
                              [hd(to_charlist(char)) | acc]
                            end)

  def code_points(), do: @line_terminators_unicode
end
