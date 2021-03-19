defmodule CSSEx.Helpers.Function do
  import CSSEx.Helpers.Shared, only: [inc_col: 1, inc_col: 2, inc_line: 1]
  import CSSEx.Parser, only: [add_error: 2]
  import CSSEx.Helpers.Error, only: [error_msg: 1]

  @line_terminators CSSEx.Helpers.LineTerminators.code_points()

  Enum.each(@line_terminators, fn char ->
    # we reached the end of the function declaration
    def parse(
          %{current_value: current_value, current_function: fn_iodata} = data,
          <<"};", unquote(char), rem::binary>>
        ) do
      cval = String.trim(IO.iodata_to_binary(current_value))
      fun_string = String.trim(IO.iodata_to_binary(fn_iodata))
      {name, args} = extract_name_and_args(cval)

      full_string =
        IO.iodata_to_binary(["fn(", Enum.join(args, ","), ") -> ", fun_string, " end"])

      {fun_result, _} =
        Code.eval_string(full_string,
          file: data.file,
          line: data.line
        )

      new_data =
        data
        |> inc_col(2)
        |> inc_line()
        |> add_fun(name, fun_result)

      {:ok, {new_data, rem}}
    end

    def parse(%{current_function: cfun} = data, <<unquote(char), rem::binary>>) do
      %{data | current_function: [cfun, unquote(char)]}
      |> inc_line()
      |> parse(rem)
    end
  end)

  def parse(%{current_function: cfun} = data, <<char::binary-size(1), rem::binary>>) do
    %{data | current_function: [cfun, char]}
    |> inc_col()
    |> parse(rem)
  end

  def extract_name_and_args(declaration) do
    case Regex.run(~r/(.+)\((.+)?\)/, declaration) do
      [_, name, args] ->
        {name, Enum.map(String.split(args, ",", trim: true), fn arg -> String.trim(arg) end)}

      [_, name] ->
        {name, ""}

      _ ->
        {:error, :invalid_declaration}
    end
  end

  def add_fun(%{functions: functions} = data, name, fun),
    do: %{data | functions: Map.put(functions, name, fun)}

  def parse_call(data, rem) do
    case do_parse_call(data, rem, [], 0) do
      {:ok, _} = ok -> ok
    end
  end

  def do_parse_call(data, <<"(", rem::binary>>, acc, level) do
    data
    |> inc_col()
    |> do_parse_call(rem, [acc, "("], level + 1)
  end

  def do_parse_call(data, <<")", rem::binary>>, acc, 1) do
    data
    |> inc_col()
    |> finish_parse_call(rem, [acc, ")"])
  end

  def do_parse_call(data, <<")", rem::binary>>, acc, level) do
    data
    |> inc_col()
    |> do_parse_call(rem, [acc, ")"], level - 1)
  end

  def do_parse_call(data, <<char::binary-size(1), rem::binary>>, acc, level) do
    data
    |> inc_col()
    |> do_parse_call(rem, [acc, char], level)
  end

  def do_parse_call(data, <<>>, _acc, _level),
    do: {:error, add_error(data, error_msg({:malformed, :function_call}))}

  def finish_parse_call(%{functions: functions} = data, rem, acc) do
    fun_spec = IO.iodata_to_binary(acc)
    {name, args} = extract_name_and_args(fun_spec)

    case replace_args(args, data) do
      {:ok, final_args} ->
        case Map.get(functions, name) do
          nil ->
            finish_error(data, {:not_declared, :function, name})

          function when is_function(function) ->
            case apply(function, final_args) do
              {:ok, result} when is_binary(result) -> finish_call(data, rem, result)
              {:ok, [_ | _] = result} -> finish_call(data, rem, IO.iodata_to_binary(result))
              {:ok, result} -> finish_call(data, rem, to_string(result))
              error -> finish_error(data, error)
            end
        end
    end
  end

  def finish_call(data, rem, result) do
    {:ok, {data, <<result::binary, rem::binary>>}}
  end

  def finish_error(data, error),
    do: {:error, add_error(data, error_msg(error))}

  def replace_args(args, data) do
    Enum.reduce_while(args, {:ok, []}, fn arg, {:ok, acc} ->
      case CSSEx.Helpers.Interpolations.maybe_replace_arg(arg, data) do
        {:ok, val} -> {:cont, {:ok, [val | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed_args} -> {:ok, :lists.reverse(reversed_args)}
      error -> error
    end
  end
end
