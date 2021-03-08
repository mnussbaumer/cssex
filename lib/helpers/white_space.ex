defmodule CSSEx.Helpers.WhiteSpace do

  @moduledoc """
  Helpers for matching on white space characters according to Unicode Pattern_White_Space. The chars we match are those mentioned in the wikipedia page except the line terminators that are in the helpers for them since we want to be able to discern line and column when parsing the cssex files
  https://en.wikipedia.org/wiki/Whitespace_character#Unicode
  
  """
  @white_space_unicode ["\u0009", "\u0020", "\u00A0", "\u1680", "\u2000", "\u2001", "\u2002", "\u2003", "\u2004", "\u2005", "\u2006", "\u2007", "\u2008", "\u2009", "\u200A", "\u202F", "\u205F", "\u3000"]

  def code_points(), do: @white_space_unicode
end

