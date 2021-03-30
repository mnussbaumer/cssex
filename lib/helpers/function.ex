defmodule CSSEx.Helpers.Function do
  @moduledoc false

  import CSSEx.Helpers.Shared,
    only: [
      inc_col: 1,
      inc_col: 2,
      inc_line: 1,
      inc_line: 2,
      calc_line_offset: 2,
      file_and_line_opts: 1
    ]

  import CSSEx.Parser, only: [add_error: 2]
  import CSSEx.Helpers.Error, only: [error_msg: 1]

  @line_terminators CSSEx.Helpers.LineTerminators.code_points()

  Enum.each(@line_terminators, fn char ->
    # we reached the end of the function declaration
    def parse(
          %{current_value: current_value, current_function: fn_iodata} = data,
          'end;' ++ [unquote(char) | rem]
        ) do
      cval = String.trim(IO.chardata_to_string(current_value))
      fun_string = String.trim(IO.chardata_to_string(fn_iodata))
      {name, args} = extract_name_and_args(cval)

      full_string =
        IO.iodata_to_binary([
          "fn(",
          Enum.join(["ctx_content" | args], ","),
          ") -> ",
          "\nif(ctx_content, do: true, else: false)\n",
          fun_string,
          " end"
        ])

      {fun_result, _} = Code.eval_string(full_string, [], file_and_line_opts(data))

      line_correction = calc_line_offset(1, fun_string)

      new_data =
        data
        |> inc_col(2)
        |> inc_line(line_correction)
        |> add_fun(name, fun_result)

      {:ok, {new_data, rem}}
    end

    def parse(%{current_function: cfun} = data, [unquote(char) | rem]) do
      %{data | current_function: [cfun, unquote(char)]}
      |> inc_line()
      |> parse(rem)
    end
  end)

  def parse(%{current_function: cfun} = data, [char | rem]) do
    %{data | current_function: [cfun, char]}
    |> inc_col()
    |> parse(rem)
  end

  def extract_name_and_args(declaration, functions \\ nil) do
    case Regex.run(~r/(^[^\(]*)\((.+)?\)/s, declaration) do
      [_, name, args] ->
        case functions do
          nil ->
            split_args =
              args
              |> String.split(",", trim: true)
              |> Enum.map(fn arg -> String.trim(arg) end)

            {name, split_args}

          funs ->
            case Map.get(funs, name) do
              nil ->
                {:error, {:not_declared, :function, name}}

              fun ->
                {:arity, ar} = Function.info(fun, :arity)

                split_args = CSSEx.Helpers.Shared.search_args_split(to_charlist(args), ar - 1)
                {actual_args, ctx} = Enum.split(split_args, ar - 1)
                ctx_content = if(length(ctx) == 1, do: hd(ctx), else: nil)
                {name, [ctx_content | Enum.map(actual_args, fn arg -> String.trim(arg) end)]}
            end
        end

      [_, name] ->
        case functions do
          nil -> {name, []}
          _funs -> {name, [nil]}
        end

      _ ->
        {:error, :invalid_declaration}
    end
  end

  def add_fun(%{functions: functions} = data, name, fun),
    do: %{data | functions: Map.put(functions, name, fun)}

  def parse_call(data, rem) do
    case do_parse_call(data, rem, [], 0) do
      {:ok, _} = ok -> ok
      {:error, _} = error -> error
    end
  end

  def do_parse_call(data, [?( | rem], acc, level) do
    data
    |> inc_col()
    |> do_parse_call(rem, [acc, ?(], level + 1)
  end

  def do_parse_call(data, [?) | rem], acc, 1) do
    data
    |> inc_col()
    |> finish_parse_call(rem, [acc, ?)])
  end

  def do_parse_call(data, [?) | rem], acc, level) do
    data
    |> inc_col()
    |> do_parse_call(rem, [acc, ?)], level - 1)
  end

  def do_parse_call(data, [char | rem], acc, level) do
    data
    |> inc_col()
    |> do_parse_call(rem, [acc, char], level)
  end

  def do_parse_call(data, [], _acc, _level),
    do: {:error, add_error(data, error_msg({:malformed, :function_call}))}

  def finish_parse_call(%{functions: functions} = data, rem, acc) do
    fun_spec = IO.chardata_to_string(acc)
    {name, args} = extract_name_and_args(fun_spec, functions)

    case replace_args(args, data) do
      {:ok, final_args} ->
        case Map.get(functions, name) do
          nil ->
            finish_error(data, {:not_declared, :function, name})

          function when is_function(function) ->
            try do
              case apply(function, final_args) do
                {:ok, result} when is_binary(result) ->
                  finish_call(data, rem, result)

                {:ok, [_ | _] = result} ->
                  finish_call(data, rem, IO.iodata_to_binary(result))

                {:ok, result} ->
                  finish_call(data, rem, to_string(result))

                result when is_binary(result) ->
                  finish_call(data, rem, result)

                [_ | _] = result ->
                  finish_call(data, rem, IO.iodata_to_binary(result))

                error ->
                  finish_error(data, error)
              end
            rescue
              e ->
                finish_error(data, {:function_call, name, e})
            end
        end

      {:error, error} ->
        finish_error(data, error)
    end
  end

  def finish_call(data, rem, result) when is_binary(result) do
    line_correction = calc_line_offset(0, result)

    data
    |> inc_line(line_correction)
    |> finish_call(rem, to_charlist(result))
  end

  def finish_call(data, rem, result) when is_list(result) do
    {:ok, {data, :lists.flatten([result | rem])}}
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
