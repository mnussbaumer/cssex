defmodule CSSEx.Parser do
  import CSSEx.Helpers.Shared, only: [inc_col: 1, inc_col: 2, inc_line: 1]

  @behaviour :gen_statem

  @timeout 15_000

  @enforce_keys [:ets, :ets_fontface, :ets_keyframes, :line, :column]
  defstruct [
    :ets,
    :ets_fontface,
    :ets_keyframes,
    :line,
    :column,
    :error,
    :answer_to,
    :current_line,
    :current_column,
    file: nil,
    file_list: [],
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
    warnings: [],
    media: %{},
    prefix: nil,
    font_face: false,
    font_face_count: 0,
    imports: []
  ]

  @white_space CSSEx.Helpers.WhiteSpace.code_points()
  @line_terminators CSSEx.Helpers.LineTerminators.code_points()

  ## TODO
  # "@font-feature-values", # Allows authors to use a common name in font-variant-alternate for feature activated differently in OpenType

  @doc """
  Takes a file path to a cssex or css file and parses it into a final CSS representation returning either:
  {:ok, final_binary, term}
  {:error, term}
  """
  def parse_file(file_path) do
    {:ok, pid} = __MODULE__.start_link()
    :gen_statem.call(pid, {:start_file, file_path})
  end
  
  @doc """
  Takes a binary parses it into a final CSS representation and returns either:
  {:ok, final_binary, term}
  {:error, term}
  """

  def parse(content) do
    {:ok, pid} = __MODULE__.start_link()
    :gen_statem.call(pid, {:start, content})
  end

  def parse_inner(%__MODULE__{} = data, content) do
    {:ok, pid} = __MODULE__.start_link(data)
    :gen_statem.call(pid, {:start, content})
  end

  @impl :gen_statem
  def callback_mode(), do: :handle_event_function

  def start_link() do
    :gen_statem.start_link(__MODULE__, nil, [])
  end

  def start_link(%__MODULE__{} = starting_data) do
    :gen_statem.start_link(__MODULE__, starting_data, [])
  end
    
  @impl :gen_statem
  def init(nil) do
    table_ref = :ets.new(:base, [])
    table_font_face_ref = :ets.new(:font_face, [])
    table_keyframes_ref = :ets.new(:keyframes, [])
    {:ok, :waiting, %__MODULE__{ets: table_ref, line: 0, column: 0, ets_fontface: table_font_face_ref, ets_keyframes: table_keyframes_ref}, [@timeout]}
  end

  def init(%__MODULE__{} = starting_data) do
    {:ok, :waiting, starting_data, [@timeout]}
  end

  @impl :gen_statem
  def handle_event({:call, from}, {:start, content}, :waiting, data) do
    new_data = %__MODULE__{data | answer_to: from}
    {:next_state, {:parse, :next},  new_data, [{:next_event, :internal, {:parse, content}}]}
  end

  def handle_event({:call, from}, {:start_file, path}, :waiting, data) do
    case File.read(path) do
      {:ok, content} ->
	new_data = %__MODULE__{data | answer_to: from, file: path, file_list: [path]}
	{:next_state, {:parse, :next}, new_data, [{:next_event, :internal, {:parse, content}}]}
    end
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

  def handle_event(:internal,
    {:parse, <<"@import", rem::binary>>},
    {:parse, :next},
    data
  ) do

    new_data =
      data
      |> inc_col(7)

    {:next_state, {:parse, :value, :import}, new_data, [{:next_event, :internal, {:parse, rem}}]}
    
  end

  def handle_event(:internal,
    {:parse, <<"@charset", rem::binary>>},
    {:parse, :next},
    data
  ) do

    new_data =
      data
      |> inc_col(8)
    
    {:next_state, {:parse, :value, :charset}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(:internal,
    {:parse, <<"@media", rem::binary>>},
    {:parse, :next},
    data
  ) do

    new_data =
      data
      |> inc_col(6)
    
    {:next_state, {:parse, :value, :media}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(:internal,
    {:parse, <<"@keyframes", rem::binary>>},
    {:parse, :next},
    data
  ) do

    new_data =
      data
      |> inc_col(10)

    {:next_state, {:parse, :value, :keyframes}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(:internal,
    {:parse, <<"@font-face", rem::binary>>},
    {:parse, :next},
    %{current_chain: [], font_face: false, font_face_count: ffc} = data
  ) do

    new_data =
      %{data | font_face: true, font_face_count: ffc + 1}
      |> inc_col(10)
      |> first_rule()

    {:next_state, {:parse, :current_key}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  # we have reached a closing bracket } while accumulating a font-face, reset the font-face toggle and resume normal parsing
  def handle_event(:internal,
    {:parse, <<125, rem::binary>>},
    {:parse, :next},
    %{font_face: true} = data
  ) do

    new_data =
      %{data | font_face: false}
      |> inc_col(1)

    {:keep_state, new_data, [{:next_event, :internal, {:parse, rem}}]}
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

  # we reached a closing bracket without being inside a block and at the top level, error out
  def handle_event(:internal,
    {:parse, <<125, _::binary>>},
    {:parse, :next} = state,
    %{answer_to: from, current_chain: [], line: line, column: col, level: 0} = data
  ) do
    new_data = %{data | valid?: false, error: "Mismatched } at l:#{line} c:#{col}"}
    {:stop_and_reply, :normal, [{:reply, from, {:error, {state, new_data}}}]}
  end

  # we reached a closing bracket without being inside a block in an inner level, inc the col and return to original the current data and the remaining text
  def handle_event(:internal,
    {:parse, <<125, rem::binary>>},
    {:parse, :next},
    %{answer_to: from, current_chain: []} = data
  ), do: {:stop_and_reply, :normal, [{:reply, from, {:finished, {inc_col(data), rem}}}]}

  # we reached a closing bracket when searching for a key/attribute ditch whatever we have and add a warning
  
  # TODO this will be wrong if we're on a current_key and this is part of a string, like div[data-json="{a: 1}"]
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
    _state,
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

    # we reached a white-space while building a media query or keyframe name, include the whitespace in the value
    def handle_event(:internal,
      {:parse, <<unquote(char), rem::binary>>},
      {:parse, :value, type},
      %{current_value: cval} = data
    ) when type in [:media, :keyframes, :import], do: {
      :keep_state,
      %{data | current_value: [cval | unquote(char)]},
      [{:next_event, :internal, {:parse, rem}}]
    }

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
	nil when type in [:charset] -> {:keep_state, new_data, [{:next_event, :internal, {:parse, rem}}]}
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


  # we found the selector end char { opening a css inner context while searching for the :current_key, which means that this is a selector that we were parsing, add it and start searching for the next token (we use 123 because ?{ borks the text-editor identation)
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
      |> inc_col()
      |> first_rule()

    {:next_state, {:parse, :next}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  # we found the selector end char { opening a css inner context while parsing the @media attributes, we start a subsequent gen_statem to continue which will accumulate itself and answer back to this one where it will merge what was found there
  def handle_event(:internal,
    {:parse, <<123, rem::binary>>},
    {:parse, :value, :media},
    data
  ) do
    
    inner_data = create_data_for_inner(data, false, nil)
    
    case __MODULE__.parse_inner(inner_data, rem) do
      {:finished, {%{column: n_col, line: n_line} = new_inner_data, new_rem}} ->
	new_data = (
	  %{data | line: n_line, column: n_col}
	  |> add_media_query(new_inner_data)
	  |> reset_current()
	)

	{:next_state, {:parse, :next}, new_data, [{:next_event, :internal, {:parse, new_rem}}]}
	## TODO error needs to stop correctly
      error -> error
    end
  end

  # we found the selector end char { opening a css inner context while parsing the @keyframes name, we'll do the parsing for those in a new parser gen_statem because we can't construct the key path correctly from this level, but inside the keyframe block they're in all similar to a normal css selector + block, then with the result of that parser we'll put all those elements inside a single selector @keyframes + animation name
  def handle_event(:internal,
    {:parse, <<123, rem::binary>>},
    {:parse, :value, :keyframes},
    data
  ) do

    # create a new ets table, public, so that the new started process can write to it
    inner_data = create_data_for_inner(data)

    case __MODULE__.parse_inner(inner_data, rem) do
      {:finished, {%{column: n_col, line: n_line} = new_inner_data, new_rem}} ->
	new_data = (
	  %{data | line: n_line, column: n_col}
	  |> add_keyframe(new_inner_data)
	  |> reset_current()
	)
	
	{:next_state, {:parse, :next}, new_data, [{:next_event, :internal, {:parse, new_rem}}]}
	## TODO error needs to stop correctly
      error -> error
    end
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

  # we reached the termination ; char while assembling a special attribute, @charset, cleanup and verify it's valid to add
  def handle_event(:internal,
    {:parse, <<?;, rem::binary>>},
    {:parse, :value, :charset},
    data
  ) do

    new_data =
      data
      |> validate_charset()
      |> reset_current()
      |> inc_col()

    {:next_state, {:parse, :next}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  # we reached the termination ; char while assembling a special attribute, @import, cleanup and verify it's valid to add
  def handle_event(:internal,
    {:parse, <<?;, rem::binary>>},
    {:parse, :value, :import},
    data
  ) do

    new_data =
      data
      |> validate_import()
      |> reset_current()
      |> inc_col()

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

  # add to font-face ETS table when dealing with a font-face block
  def add_to_attributes(%{font_face: true, ets_fontface: ets, font_face_count: ffc} = data, key, val) do
    case maybe_replace_val(val, data) do
      {:ok, new_val} ->
	case :ets.lookup(ets, ffc) do
	  [{_, existing}] -> :ets.insert(ets, {ffc, [existing, key, ":", new_val, ";"]})
	  [] -> :ets.insert(ets, {ffc, [key, ":", new_val, ";"]})
	end
	data
      {:error, :not_declared} -> %{data | valid?: false, error: "#{val} was not declared"}
    end
  end

  # add attribute to the ETS table
  def add_to_attributes(%{ets: ets, current_chain: current_chain, prefix: prefix} = data, key, val) do
    case maybe_replace_val(val, data) do
	{:ok, new_val} ->
	cc_base = if(prefix, do: prefix ++ current_chain, else: current_chain)
	cc = CSSEx.Helpers.Shared.ampersand_join(cc_base)
	  case :ets.lookup(ets, cc) do
	    [{_, existing}] -> :ets.insert(ets, {cc, [existing, key, ":", new_val, ";"]})
	    [] -> :ets.insert(ets, {cc, [key, ":", new_val, ";"]})
	  end
	  data
	
      {:error, :not_declared} ->
	  %{data | valid?: false, error: "#{val} was not declared"}
      end
  end

  # add a special case for when parsing a font-face
  def add_current_selector(%{font_face: true} = data), do: data
  
  # add the current_selector to the current_chain
  def add_current_selector(%{current_chain: cc, current_key: cs} = data) do
    current_selector = String.trim_trailing(IO.iodata_to_binary(cs))
    case maybe_replace_val(current_selector, data) do
      {:ok, replaced_selector} ->    
	Map.put(data, :current_chain, cc ++ [replaced_selector])
      _ -> %{data | valid?: false, error: "variable in #{current_selector} was not declared"}
    end
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
  def maybe_replace_val(<<"@$$", var_name::binary>>, %{local_scope: ls}) when is_map_key(ls, var_name),
    do: {:ok, Map.fetch!(ls, var_name)}

  def maybe_replace_val(<<"@$$", var_name::binary>>, %{scope: scope}) when is_map_key(scope, var_name),
    do: {:ok, Map.fetch!(scope, var_name)}

  def maybe_replace_val(<<"@$$", var_name::binary>>, _data), do: {:error, {:not_declared, var_name}}

  def maybe_replace_val(val, data) do
    case Regex.scan(~r/<\$(.+?)\$>/u, val) do
      [] -> {:ok, val}
      tokens ->
	Enum.reduce_while(tokens, {:ok, val}, fn([token, var_name], {_result, acc}) ->
	  case var_name do
	    <<"@$$", _::binary>> ->
	      case maybe_replace_val(var_name, data) do
		{:ok, replaced} -> {:cont, {:ok, String.replace(acc, token, replaced)}}
		error -> {:halt, error}
	      end
	    _ ->
	      case maybe_replace_val("@$$" <> var_name, data) do
		{:ok, replaced} -> {:cont, {:ok, String.replace(acc, token, replaced)}}
		error -> {:halt, error}
	      end
	  end
	end)
    end
  end

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
	    
	  {:error, {:not_declared, _ }} ->
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

  @doc """
  Right now just checks if the charset has enclosing doube-quotes, ", might want to check if the value is actually a valid charset? https://www.iana.org/assignments/character-sets/character-sets.xhtml.
  """
  def validate_charset(%{current_value: charset, charset: nil, first_rule: true} = data) do
    new_charset =
      charset
      |> IO.iodata_to_binary()
      |> String.trim(~s("))
    
    %{data | charset: ~s("#{new_charset}")}
  end

  def validate_charset(%{charset: charset, first_rule: first_rule, line: line, column: col, warnings: warnings} = data) do
    warning_1 =
      case charset do
	nil -> []
	_ -> ["Only a single @charset declaration is valid l:#{line} c:#{col}"]
      end

    warning_2 =
      case first_rule do
	true -> warning_1
	_ -> ["@charset declaration must be the first rule in a spreadsheet l:#{line} c:#{col}" | warning_1]
      end

    
    %{data | warnings: :lists.flatten([warning_2 | warnings])}
    |> reset_current()
  end

  def validate_import(%{current_value: current_value, first_rule: true, imports: imports} = data) do
    {:ok, cval} =
      current_value 
      |> IO.iodata_to_binary()
      |> String.trim()
      |> maybe_replace_val(data)

    %{data | imports: [imports | ["@import", " ", cval, ";"]]}
  end

  def validate_import(%{first_rule: false, line: line, column: col, warnings: warnings} = data) do

    %{data | warnings: :lists.flatten([warnings | "@import declarations must be at the top level of a file, with exception of the @charset declaration that comes always first if present l:#{line} c:#{col}"])}
  end
  
  def first_rule(%{first_rule: false} = data), do: data
  def first_rule(data), do: %{data | first_rule: false}

  def add_warning(%{warnings: warnings, column: col, line: line} = data, :missing, {:parse, _}),
    do: %{data | warnings: ["Incomplete declaration at l:#{line} and c:#{col} - this line was removed" | warnings]}

  # reply back according to the level
  def reply_finish(%{answer_to: from, ets: ets, level: 0} = data) do
    css = fold_attributes_table(ets)
    final_css = add_last_special_attributes(data, css)
    
    {
      :stop_and_reply,
      :normal,
      [{:reply, from, {:ok, data, IO.iodata_to_binary([final_css, "\n"])}}]
    }
  end

  @doc """
  Adds special rules like @charset to the stylesheet iodata_list, since those have to be in the beginning of the file to not be ignored by browser parsers. 
  """
  def add_last_special_attributes(data, iodata) do
    iodata
    |> maybe_add_font_faces(data)
    |> maybe_add_imports(data)
    |> maybe_add_charset(data)
    |> maybe_add_media(data)
    |> maybe_add_keyframes(data)
  end

  def maybe_add_font_faces(iodata, %{ets_fontface: ets}) do
    css = fold_font_faces_table(ets)
    [css | iodata]
  end

  def maybe_add_charset(iodata, %{charset: charset}) when is_binary(charset),
    do: ["@charset #{charset};", iodata]

  def maybe_add_charset(iodata, _), do: iodata

  def maybe_add_imports(iodata, %{imports: imports}),
    do: [imports | iodata]

  def maybe_add_media(iodata, %{media: media}) do
    Enum.reduce(media, iodata, fn({media_rule, ets_table}, acc) ->
      [acc, media_rule, "{", fold_attributes_table(ets_table), "}"]
    end)
  end

  def maybe_add_keyframes(iodata, %{ets_keyframes: ets}) do
    css = fold_attributes_table(ets)
    [iodata | css]
  end

  def fold_attributes_table(ets) do
    :ets.foldl(
      fn({selector, attributes}, acc) ->
	[acc, Enum.join(selector, " "), "{", attributes, "}"]
      end,
      [],
      ets
    )
  end

  def fold_font_faces_table(ets) do
    :ets.foldl(
      fn({_, attributes}, acc) ->
	[acc, "@font-face{", attributes, "}"]
      end,
      [],
      ets
    )
  end

  @doc """
  Adds a media query, taking care of translating the contents parsed in the upper level to the correct selectors
  """
  def add_media_query(
    %{current_value: current_value, current_chain: _current_chain, media: media} = data,
    %{ets: inner_ets} = _new_inner_data
  ) do

    parsed = IO.iodata_to_binary(current_value)
    {parsed_2, data} = CSSEx.Helpers.Media.parse(parsed, data)
    
    case maybe_replace_val(parsed_2, data) do
      {:ok, cval} ->
	media_query = IO.iodata_to_binary(["@media" | cval]) |> String.trim_trailing()
	
	new_media =
	  case Map.get(media, media_query) do
	    nil -> Map.put(media, media_query, inner_ets)
	    original_ets ->
	      :ets.foldl(
		fn({selector, attributes}, _acc) ->
		  case :ets.lookup(original_ets, selector) do
		    [] -> :ets.insert(original_ets, {selector, attributes})
		    [{_, existing}] -> :ets.insert(original_ets, {selector, [existing | attributes]})
		  end
		end,
		:ok,
		inner_ets
	      )
	      
	      :ets.delete(inner_ets)
	      media
	  end
	%{data | media: new_media}
	
      {:error, {:not_declared, val}} -> add_error(data, "#{val} was not declared")
    end
  end

  @doc """
  Adds a keyframe element, where the chain is simply ["@keyframe", animation_name]
  """
  def add_keyframe(
    %{ets_keyframes: original_ets, current_value: current_value} = data,
    %{ets: inner_ets} = _new_inner_data
  ) do

    parsed = IO.iodata_to_binary(current_value)
    
    case maybe_replace_val(parsed, data) do
      {:ok, cval} ->
	full_path = ["@keyframes", String.trim(cval)]
	folded_css = fold_attributes_table(inner_ets)
	
	case :ets.lookup(original_ets, full_path) do
	  [] -> :ets.insert(original_ets, {full_path, folded_css})
	  [{_, existing}] -> :ets.insert(original_ets, {full_path, [existing | folded_css]})
	end

	:ets.delete(inner_ets)
	data
	
      {:error, {:not_declared, val}} -> add_error(data, "#{val} was not declared")
    end
  end

  def create_data_for_inner(
    %{
      line: line, column: col, level: level,
      ets_fontface: etsff, ets_keyframes: etskf, font_face_count: ffc,
      assigns: assigns, local_assigns: l_assigns, scope: scope, local_scope: l_scope
    } = data,
    ets \\ nil,
    prefix \\ nil
  ) do
    inner_ets = if(ets, do: ets, else: :ets.new(:inner, [:public]))
    inner_prefix = if(prefix, do: prefix, else: if(prefix == false, do: nil, else: CSSEx.Helpers.Shared.generate_prefix(data)))
    inner_assigns = Map.merge(assigns, l_assigns)
    inner_scope = Map.merge(scope, l_scope)
    
    %__MODULE__{
      ets: inner_ets,
      line: line,
      column: col,
      level: level + 1,
      prefix: inner_prefix,
      ets_fontface: etsff,
      ets_keyframes: etskf,
      font_face_count: ffc,
      local_assigns: inner_assigns,
      local_scope: inner_scope
    }
  end

  def add_error(%{line: line, column: column} = data, error) do
    %{data | valid?: false, error: "#{error} :: l:#{line} c:#{column}"}
  end
end
