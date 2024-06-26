defmodule CSSEx.Helpers.EEX do
  @moduledoc false

  import CSSEx.Parser, only: [open_current: 2, close_current: 1, add_error: 2]

  import CSSEx.Helpers.Shared,
    only: [
      inc_col: 1,
      inc_col: 2,
      inc_line: 1,
      inc_line: 2,
      inc_no_count: 1,
      file_and_line_opts: 1
    ]

  import CSSEx.Helpers.Error, only: [error_msg: 1]
  @line_terminators CSSEx.Helpers.LineTerminators.code_points()
  @white_space CSSEx.Helpers.WhiteSpace.code_points()

  defstruct line: 0, column: 0, level: 0, acc: "", no_count: 0

  def parse(rem, data) do
    case do_parse(rem, open_current(data, :eex), %__MODULE__{}) do
      {:ok, {_, _} = result} -> result
      {:error, _new_data} = error -> error
    end
  end

  def finish(rem, data, %{acc: eex_block, line: s_line}) do
    acc = IO.chardata_to_string(eex_block)
    final = eval_with_bindings(acc, data)
    new_final = :lists.flatten([to_charlist(final), ?$, 0, ?$, 0, ?$ | rem])
    :erlang.garbage_collect()

    new_data =
      data
      |> inc_line(s_line)
      |> inc_no_count()
      |> close_current()

    {:ok, {new_final, new_data}}
  rescue
    error ->
      {:error, add_error(%{data | line: s_line}, error_msg({:eex, error}))}
  end

  def do_parse([], data, %{column: col, line: line}) do
    new_data =
      data
      |> inc_line(line)
      |> inc_col(col)

    {:error, new_data}
  end

  def do_parse(~c"<% end %>" ++ rem, data, %{acc: acc} = state) do
    %{state | acc: [acc | ~c"<% end %>"]}
    |> inc_col(9)
    |> inc_level(-1)
    |> case do
      %{level: 0} = new_state -> finish(rem, data, new_state)
      new_state -> do_parse(rem, data, new_state)
    end
  end

  def do_parse(~c"<%" ++ rem, data, %{acc: acc, level: level} = state) do
    new_state =
      state
      |> inc_col(2)
      |> inc_level()

    do_parse(rem, data, %{new_state | acc: [acc | ~c"<%"], level: level + 1})
  end

  def do_parse(~c"do %>" ++ rem, data, %{acc: acc} = state) do
    new_state =
      state
      |> inc_col(5)

    do_parse(rem, data, %{new_state | acc: [acc | ~c"do %>"]})
  end

  def do_parse(~c"%>" ++ rem, data, %{acc: acc} = state) do
    %{state | acc: [acc | ~c"%>"]}
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
    Enum.reduce_while(matches, {acc, []}, fn <<"@::", name::binary>> = full,
                                             {eex_block, bindings} ->
      case Map.get(local_assigns, name) || Map.get(assigns, name) do
        nil ->
          {:halt, {:error, {:not_declared, :var, name}}}

        val ->
          {:cont,
           {
             String.replace(eex_block, full, fn <<"@::", name::binary>> ->
               <<"@", name::binary>>
             end),
             [{String.to_atom(name), val} | bindings]
           }}
      end
    end)
  end

  def inc_level(%{level: level} = state, amount \\ 1),
    do: %{state | level: level + amount}

  def eval_with_bindings(acc, data),
    do:
      EEx.eval_string(
        acc,
        [assigns: build_bindings(data)],
        file_and_line_opts(data)
      )

  def build_bindings(%{assigns: a, local_assigns: la}),
    do:
      Enum.map(
        Map.merge(a, la),
        fn {k, v} -> {String.to_atom(k), v} end
      )
end
