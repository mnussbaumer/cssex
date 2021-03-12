defmodule CSSEx.Helpers.EEX do

  @var_sub_regex ~r/(%::.*?)(?:\s|,|\)|\])/mu
  
  import CSSEx.Helpers.Shared, only: [inc_col: 1, inc_col: 2, inc_line: 1]
  @line_terminators CSSEx.Helpers.LineTerminators.code_points()
  @white_space CSSEx.Helpers.WhiteSpace.code_points()

  defstruct [line: 0, column: 0, level: 0, acc: ""]

  def parse(rem, data) do
    case do_parse(rem, data, %__MODULE__{}) do
      {:ok, {_,_} = result} -> result
      {:error, new_data} -> {rem, new_data}
    end
  end

  def finish(
    rem,
    %{assigns: assigns, local_assigns: local_assigns, line: line} = data,
    %{acc: eex_block} = state
  ) do
    acc = IO.iodata_to_binary(eex_block)
    matches =
      Regex.scan(@var_sub_regex, acc, capture: :all_but_first)
      |> :lists.flatten()
    
    case replace_and_extract_assigns(acc, matches, data) do
	
      {:error, error} -> {:error, add_error(data, error)}
      
      {final_block, bindings} ->
	final =
	  case EEx.eval_string(final_block, [assigns: bindings]) do
	    replaced when is_binary(replaced) -> replaced
	    iodata when is_list(iodata) -> IO.iodata_to_binary(iodata)
	  end
	  
	  line_correction = calc_line_offset(state, final)
	{:ok, {final <> rem, %{data | line: line + line_correction}}}
    end

  rescue error ->
    description =
      case error do
	%{description: description} -> description
	error when is_binary(error) -> error
	_ -> "#{inspect error}"
      end
    
    {:error, %{data | valid?: false, error: "Error parsing EEX tag: #{description} :: line: #{line}"}}
  end

  def do_parse(<<>>, data, state), do: {:error, :eof}

  def do_parse(<<"<% end %>", rem::binary>>, data, %{acc: acc, level: level} = state) do
    %{state | acc: [acc | "<% end %>"]}
    |> inc_col(9)
    |> inc_level(-1)
    |> case do
	 %{level: 0} = new_state -> finish(rem, data, new_state)
	 new_state -> do_parse(rem, data, new_state)
       end
  end

  def do_parse(<<"<%", rem::binary>>, data, %{acc: acc, level: level} = state) do
    new_state =
      state
      |> inc_col(2)
      |> inc_level()
    
    do_parse(rem, data, %{new_state | acc: [acc | "<%"], level: level + 1})
  end

  def do_parse(<<"do %>", rem::binary>>, data, %{acc: acc} = state) do
    new_state =
      state
      |> inc_col(5)
    
    do_parse(rem, data, %{new_state | acc: [acc | "do %>"]})
  end

  def do_parse(<<"%>", rem::binary>>, data, %{acc: acc, level: level} = state) do
    %{state | acc: [acc | "%>"]}
    |> inc_col(2)
    |> inc_level(-1)
    |> case do
	 %{level: 0} = new_state -> finish(rem, data, new_state)
	 new_state -> do_parse(rem, data, new_state)
       end
  end

  Enum.each(@line_terminators, fn(char) ->
    def do_parse(<<unquote(char), rem::binary>>, data, %{acc: acc} = state),
      do: do_parse(rem, data, inc_line(%{state | acc: [acc | unquote(char)]}))
  end)

  Enum.each(@white_space, fn(char) ->
    def do_parse(<<unquote(char), rem::binary>>, data, %{acc: acc} = state),
      do: do_parse(rem, data, inc_col(%{state | acc: [acc | unquote(char)]}))
  end)

  def do_parse(<<char::binary-size(1), rem::binary>>, data, %{acc: acc} = state),
    do: do_parse(rem, data, inc_col(%{state | acc: [acc | char]}))

  def replace_and_extract_assigns(acc, matches, %{assigns: assigns, local_assigns: local_assigns}) do
    Enum.reduce_while(matches, {acc, []}, fn(<<"%::", name::binary>> = full, {eex_block, bindings}) ->
      case Map.get(local_assigns, name) || Map.get(assigns, name) do
	nil -> {:halt, {:error, {:not_declared, name}}}
	val ->
	  {:cont, {
	    String.replace(eex_block, full, fn(<<"%::", name::binary>>) -> <<"@", name::binary>> end),
	    [{String.to_atom(name), val} | bindings]
	  }}
      end
    end)
  end

  def calc_line_offset(%{line: eex_lines}, final) do
    lines = for <<char <- final>>, <<char>> in @line_terminators, reduce: 0 do
      acc -> acc + 1
    end

    eex_lines - lines
  end

  def inc_level(%{level: level} = state, amount \\ 1),
    do: %{state | level: level + amount}

  def add_error(data, {:not_declared, val}),
    do: %{data | valid?: false, error: "#{val} was not declared"}
end
