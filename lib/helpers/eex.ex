defmodule CSSEx.Helpers.EEX do
  import CSSEx.Parser, only: [open_current: 2, close_current: 1, add_error: 2]
  import CSSEx.Helpers.Shared, only: [inc_col: 1, inc_col: 2, inc_line: 1, inc_line: 2]
  import CSSEx.Helpers.Error, only: [error_msg: 1]
  @line_terminators CSSEx.Helpers.LineTerminators.code_points()
  @white_space CSSEx.Helpers.WhiteSpace.code_points()

  defstruct line: 0, column: 0, level: 0, acc: ""

  def parse(rem, data) do
    new_data = open_current(data, :eex)

    case do_parse(rem, new_data, %__MODULE__{}) do
      {:ok, {_, _} = result} -> result
      {:error, _new_data} = error -> error
    end
  end

  def finish(rem, %{line: line} = data, %{acc: eex_block} = state) do
    acc = IO.chardata_to_string(eex_block)
    final = eval_with_bindings(acc, data)
    line_correction = calc_line_offset(state, final)

    new_final = :lists.flatten([to_charlist(final) | rem])
    :erlang.garbage_collect()
    {:ok, {new_final, %{close_current(data) | line: line + line_correction}}}
  rescue
    error -> {:error, add_error(data, error_msg({:eex, error}))}
  end

  def do_parse([], data, %{column: col, line: line}) do
    new_data =
      data
      |> inc_line(line)
      |> inc_col(col)

    {:error, new_data}
  end

  def do_parse('<% end %>' ++ rem, data, %{acc: acc} = state) do
    %{state | acc: [acc | '<% end %>']}
    |> inc_col(9)
    |> inc_level(-1)
    |> case do
      %{level: 0} = new_state -> finish(rem, data, new_state)
      new_state -> do_parse(rem, data, new_state)
    end
  end

  def do_parse('<%' ++ rem, data, %{acc: acc, level: level} = state) do
    new_state =
      state
      |> inc_col(2)
      |> inc_level()

    do_parse(rem, data, %{new_state | acc: [acc | '<%'], level: level + 1})
  end

  def do_parse('do %>' ++ rem, data, %{acc: acc} = state) do
    new_state =
      state
      |> inc_col(5)

    do_parse(rem, data, %{new_state | acc: [acc | 'do %>']})
  end

  def do_parse('%>' ++ rem, data, %{acc: acc} = state) do
    %{state | acc: [acc | '%>']}
    |> inc_col(2)
    |> inc_level(-1)
    |> case do
      %{level: 0} = new_state -> finish(rem, data, new_state)
      new_state -> do_parse(rem, data, new_state)
    end
  end

  Enum.each(@line_terminators, fn char ->
    def do_parse([unquote(char) | rem], data, %{acc: acc} = state),
      do: do_parse(rem, data, inc_line(%{state | acc: [acc, unquote(char)]}))
  end)

  Enum.each(@white_space, fn char ->
    def do_parse([unquote(char) | rem], data, %{acc: acc} = state),
      do: do_parse(rem, data, inc_col(%{state | acc: [acc, unquote(char)]}))
  end)

  def do_parse([char | rem], data, %{acc: acc} = state),
    do: do_parse(rem, data, inc_col(%{state | acc: [acc, char]}))

  def replace_and_extract_assigns(acc, matches, %{assigns: assigns, local_assigns: local_assigns}) do
    Enum.reduce_while(matches, {acc, []}, fn <<"%::", name::binary>> = full,
                                             {eex_block, bindings} ->
      case Map.get(local_assigns, name) || Map.get(assigns, name) do
        nil ->
          {:halt, {:error, {:not_declared, :var, name}}}

        val ->
          {:cont,
           {
             String.replace(eex_block, full, fn <<"%::", name::binary>> ->
               <<"@", name::binary>>
             end),
             [{String.to_atom(name), val} | bindings]
           }}
      end
    end)
  end

  def calc_line_offset(%{line: eex_lines}, final) do
    lines =
      for <<char <- final>>, <<char>> in @line_terminators, reduce: 0 do
        acc -> acc + 1
      end

    eex_lines - lines
  end

  def inc_level(%{level: level} = state, amount \\ 1),
    do: %{state | level: level + amount}

  def eval_with_bindings(acc, data),
    do: EEx.eval_string(acc, assigns: build_bindings(data))

  def build_bindings(%{assigns: a, local_assigns: la}),
    do:
      Enum.map(
        Map.merge(a, la),
        fn {k, v} -> {String.to_atom(k), v} end
      )
end
