defmodule CSSEx.Parser do
  import CSSEx.Helpers.Shared, only: [inc_col: 1, inc_col: 2, inc_line: 1]

  @behaviour :gen_statem

  @timeout 15_000

  @enforce_keys [:ets, :line, :column]
  defstruct [
    :ets,
    :line,
    :column,
    :error,
    :answer_to,
    :current_line,
    :current_column,
    pass: 1,
    scope: %{},
    local_scope: %{},
    assigns: %{},
    local_assigns: %{},
    current_chain: [],
    valid?: true,
    current_key: "",
    current_value: "",
    current_var: "",
    current_assign: "",
    current_scope: nil,
    current_add_var: false,
    level: 0,
    charset: nil,
    first_rule: true,
    warnings: []
  ]

  @white_space CSSEx.Helpers.WhiteSpace.code_points()
  @line_terminators CSSEx.Helpers.LineTerminators.code_points()

  @special_css_rules [
    "@charset",
    "@font-face",
    "@font-feature-values", # Allows authors to use a common name in font-variant-alternate for feature activated differently in OpenType
    "@import",
    "@keyframes"
  ]

  @doc """
  Takes a binary or an IO.device(), parses it into a final CSS representation and returns either:
  {:ok, final_binary, term}
  {:error, term}
  """

  def parse(content) do
    {:ok, pid} = __MODULE__.start_link()
    :gen_statem.call(pid, {:start, content})
  end
  

  @impl :gen_statem
  def callback_mode(), do: :handle_event_function

  def start_link() do
    :gen_statem.start_link(__MODULE__, nil, [])
  end

  @impl :gen_statem
  def init(_content) do
    table_ref = :ets.new(:base, [])
    {:ok, :waiting, %__MODULE__{ets: table_ref, line: 0, column: 0}, [@timeout]}
  end

  @impl :gen_statem
  def handle_event({:call, from}, {:start, content}, :waiting, data) do
    new_data = %__MODULE__{data | answer_to: from}
    {:next_state, {:parse, :next},  new_data, [{:next_event, :internal, {:parse, content}}]}
  end

  # we are in an invalid parsing state, abort and return an error with the current state and data
  def handle_event(:internal, {:parse, _}, state, %{valid?: false, answer_to: from} = data), do: {:stop_and_reply, :normal, [{:reply, from, {:error, {state, data}}}]}

  # we have reached the end of the binary, there's nothing else to do except answer the caller, if we're in something else than {:parse, :next} it's an error
  def handle_event(:internal, {:parse, ""}, state, %{answer_to: from} = data) do
    case state do
      {:parse, :next} -> reply_finish(data)
      _ -> {:stop_and_reply, :normal, [{:reply, from, {:error, {state, data}}}]}
    end
  end

  # we have reached a closing bracket } which means we should move back up in the chain ditching our last value in it, and start searching for the next token
  def handle_event(:internal,
    {:parse, <<125, rem::binary>>},
    {:parse, :next},
    %{current_chain: [_|_] = cc} = data
  ) do

    [_ | new_cc_1] = :lists.reverse(cc)
    new_cc_2 = :lists.reverse(new_cc_1)
    new_data =
      %{data | current_chain: new_cc_2}
      |> inc_col()

    {:keep_state, new_data, [{:next_event, :internal, {:parse, rem}}]} 
  end

  # we reached a closing bracket without being inside a block, error out
  def handle_event(:internal,
    {:parse, <<125, _::binary>>},
    {:parse, :next} = state,
    %{answer_to: from, current_chain: []} = data
  ) do
    new_data = %{data | valid?: false, error: "Mismatched }"}
    {:stop_and_reply, :normal, [{:reply, from, {:error, {state, new_data}}}]}
  end

  # we reached a closing bracket when searching for a key/attribute ditch whatever we have and add a warning
  def handle_event(:internal,
    {:parse, <<125, rem::binary>>},
    {:parse, type} = state,
    data
  ) when type in [:current_key, :current_var] do

    new_data =
      data
      |> add_warning(:missing, state)
      |> reset_current()
      |> inc_col()

    {:next_state, {:parse, :next}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  # we reached a closing bracket } while we were searching for a value to an attribute inside a previously opened block (we have a current chain), meaning there's no ; char, this is allowed on the last attr:val of a block, so we will do as if it was there and just reparse adding the ; to the beggining
  def handle_event(:internal,
    {:parse, <<125, _::binary>> = full},
    {:parse, _, _},
    %{current_chain: [_|_]} = data
  ) do
    {:keep_state, data, [{:next_event, :internal, {:parse, <<";", full::binary>>}}]}
  end

  # we reached an eex opening tag, because it requires dedicated handling and parsing we move to a different parse step
  def handle_event(:internal,
    {:parse, <<"<%", _::binary>> = full},
    state,
    data
  ) do
    {new_rem, new_data} = CSSEx.Helpers.EEX.parse(full, data)

    {:keep_state, new_data, [{:next_event, :internal, {:parse, new_rem}}]}
  end

  # we reached a new line char, reset the col, inc the line and continue
  Enum.each(@line_terminators, fn(char) ->
    def handle_event(:internal,
      {:parse, <<unquote(char), rem::binary>>},
      _,
      data
    ), do: {:keep_state, inc_line(data), [{:next_event, :internal, {:parse, rem}}]}
  end)


  Enum.each(@white_space, fn(char) ->
    # we reached a white-space char while searching for the next token, inc the column, keep searching
    def handle_event(:internal,
      {:parse, <<unquote(char), rem::binary>>},
      {:parse, :next},
      data
    ), do: {:keep_state, inc_col(data), [{:next_event, :internal, {:parse, rem}}]}

    # we reached a white-space while building a variable, move to parse the value now
    def handle_event(:internal,
      {:parse, <<unquote(char), rem::binary>>},
      {:parse, :current_var},
      data
    ),
 do: {:next_state, {:parse, :value, :current_var}, inc_col(data), [{:next_event, :internal, {:parse, rem}}]}

    # we reached a white-space while building an assign, move to parse the value now, the assign is special because it can be any term and needs to be validated by compiling it so we do it in a special parse step
    def handle_event(:internal,
      {:parse, <<unquote(char), rem::binary>>},
      {:parse, :current_assign},
      data
    ) do

      {new_rem, new_data} = CSSEx.Helpers.Assigns.parse(rem, inc_col(data))
      
      {:next_state, {:parse, :next}, reset_current(new_data) , [{:next_event, :internal, {:parse, new_rem}}]}
    end

    # we reached a white-space while building a value parsing - ditching the white-space depends on if we're in the middle of a value or in the beginning and the type of key we're searching
    def handle_event(:internal,
      {:parse, <<unquote(char), rem::binary>>},
      {:parse, :value, type},
      data
    ) do
      # we'll always inc the column counter no matter what
      new_data = inc_col(data)
      
      case Map.fetch!(data, type) do
	"" -> {:keep_state, new_data, [{:next_event, :internal, {:parse, rem}}]}
	val ->
	  new_data_2 = Map.put(new_data, type, [val | unquote(char)])
	  
	  {:keep_state, new_data_2, [{:next_event, :internal, {:parse, rem}}]}
      end
    end
  end)

  # We found an assign assigment when searching for the next token, prepare for parsing it
  def handle_event(:internal,
    {:parse, <<"%!", rem::binary>>},
    {:parse, :next},
    data
  ) do

    new_data =
      data
      |> set_scope(:global)
      |> inc_col(2)

    {:next_state, {:parse, :current_assign}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(:internal,
    {:parse, <<"%()", rem::binary>>},
    {:parse, :next},
    data
  ) do

    new_data =
      data
      |> set_scope(:local)
      |> inc_col(3)

    {:next_state, {:parse, :current_assign}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(:internal,
    {:parse, <<"%?", rem::binary>>},
    {:parse, :next},
    data
  ) do

    new_data =
      data
      |> set_scope(:conditional)
      |> inc_col(3)

    {:next_state, {:parse, :current_assign}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  # We found a var assignment when searching for the next token, prepare for parsing it
  def handle_event(:internal,
    {:parse, <<"@!", rem::binary>>},
    {:parse, :next},
    data
  ) do

    new_data =
      data
      |> set_scope(:global)
      |> inc_col(2)

    {:next_state, {:parse, :current_var}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(:internal,
    {:parse, <<"@*!", rem::binary>>},
    {:parse, :next},
    data
  ) do

    new_data =
      data
      |> set_scope(:global)
      |> set_add_var()
      |> inc_col(3)

    {:next_state, {:parse, :current_var}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(:internal,
    {:parse, <<"@()", rem::binary>>},
    {:parse, :next},
    data
  ) do

    new_data =
      data
      |> set_scope(:local)
      |> inc_col(3)

    {:next_state, {:parse, :current_var}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(:internal,
    {:parse, <<"@*()", rem::binary>>},
    {:parse, :next},
    data
  ) do

    new_data =
      data
      |> set_scope(:local)
      |> set_add_var()
      |> inc_col(4)

    {:next_state, {:parse, :current_var}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(:internal,
    {:parse, <<"@?", rem::binary>>},
    {:parse, :next},
    data
  ) do

    new_data =
      data
      |> set_scope(:conditional)
      |> inc_col(2)

    {:next_state, {:parse, :current_var}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(:internal,
    {:parse, <<"@*?", rem::binary>>},
    {:parse, :next},
    data
  ) do

    new_data =
      data
      |> set_scope(:conditional)
      |> set_add_var()
      |> inc_col(3)

    {:next_state, {:parse, :current_var}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  # we found the selector end char { opening a css inner context while searching for the :current_key, which means that this is a selector that we were parsing, add it and start searching for the next token (we use 123 because ?{ borks the text-editor identation
  def handle_event(:internal,
    {:parse, <<123, rem::binary>>},
    {:parse, :current_key},
    data
  ) do

    ## TODO validate it's a valid selector, error if not
    
    new_data =
      data
      |> add_current_selector()
      |> reset_current()
      |> inc_line()
      |> first_rule()

    {:next_state, {:parse, :next}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  # we found the key separator : while searching for the :current_key, which means this is an attribute that we were parsing, add it and start searching for the next token which will be the value
  def handle_event(:internal,
    {:parse, <<?:, rem::binary>>},
    {:parse, :current_key},
    data
  ) do
    
    {:next_state, {:parse, :value, :current_value}, inc_col(data), [{:next_event, :internal, {:parse, rem}}]}
  end

  # we found a non-white-space/line-end char while searching for the next token, which means it's a regular css rule start, prepare for parsing it
  def handle_event(:internal,
    {:parse, <<char, rem::binary>>},
    {:parse, :next},
    data
  ) do

    new_data =
      data
      |> Map.put(:current_key, [char])
      |> inc_col()
      |> first_rule()
    
    {:next_state, {:parse, :current_key}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end
 

  # we're accumulating on something, add the value to that type we're accumulating
  def handle_event(:internal,
    {:parse, <<char, rem::binary>>},
    {:parse, type},
    data
  ), do: {:keep_state, Map.put(data, type, [Map.fetch!(data, type), char]), [{:next_event, :internal, {:parse, rem}}]}

  # we reached the termination ; char while assembling a variable, cleanup and add it to the correct scopes
  def handle_event(:internal,
    {:parse, <<?;, rem::binary>>},
    {:parse, :value, :current_var},
    %{current_var: current_var, current_value: current_value} = data
  ) do
    
    cvar = IO.iodata_to_binary(current_var)
    cval = String.trim_trailing(IO.iodata_to_binary(current_value))

    ## TODO add checks on var name && and value, emit warnings if invalid;
    
    new_data =
      data
      |> maybe_add_css_var(cvar, cval)
      |> add_to_var(cvar, cval)
      |> reset_current()
      |> inc_col()
    
    {:next_state, {:parse, :next}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  # we reached the termination ; char while assembling an attribute, cleanup and add it to the correct ets slot
  def handle_event(:internal,
    {:parse, <<?;, rem::binary>>},
    {:parse, :value, :current_value},
    %{current_key: current_key, current_value: current_value} = data
  ) do
    
    ckey = IO.iodata_to_binary(current_key)
    cval = String.trim_trailing(IO.iodata_to_binary(current_value))

    ## TODO add checks on attribute & value, emit warnings if invalid;
    
    new_data =
      data
      |> add_to_attributes(ckey, cval)
      |> reset_current()
      |> inc_col()
      |> first_rule()

    {:next_state, {:parse, :next}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  # a valid char while we're accumulating for a value, add it and continue
  def handle_event(:internal,
    {:parse, <<char, rem::binary>>},
    {:parse, :value, _type},
    %{current_value: cval} = data
  ), do: {:keep_state, %{inc_col(data) | current_value: [cval, char]}, [{:next_event, :internal, {:parse, rem}}]}

  # set the scope for whatever we're doing, scopes can only be set by when parsing variables or assigns if it's not nil there's a problem
  def set_scope(%{current_scope: nil} = data, scope), do: %{data | current_scope: scope}

  # set var, it should be always false when this is called for the same reasons as set_scop
  def set_add_var(%{current_add_var: false} = data), do: %{data | current_add_var: true}
  
  # add the variable to the global and local scopes
  def add_to_var(
    %{current_scope: :global, scope: scope, local_scope: local_scope} = data,
    key,
    val
  ), do: %{
	data |
	scope: Map.put(scope, key, val),
	local_scope: Map.put(local_scope, key, val),
     }

  # add the variable only to the local scope
  def add_to_var(
    %{current_scope: :local, local_scope: local_scope} = data,
    key,
    val
  ), do: %{data | local_scope: Map.put(local_scope, key, val)}

  # conditionally add variable to the local scope if it's not in scope
  def add_to_var(
    %{current_scope: :conditional, local_scope: local_scope, scope: scope} = data,
    key,
    val
  ) do
    case Map.get(scope, key) do
      nil ->
	case Map.get(local_scope, key) do
	  nil -> %{data | local_scope: Map.put(local_scope, key, val)}
	  _ -> data
	end
      _ -> data
    end
  end

  # add attribute to the ETS table
  def add_to_attributes(%{ets: ets, current_chain: cc} = data, key, val) do
      case maybe_replace_val(val, data) do
	{:ok, new_val} ->
	  
	  case :ets.lookup(ets, cc) do
	    [{_, existing}] -> :ets.insert(ets, {cc, [existing, key, ":", new_val, ";"]})
	    [] -> :ets.insert(ets, {cc, [key, ":", new_val, ";"]})
	  end
	  data
	
      {:error, :not_declared} ->
	  %{data | valid?: false, error: "#{val} was not declared"}
      end
  end

# add the current_selector to the current_chain
  def add_current_selector(%{current_chain: cc, current_key: cs} = data) do
    current_selector = String.trim_trailing(IO.iodata_to_binary(cs))
    
    Map.put(data, :current_chain, cc ++ [current_selector])
  end


  # reset the accumulators and scope
  def reset_current(data),
    do: %{
	  data |
	  current_key: "",
	  current_value: "",
	  current_var: "",
	  current_assign: "",
	  current_scope: nil,
	  current_add_var: false
    }

  # replaces the value if it mentions a cssex variable and that variable is bound in either the local_scope (first match) or the global scope (second match)
  def maybe_replace_val(<<"@::", var_name::binary>>, %{local_scope: ls}) when is_map_key(ls, var_name),
    do: {:ok, Map.fetch!(ls, var_name)}

  def maybe_replace_val(<<"@::", var_name::binary>>, %{scope: scope}) when is_map_key(scope, var_name),
    do: {:ok, Map.fetch!(scope, var_name)}

  def maybe_replace_val(<<"@::", _::binary>>, _), do: {:error, :not_declared}

  def maybe_replace_val(val, _), do: {:ok, val}

  def maybe_add_css_var(%{current_add_var: false} = data, _, _), do: data
  def maybe_add_css_var(
    %{current_add_var: true, current_scope: current_scope, local_scope: local_scope, scope: scope, current_chain: []} = data,
    key,
    val
  ) do
    
    check_if_to_add =
      case current_scope do
	:conditional -> !(Map.get(scope, key, false) and Map.get(local_scope, key, false))
	_ -> true
      end

    case check_if_to_add do
      true ->
	case maybe_replace_val(val, data) do
	  {:ok, new_val} -> add_css_var(data, [":root"], ["--", key, ":", new_val, ";"])
	    
	  {:error, :not_declared} ->
	      %{data | valid?: false, error: "#{val} was not declared"}
	end
	_ -> data
    end
  end

  def add_css_var(%{ets: ets} = data, cc, to_add) do
    case :ets.lookup(ets, cc) do
      [{_, existing}] -> :ets.insert(ets, {cc, [existing | to_add]})
      [] -> :ets.insert(ets, {cc, to_add})
    end

    data
  end

  def first_rule(%{first_rule: false} = data), do: data
  def first_rule(data), do: %{data | first_rule: false}

  def add_warning(%{warnings: warnings, column: col, line: line} = data, :missing, {:parse, _}),
    do: %{data | warnings: ["Incomplete declaration at line #{line} and col #{col} - this line was removed" | warnings]}

  # reply back according to the level
  def reply_finish(%{answer_to: from, ets: ets, level: 0} = data) do
    css = :ets.foldl(
      fn({selector, attributes}, acc) ->
	[acc, selector, "{", attributes, "}\n"]
      end,
      [],
      ets
    )
    #IO.inspect(data)
    {:stop_and_reply, :normal, [{:reply, from, {:ok, data, IO.iodata_to_binary(css)}}]}
  end
  
end
