defmodule CSSEx.Helpers.Error do
  # this means that the error is being bubbled up
  def error_msg(%{valid?: false, error: error}), do: error

  def error_msg({:mismatched, char}), do: "mismatched #{char}"

  def error_msg({:not_declared, :var, val}), do: "variable #{val} was not declared"
  def error_msg({:not_declared, :val, val}), do: "assign #{val} was not declared"
  def error_msg({:not_declared, :function, name}), do: "function #{name} was not declared"
  def error_msg({:unexpected, string}), do: "unexpected token: #{string}"

  def error_msg({:eex, error}), do: "parsing EEX tag: #{inspect(error)}"

  def error_msg({:cyclic_reference, path, _file_list}),
    do: "cyclic reference, #{path} won't be able to be parsed"

  def error_msg({:enoent, path}), do: "unable to find file #{path}"

  def error_msg({:terminator, {:terminator, char}}) when is_integer(char),
    do: <<"unable to find terminator for ", char>>

  def error_msg({:terminator, {:terminator, char}}) when is_binary(char),
    do: "unable to find terminator for #{char}"

  def error_msg({:terminator, step}), do: "invalid #{inspect(step)} declaration"

  def error_msg({:malformed, :function_call}), do: "malformed function call"

  def error_msg({:function_call, name, error}),
    do: "function call #{name} threw an exception: #{inspect(error)}"

  def error_msg({:invalid_argument, name}), do: "invalid argument #{name}"

  def error_msg({:invalid_component_concat, to_concat, existing}),
    do: "you're tring to concat an html element #{to_concat} to another html element #{existing}"

  def error_msg({:invalid_parent_concat, to_concat}),
    do: "you're tring to concat #{to_concat} outside of a block"
end
