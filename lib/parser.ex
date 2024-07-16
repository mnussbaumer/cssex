defmodule CSSEx.Parser do
  @moduledoc """
  The parser module that generates or writes a CSS file based on an entry file.
  """

  import CSSEx.Helpers.Shared,
    only: [inc_col: 1, inc_col: 2, inc_line: 1, remove_last_from_chain: 1, inc_no_count: 2]

  import CSSEx.Helpers.Interpolations, only: [maybe_replace_val: 2]
  import CSSEx.Helpers.Error, only: [error_msg: 1, warning_msg: 1]

  alias CSSEx.Helpers.Shared, as: HShared
  alias CSSEx.Helpers.Output
  @behaviour :gen_statem

  @timeout 15_000

  @functions Enum.reduce(CSSEx.Helpers.Functions.__info__(:functions), %{}, fn {fun, arity},
                                                                               acc ->
               Map.put(
                 acc,
                 Atom.to_string(fun),
                 Function.capture(CSSEx.Helpers.Functions, fun, arity)
               )
             end)

  @enforce_keys [:ets, :ets_fontface, :ets_keyframes, :line, :column]
  defstruct [
    :ets,
    :ets_fontface,
    :ets_keyframes,
    :line,
    :column,
    :error,
    :answer_to,
    :to_file,
    no_count: 0,
    current_reg: [],
    base_path: nil,
    file: nil,
    file_list: [],
    pass: 1,
    scope: %{},
    local_scope: %{},
    assigns: %{},
    local_assigns: %{},
    current_chain: [],
    split_chain: [[]],
    valid?: true,
    current_key: [],
    current_value: [],
    current_var: [],
    current_assign: [],
    current_scope: nil,
    current_add_var: false,
    current_function: [],
    functions: @functions,
    level: 0,
    charset: nil,
    first_rule: true,
    warnings: [],
    media: %{},
    media_parent: "",
    page: %{},
    page_parent: "",
    supports: %{},
    supports_parent: "",
    source_pid: nil,
    prefix: nil,
    font_face: false,
    font_face_count: 0,
    imports: [],
    dependencies: [],
    search_acc: [],
    order_map: %{c: 0},
    keyframes_order_map: %{c: 0},
    expandables: %{},
    expandables_order_map: %{c: 0},
    pretty_print?: false
  ]

  @white_space CSSEx.Helpers.WhiteSpace.code_points()
  @line_terminators CSSEx.Helpers.LineTerminators.code_points()

  ## TODO
  # "@font-feature-values", # Allows authors to use a common name in font-variant-alternate for feature activated differently in OpenType

  @doc """
  Takes a file path to a cssex or css file and parses it into a final CSS
   representation returning either:

  ```
  {:ok, %CSSEx.Parser{}, final_binary}
  {:error, %CSSEx.Parser{}}
  ```

  Additionally a `%CSSEx.Parser{}` struct with prefilled details can be passed as the first
  argument in which case the parser will use it as its configuration. 
  You can also pass a file path as the last argument and instead of returning the final binary on the `:ok` tuple it will write the css directly into that file path and return an empty list instead of the final binary
  """
  @spec parse_file(path :: String.t(), file_path :: String.t()) ::
          {:ok, %CSSEx.Parser{}, String.t()}
          | {:error, %CSSEx.Parser{error: String.t(), valid?: false}}
  def parse_file(base_path, file_path),
    do: parse_file(nil, base_path, file_path, nil, pretty_print?: false)

  @spec parse_file(%CSSEx.Parser{} | String.t(), String.t(), String.t()) ::
          {:ok, %CSSEx.Parser{}, String.t() | []}
          | {:error, %CSSEx.Parser{error: String.t(), valid?: false}}
  def parse_file(%CSSEx.Parser{} = data, base_path, file_path),
    do: parse_file(data, base_path, file_path, nil, pretty_print?: false)

  @spec parse_file(
          %CSSEx.Parser{} | nil,
          path :: String.t(),
          file_path :: String.t(),
          output_path :: String.t() | nil
        ) ::
          {:ok, %CSSEx.Parser{}, String.t() | []}
          | {:error, %CSSEx.Parser{error: String.t(), valid?: false}}
  def parse_file(base_path, file_path, parse_to_file),
    do: parse_file(nil, base_path, file_path, parse_to_file, pretty_print?: false)

  def parse_file(data, base_path, file_path, parse_to_file),
    do: parse_file(data, base_path, file_path, parse_to_file, pretty_print?: false)

  @spec parse_file(
          %CSSEx.Parser{} | nil,
          path :: String.t(),
          file_path :: String.t(),
          output_path :: String.t() | nil,
          options :: [pretty_print?: boolean()]
        ) ::
          {:ok, %CSSEx.Parser{}, String.t() | []}
          | {:error, %CSSEx.Parser{error: String.t(), valid?: false}}
  def parse_file(data, base_path, file_path, parse_to_file, options) do
    options =
      case data do
        nil -> options
        %__MODULE__{} -> data
      end

    {:ok, pid} = __MODULE__.start_link(options)
    :gen_statem.call(pid, {:start_file, base_path, file_path, parse_to_file})
  end

  @doc """
  Parses a `String.t` or a `charlist` and returns `{:ok, %CSSEx.Parser{}, content_or_empty_list}` or `{:error, %CSSEx.Parser{}}`.
  If a file path is passed as the final argument it returns the `:ok` tuple with an empty list instead of the content and writes into the file path.
  On error it returns an :error tuple with the `%CSSEx.Parser{}` having its `:error` key populated.
  If the first argument is a prefilled `%CSSEx.Parser{}` struct the parser uses that as its basis allowing to provide an `ETS` table that can be retrieved in the end, or passing predefined functions, assigns or variables, prefixes and etc into the context of the parser.
  """
  @spec parse(content :: String.t() | charlist) ::
          {:ok, %CSSEx.Parser{valid?: true}, String.t() | []}
          | {:error, %CSSEx.Parser{error: String.t(), valid?: false}}

  def parse(content), do: parse(nil, content, nil, pretty_print?: false)

  @spec parse(base_config :: %CSSEx.Parser{} | nil, content :: String.t() | charlist) ::
          {:ok, %CSSEx.Parser{valid?: true}, String.t() | []}
          | {:error, %CSSEx.Parser{error: String.t(), valid?: false}}

  def parse(%__MODULE__{} = data, content), do: parse(data, content, nil, pretty_print?: false)
  def parse(content, file), do: parse(nil, content, file, pretty_print?: false)

  @spec parse(
          base_config :: %CSSEx.Parser{} | nil,
          content :: String.t() | charlist,
          output_file :: String.t() | nil
        ) ::
          {:ok, %CSSEx.Parser{valid?: true}, String.t() | []}
          | {:error, %CSSEx.Parser{error: String.t(), valid?: false}}

  def parse(data, content, parse_to_file) when is_binary(content),
    do: parse(data, to_charlist(content), parse_to_file, pretty_print?: false)

  @spec parse(
          base_config :: %CSSEx.Parser{} | nil,
          content :: String.t() | charlist,
          output_file :: String.t() | nil,
          options :: [pretty_print?: boolean()]
        ) ::
          {:ok, %CSSEx.Parser{valid?: true}, String.t() | []}
          | {:error, %CSSEx.Parser{error: String.t(), valid?: false}}

  def parse(data, content, parse_to_file, options) when is_binary(content),
    do: parse(data, to_charlist(content), parse_to_file, options)

  def parse(data, content, parse_to_file, options) do
    options =
      case data do
        nil -> options
        %__MODULE__{} -> data
      end

    {:ok, pid} = __MODULE__.start_link(options)
    :gen_statem.call(pid, {:start, content, parse_to_file})
  end

  @impl :gen_statem
  def callback_mode(), do: :handle_event_function

  @doc false
  def start_link(opts \\ [])

  def start_link(%__MODULE__{} = starting_data) do
    :gen_statem.start_link(__MODULE__, starting_data, [])
  end

  def start_link(opts) do
    :gen_statem.start_link(__MODULE__, opts, [])
  end

  @impl :gen_statem
  def init(nil),
    do: init([])

  def init(options) when is_list(options) do
    table_ref = :ets.new(:base, [:public])
    table_font_face_ref = :ets.new(:font_face, [:public])
    table_keyframes_ref = :ets.new(:keyframes, [:public])

    pretty_print? = Keyword.get(options, :pretty_print?, false)

    {:ok, :waiting,
     %__MODULE__{
       ets: table_ref,
       line: 1,
       column: 1,
       ets_fontface: table_font_face_ref,
       ets_keyframes: table_keyframes_ref,
       source_pid: self(),
       pretty_print?: pretty_print?
     }, [@timeout]}
  end

  def init(%__MODULE__{} = starting_data) do
    {:ok, :waiting, starting_data, [@timeout]}
  end

  @impl :gen_statem
  def handle_event({:call, from}, {:start, content, parse_to_file}, :waiting, data) do
    new_data = %__MODULE__{data | answer_to: from, to_file: parse_to_file}
    {:next_state, {:parse, :next}, new_data, [{:next_event, :internal, {:parse, content}}]}
  end

  def handle_event(
        {:call, from},
        {:start_file, base_path, file_path, parse_to_file},
        :waiting,
        %{file_list: file_list} = data
      ) do
    path = Path.expand(file_path, base_path)

    case path in file_list do
      true ->
        {:stop_and_reply, :normal,
         [
           {
             :reply,
             from,
             {:error, add_error(data, error_msg({:cyclic_reference, path, file_list}))}
           }
         ]}

      _ ->
        case File.open(path, [:read, :charlist]) do
          {:ok, device} ->
            new_data = %__MODULE__{
              data
              | answer_to: from,
                file: path,
                file_list: [path | file_list],
                base_path: base_path,
                to_file: parse_to_file
            }

            {:next_state, {:parse, :next}, new_data,
             [{:next_event, :internal, {:parse, IO.read(device, :all)}}]}

          {:error, :enoent} ->
            file_errored =
              case file_list do
                [h | _] -> h
                _ -> nil
              end

            {:stop_and_reply, :normal,
             [
               {
                 :reply,
                 from,
                 {:error, add_error(%{data | file: file_errored}, error_msg({:enoent, path}))}
               }
             ]}
        end
    end
  end

  # we are in an invalid parsing state, abort and return an error with the current
  # state and data
  def handle_event(:internal, {:parse, _}, _state, %{valid?: false, answer_to: from} = data),
    do: {:stop_and_reply, :normal, [{:reply, from, {:error, data}}]}

  # we have reached the end of the binary, there's nothing else to do except answer
  # the caller, if we're in something else than {:parse, :next} it's an error
  def handle_event(:internal, {:parse, []}, state, %{answer_to: from} = data) do
    case state do
      {:parse, :next} ->
        reply_finish(data)

      _ ->
        {:stop_and_reply, :normal,
         [
           {:reply, from, {:error, add_error(data)}}
         ]}
    end
  end

  # handle no_count null byte
  def handle_event(:internal, {:parse, [?$, 0, ?$, 0, ?$ | rem]}, _state, data),
    do: {:keep_state, inc_no_count(data, -1), [{:next_event, :internal, {:parse, rem}}]}

  # handle comments
  [~c"//", ~c"/*"]
  |> Enum.each(fn chars ->
    def handle_event(
          :internal,
          {:parse, unquote(chars) ++ rem},
          state,
          data
        )
        when not (is_tuple(state) and elem(state, 0) == :find_terminator) do
      new_data =
        data
        |> inc_col(2)
        |> open_current(:comment)

      case CSSEx.Helpers.Comments.parse(rem, new_data, unquote(chars)) do
        {:ok, {new_data, new_rem}} ->
          {:keep_state, close_current(new_data), [{:next_event, :internal, {:parse, new_rem}}]}

        {:error, new_data} ->
          {:keep_state, new_data, [{:next_event, :internal, {:parse, rem}}]}
      end
    end
  end)

  # Handle a function call, this is on top of everything as when outside EEx blocks,
  # meaning normal parsing, it should be replaced by the return value of the function
  # we parse from @fn:: ... to the end of the declaration ")", we do it in the Function
  # module as it has its own parsing nuances
  def handle_event(
        :internal,
        {:parse, ~c"@fn::" ++ rem},
        _state,
        data
      ) do
    new_data =
      data
      |> open_current(:function_call)
      |> inc_col(5)

    case CSSEx.Helpers.Function.parse_call(new_data, rem) do
      {:ok, {new_data_2, new_rem}} ->
        new_data_3 =
          new_data_2
          |> close_current()

        {:keep_state, new_data_3, [{:next_event, :internal, {:parse, new_rem}}]}

      {:error, %{valid?: false} = error_data} ->
        {:keep_state, error_data, [{:next_event, :internal, {:parse, rem}}]}
    end
  end

  # Handle an @expandable declaration, this is on top of everything as it's only allowed on top level and should be handled specifically
  def handle_event(
        :internal,
        {:parse, ~c"@expandable" ++ rem},
        {:parse, :next},
        %{current_chain: []} = data
      ) do
    new_data =
      data
      |> open_current(:expandable)
      |> inc_col(11)

    case CSSEx.Helpers.Expandable.parse(rem, new_data) do
      {:ok, {new_data_2, new_rem}} ->
        {:keep_state, reset_current(new_data_2), [{:next_event, :internal, {:parse, new_rem}}]}

      {:error, error} ->
        {:keep_state, add_error(new_data, error_msg(error)),
         [{:next_event, :internal, {:parse, rem}}]}
    end
  end

  def handle_event(
        :internal,
        {:parse, ~c"@expandable" ++ rem},
        state,
        data
      ) do
    new_data = add_error(data, error_msg({:expandable, state, data}))
    {:keep_state, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  # Handle an @apply declaration
  def handle_event(
        :internal,
        {:parse, ~c"@apply" ++ rem},
        {:parse, :next},
        data
      ) do
    new_data =
      data
      |> open_current(:apply)
      |> inc_col(6)

    case CSSEx.Helpers.Expandable.make_apply(rem, new_data) do
      {:ok, new_rem} ->
        new_data_2 =
          new_data
          |> close_current()
          |> inc_no_count(1)
          |> reset_current()

        {:keep_state, new_data_2, [{:next_event, :internal, {:parse, new_rem}}]}

      {:error, error} ->
        {:keep_state, add_error(new_data, error_msg(error)),
         [{:next_event, :internal, {:parse, rem}}]}
    end
  end

  Enum.each([{?], ?[}, {?), ?(}, {?", ?"}, {?', ?'}], fn {char, opening} ->
    def handle_event(
          :internal,
          {:parse, [unquote(char) | rem]},
          {:find_terminator, unquote(opening), [], state},
          %{search_acc: acc} = data
        ) do
      new_data =
        %{data | search_acc: [acc, unquote(char)]}
        |> close_current()
        |> inc_col(1)

      {:next_state, {:after_terminator, state}, new_data,
       [{:next_event, :internal, {:terminate, rem}}]}
    end

    def handle_event(
          :internal,
          {:parse, [unquote(char) | rem]},
          {:find_terminator, unquote(opening), [next_search | old_search], state},
          %{search_acc: acc} = data
        ) do
      new_data =
        %{data | search_acc: [acc, unquote(char)]}
        |> close_current()
        |> inc_col(1)

      {:next_state, {:find_terminator, next_search, old_search, state}, new_data,
       [{:next_event, :internal, {:parse, rem}}]}
    end
  end)

  Enum.each([?[, ?(, ?", ?'], fn char ->
    def handle_event(
          :internal,
          {:parse, [unquote(char) | rem]},
          state,
          %{search_acc: acc} = data
        ) do
      new_data =
        %{data | search_acc: [acc, unquote(char)]}
        |> inc_col(1)
        |> open_current({:terminator, unquote(char)})

      case state do
        {:find_terminator, prev_search, old_search, old_state} ->
          {:next_state, {:find_terminator, unquote(char), [prev_search | old_search], old_state},
           new_data, [{:next_event, :internal, {:parse, rem}}]}

        _ ->
          {:next_state, {:find_terminator, unquote(char), [], state}, new_data,
           [{:next_event, :internal, {:parse, rem}}]}
      end
    end
  end)

  Enum.each(@line_terminators, fn char ->
    def handle_event(
          :internal,
          {:parse, [unquote(char) | rem]},
          {:find_terminator, _, _, _},
          %{search_acc: acc} = data
        ) do
      new_data =
        %{data | search_acc: [acc, unquote(char)]}
        |> inc_line()

      {:keep_state, new_data, [{:next_event, :internal, {:parse, rem}}]}
    end
  end)

  def handle_event(
        :internal,
        {:parse, [char | rem]},
        {:find_terminator, _, _, _},
        %{search_acc: acc} = data
      ) do
    new_data =
      %{data | search_acc: [acc, char]}
      |> inc_col(1)

    {:keep_state, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(
        :internal,
        {:parse, ~c"@fn" ++ rem},
        {:parse, :next},
        data
      ) do
    new_data =
      data
      |> open_current(:function)
      |> inc_col(3)

    {:next_state, {:parse, :value, :current_function}, new_data,
     [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(
        :internal,
        {:parse, ~c"@include" ++ rem},
        {:parse, :next},
        data
      ) do
    new_data =
      data
      |> open_current(:include)
      |> inc_col(8)

    {:next_state, {:parse, :value, :include}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(
        :internal,
        {:parse, ~c"@import" ++ rem},
        {:parse, :next},
        data
      ) do
    new_data =
      data
      |> open_current(:import)
      |> inc_col(7)

    {:next_state, {:parse, :value, :import}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(
        :internal,
        {:parse, ~c"@charset" ++ rem},
        {:parse, :next},
        data
      ) do
    new_data =
      data
      |> open_current(:charset)
      |> inc_col(8)

    {:next_state, {:parse, :value, :charset}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(
        :internal,
        {:parse, ~c"@media" ++ rem},
        {:parse, :next},
        data
      ) do
    new_data =
      data
      |> open_current(:media)
      |> inc_col(6)

    {:next_state, {:parse, :value, :media}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(
        :internal,
        {:parse, ~c"@supports" ++ rem},
        {:parse, :next},
        data
      ) do
    new_data =
      data
      |> open_current(:supports)
      |> inc_col(6)

    {:next_state, {:parse, :value, :supports}, new_data,
     [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(
        :internal,
        {:parse, ~c"@page" ++ rem},
        {:parse, :next},
        data
      ) do
    new_data =
      data
      |> open_current(:page)
      |> inc_col(6)

    {:next_state, {:parse, :value, :page}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(
        :internal,
        {:parse, ~c"@keyframes" ++ rem},
        {:parse, :next},
        data
      ) do
    new_data =
      data
      |> open_current(:keyframes)
      |> inc_col(10)

    {:next_state, {:parse, :value, :keyframes}, new_data,
     [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(
        :internal,
        {:parse, ~c"@font-face" ++ rem},
        {:parse, :next},
        %{current_chain: [], font_face: false, font_face_count: ffc} = data
      ) do
    new_data =
      %{data | font_face: true, font_face_count: ffc + 1}
      |> open_current(:fontface)
      |> inc_col(10)
      |> first_rule()

    {:next_state, {:parse, :current_key}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  # we have reached a closing bracket } while accumulating a font-face, reset the
  # font-face toggle and resume normal parsing
  def handle_event(
        :internal,
        {:parse, [125 | rem]},
        {:parse, :next},
        %{font_face: true} = data
      ) do
    new_data =
      %{data | font_face: false}
      |> close_current()
      |> inc_col(1)

    {:keep_state, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  # we have reached a closing bracket } which means we should move back up in the
  # chain ditching our last value in it, and start searching for the next token
  def handle_event(
        :internal,
        {:parse, [125 | rem]},
        {:parse, :next},
        %{current_chain: [_ | _]} = data
      ) do
    new_data =
      data
      |> remove_last_from_chain()
      |> close_current()
      |> inc_col()

    {:keep_state, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  # we reached a closing bracket without being inside a block and at the top level,
  # error out
  def handle_event(
        :internal,
        {:parse, [125 | _]},
        {:parse, :next},
        %{answer_to: from, current_chain: [], level: 0} = data
      ) do
    new_data = add_error(data, error_msg({:mismatched, "}"}))
    {:stop_and_reply, :normal, [{:reply, from, {:error, new_data}}]}
  end

  # we reached a closing bracket without being inside a block in an inner level, inc
  # the col and return to original the current data and the remaining text
  def handle_event(
        :internal,
        {:parse, [125 | rem]},
        {:parse, :next},
        %{answer_to: from, current_chain: []} = data
      ),
      do: {:stop_and_reply, :normal, [{:reply, from, {:finished, {inc_col(data), rem}}}]}

  # we reached a closing bracket when searching for a key/attribute ditch whatever we
  # have and add a warning
  def handle_event(
        :internal,
        {:parse, [125 | rem]},
        {:parse, :current_var},
        data
      ) do
    new_data =
      data
      |> add_warning(warning_msg(:incomplete_declaration))
      |> close_current()
      |> reset_current()
      |> inc_col()

    {:next_state, {:parse, :next}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  # we reached a closing bracket } while we were searching for a value to an attribute
  # inside a previously opened block (we have a current chain), meaning there's no ;
  # char, this is allowed on the last attr:val of a block, so we will do as if it was
  # there and just reparse adding the ; to the beggining
  def handle_event(
        :internal,
        {:parse, [125 | _] = full},
        {:parse, :current_key},
        %{current_chain: [_ | _]}
      ) do
    {:keep_state_and_data, [{:next_event, :internal, {:parse, [?; | full]}}]}
  end

  def handle_event(
        :internal,
        {:parse, [125 | _] = full},
        {:parse, :current_key},
        %{split_chain: [_ | _]}
      ) do
    {:keep_state_and_data, [{:next_event, :internal, {:parse, [?; | full]}}]}
  end

  # we reached an eex opening tag, because it requires dedicated handling and parsing
  # we move to a different parse step
  def handle_event(
        :internal,
        {:parse, ~c"<%" ++ _ = full},
        _state,
        data
      ) do
    case CSSEx.Helpers.EEX.parse(full, data) do
      {:error, new_data} ->
        {:keep_state, add_error(new_data), [{:next_event, :internal, {:parse, []}}]}

      {new_rem, %__MODULE__{} = new_data} ->
        {:keep_state, new_data, [{:next_event, :internal, {:parse, new_rem}}]}
    end
  end

  # we reached a new line char, reset the col, inc the line and continue
  Enum.each(@line_terminators, fn char ->
    #  if we are parsing a var this is an error though
    def handle_event(
          :internal,
          {:parse, [unquote(char) | rem]},
          state,
          data
        )
        when state == {:parse, :current_var} or state == {:parse, :value, :current_var} do
      {:keep_state, add_error(inc_col(data)), [{:next_event, :internal, {:parse, rem}}]}
    end

    def handle_event(
          :internal,
          {:parse, [unquote(char) | rem]},
          _state,
          data
        ),
        do: {:keep_state, inc_line(data), [{:next_event, :internal, {:parse, rem}}]}
  end)

  Enum.each(@white_space, fn char ->
    # we reached a white-space char while searching for the next token, inc the column,
    # keep searching
    def handle_event(
          :internal,
          {:parse, [unquote(char) | rem]},
          {:parse, :next},
          data
        ),
        do: {:keep_state, inc_col(data), [{:next_event, :internal, {:parse, rem}}]}

    # we reached a white-space while building a variable, move to parse the value now
    def handle_event(
          :internal,
          {:parse, [unquote(char) | rem]},
          {:parse, :current_var},
          data
        ),
        do:
          {:next_state, {:parse, :value, :current_var}, inc_col(data),
           [{:next_event, :internal, {:parse, rem}}]}

    # we reached a white-space while building an assign, move to parse the value
    # now, the assign is special because it can be any term and needs to be
    # validated by compiling it so we do it in a special parse step
    def handle_event(
          :internal,
          {:parse, [unquote(char) | rem]},
          {:parse, :current_assign},
          data
        ) do
      {new_rem, new_data} = CSSEx.Helpers.Assigns.parse(rem, inc_col(data))

      {:next_state, {:parse, :next}, reset_current(new_data),
       [{:next_event, :internal, {:parse, new_rem}}]}
    end

    # we reached a white-space while building a media query or keyframe name, include
    # the whitespace in the value
    def handle_event(
          :internal,
          {:parse, [unquote(char) | rem]},
          {:parse, :value, type},
          %{current_value: cval} = data
        )
        when type in [:media, :keyframes, :import, :include, :page, :supports],
        do: {
          :keep_state,
          %{data | current_value: [cval, unquote(char)]},
          [{:next_event, :internal, {:parse, rem}}]
        }

    # we reached a white-space while building a value parsing - ditching the
    # white-space depends on if we're in the middle of a value or in the beginning
    # and the type of key we're searching
    def handle_event(
          :internal,
          {:parse, [unquote(char) | rem]},
          {:parse, :value, type},
          data
        )
        when type not in [:current_var] do
      # we'll always inc the column counter no matter what
      new_data = inc_col(data)

      case Map.fetch!(data, type) do
        [] ->
          {:keep_state, new_data, [{:next_event, :internal, {:parse, rem}}]}

        nil when type in [:charset] ->
          {:keep_state, new_data, [{:next_event, :internal, {:parse, rem}}]}

        val ->
          new_data_2 = Map.put(new_data, type, [val, unquote(char)])

          {:keep_state, new_data_2, [{:next_event, :internal, {:parse, rem}}]}
      end
    end
  end)

  # We found an assign assigment when searching for the next token, prepare for
  # parsing it
  def handle_event(
        :internal,
        {:parse, ~c"@!" ++ rem},
        {:parse, :next},
        data
      ) do
    new_data =
      data
      |> set_scope(:global)
      |> open_current(:assign)
      |> inc_col(2)

    {:next_state, {:parse, :current_assign}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(
        :internal,
        {:parse, ~c"@()" ++ rem},
        {:parse, :next},
        data
      ) do
    new_data =
      data
      |> set_scope(:local)
      |> open_current(:assign)
      |> inc_col(3)

    {:next_state, {:parse, :current_assign}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(
        :internal,
        {:parse, ~c"@?" ++ rem},
        {:parse, :next},
        data
      ) do
    new_data =
      data
      |> set_scope(:conditional)
      |> open_current(:assign)
      |> inc_col(3)

    {:next_state, {:parse, :current_assign}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  # We found a var assignment when searching for the next token, prepare for parsing it
  def handle_event(
        :internal,
        {:parse, ~c"$!" ++ rem},
        {:parse, :next},
        data
      ) do
    new_data =
      data
      |> set_scope(:global)
      |> open_current(:variable)
      |> inc_col(2)

    {:next_state, {:parse, :current_var}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(
        :internal,
        {:parse, ~c"$*!" ++ rem},
        {:parse, :next},
        data
      ) do
    new_data =
      data
      |> set_scope(:global)
      |> open_current(:variable)
      |> set_add_var()
      |> inc_col(3)

    {:next_state, {:parse, :current_var}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(
        :internal,
        {:parse, ~c"$()" ++ rem},
        {:parse, :next},
        data
      ) do
    new_data =
      data
      |> set_scope(:local)
      |> open_current(:variable)
      |> inc_col(3)

    {:next_state, {:parse, :current_var}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(
        :internal,
        {:parse, ~c"$*()" ++ rem},
        {:parse, :next},
        data
      ) do
    new_data =
      data
      |> set_scope(:local)
      |> open_current(:variable)
      |> set_add_var()
      |> inc_col(4)

    {:next_state, {:parse, :current_var}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(
        :internal,
        {:parse, ~c"$?" ++ rem},
        {:parse, :next},
        data
      ) do
    new_data =
      data
      |> set_scope(:conditional)
      |> open_current(:variable)
      |> inc_col(2)

    {:next_state, {:parse, :current_var}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(
        :internal,
        {:parse, ~c"$*?" ++ rem},
        {:parse, :next},
        data
      ) do
    new_data =
      data
      |> set_scope(:conditional)
      |> open_current(:variable)
      |> set_add_var()
      |> inc_col(3)

    {:next_state, {:parse, :current_var}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  # we found the selector end char { opening a css inner context while searching for
  # the :current_key, which means that this is a selector that we were parsing, add it
  # and start searching for the next token (we use 123 because ?{ borks the
  # text-editor identation)
  def handle_event(
        :internal,
        {:parse, [123 | rem]},
        {:parse, :current_key},
        data
      ) do
    ## TODO validate it's a valid selector, error if not

    new_data =
      data
      |> add_current_selector()
      |> close_current()
      |> open_current(:selector)
      |> reset_current()
      |> inc_col()
      |> first_rule()

    {:next_state, {:parse, :next}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  # we found the selector end char { opening a css inner context while parsing the
  # @media attributes, we start a subsequent gen_statem to continue which will
  # accumulate itself and answer back to this one where it will merge what was found
  # there
  def handle_event(
        :internal,
        {:parse, [123 | rem]},
        {:parse, :value, type},
        data
      )
      when type in [:media, :page, :supports] do
    inner_data =
      %{data | order_map: %{c: 0}}
      |> create_data_for_inner(false, nil)
      |> add_parent_information(data, type)

    case __MODULE__.parse(inner_data, rem) do
      {:finished, {%{column: n_col, line: n_line} = new_inner_data, new_rem}} ->
        new_data =
          %{data | line: n_line, column: n_col}
          |> add_inner_result(new_inner_data, type)
          |> close_current()
          |> reset_current()

        {:next_state, {:parse, :next}, new_data, [{:next_event, :internal, {:parse, new_rem}}]}

      ## TODO error needs to stop correctly
      error ->
        stop_with_error(data, error)
    end
  end

  # we found the selector end char { opening a css inner context while parsing the
  # @keyframes name, we'll do the parsing for those in a new parser gen_statem because
  # we can't construct the key path correctly from this level, but inside the keyframe
  # block they're in all similar to a normal css selector + block, then with the
  # result of that parser we'll put all those elements inside a single selector
  # @keyframes + animation name
  def handle_event(
        :internal,
        {:parse, [123 | rem]},
        {:parse, :value, :keyframes},
        data
      ) do
    # create a new ets table, public, so that the new started process can write to it
    inner_data = create_data_for_inner(data)

    case __MODULE__.parse(inner_data, rem) do
      {:finished, {%{column: n_col, line: n_line} = new_inner_data, new_rem}} ->
        new_data =
          %{data | line: n_line, column: n_col}
          |> add_keyframe(new_inner_data)
          |> close_current()
          |> reset_current()

        {:next_state, {:parse, :next}, new_data, [{:next_event, :internal, {:parse, new_rem}}]}

      ## TODO error needs to stop correctly
      error ->
        stop_with_error(data, error)
    end
  end

  # we found the selector end char { opening an inner content while parsing a @fn,
  # we'll do the parsing for those in a another module as it needs to evaluate the
  # parsed content and create an anonymous fun
  def handle_event(
        :internal,
        {:parse, ~c"->" ++ rem},
        {:parse, :value, :current_function},
        data
      ) do
    case CSSEx.Helpers.Function.parse(inc_col(data, 2), rem) do
      {:ok, {new_data, new_rem}} ->
        new_data_2 =
          new_data
          |> close_current()
          |> reset_current()

        {:next_state, {:parse, :next}, new_data_2, [{:next_event, :internal, {:parse, new_rem}}]}

      error ->
        stop_with_error(data, error)
    end
  end

  # we found a non-white-space/line-end char while searching for the next token,
  # which means it's a regular css rule start, prepare for parsing it
  def handle_event(
        :internal,
        {:parse, [char | rem]},
        {:parse, :next},
        data
      )
      when char != ?; do
    new_data =
      data
      |> Map.put(:current_key, [char])
      |> open_current(:rule)
      |> inc_col()
      |> first_rule()

    {:next_state, {:parse, :current_key}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  # we reached the termination ; char while assembling an include statement, start a
  # new parser with the current ets table
  def handle_event(
        :internal,
        {:parse, [?; | rem]},
        {:parse, :value, :include},
        %{current_value: current_key, ets: ets, file: o_file} = data
      ) do
    file_path =
      current_key
      |> IO.chardata_to_string()
      |> String.replace(~r/\"?/, "")
      |> String.trim()

    inner_data = create_data_for_inner(%{data | line: 0, column: 0}, ets)

    case __MODULE__.parse_file(inner_data, Path.dirname(o_file), file_path) do
      {:finished, %{file: file} = new_inner_data} ->
        new_data =
          data
          |> merge_inner_data(new_inner_data)
          |> close_current()
          |> reset_current()
          |> add_to_dependencies(file)
          |> merge_dependencies(new_inner_data)

        :erlang.garbage_collect()
        {:next_state, {:parse, :next}, new_data, [{:next_event, :internal, {:parse, rem}}]}

      # TODO error needs to stop correctly
      error ->
        stop_with_error(data, error)
    end
  end

  # we reached the termination ; char while assembling a variable, cleanup and add it
  # to the correct scopes
  def handle_event(
        :internal,
        {:parse, [?; | rem]},
        {:parse, :value, :current_var},
        %{current_var: current_var, current_value: current_value} = data
      ) do
    cvar = IO.chardata_to_string(current_var)
    cval = String.trim_trailing(IO.chardata_to_string(current_value))

    ## TODO add checks on var name && and value, emit warnings if invalid;

    new_data =
      data
      |> maybe_add_css_var(cvar, cval)
      |> add_to_var(cvar, cval)
      |> close_current()
      |> reset_current()
      |> inc_col()

    {:next_state, {:parse, :next}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  # we reached the termination ; char while assembling an attribute, cleanup and add
  # it to the correct ets slot
  def handle_event(
        :internal,
        {:parse, [?; | rem]},
        {:parse, :current_key},
        %{current_key: current_key} = data
      ) do
    current_key
    |> IO.chardata_to_string()
    |> String.split(":", trim: true)
    |> case do
      [ckey, cval] ->
        ## TODO add checks on attribute & value, emit warnings if invalid;

        new_data =
          data
          |> add_to_attributes(ckey, cval)
          |> close_current()
          |> reset_current()
          |> inc_col()
          |> first_rule()

        {:next_state, {:parse, :next}, new_data, [{:next_event, :internal, {:parse, rem}}]}

      ## This means we had more than `key: val` which is either an error, or a value that can contain `:`, as is the case with `url()` usage, so we check if `url()` is part of the value and if it is we assume it's ok, otherwise error
      [ckey | key_rem] ->
        cval = Enum.join(key_rem, ":")

        case String.match?(cval, ~r/url\(.+\)/) do
          true ->
            new_data =
              data
              |> add_to_attributes(ckey, cval)
              |> close_current()
              |> reset_current()
              |> inc_col()
              |> first_rule()

            {:next_state, {:parse, :next}, new_data, [{:next_event, :internal, {:parse, rem}}]}

          false ->
            # this is probably a misplaced token we should error out
            error_msg = error_msg({:unexpected, IO.iodata_to_binary([ckey, cval])})

            {:next_state, {:parse, :next}, add_error(data, error_msg),
             [{:next_event, :internal, {:parse, rem}}]}
        end
    end
  end

  def handle_event(
        :internal,
        {:parse, [?; | rem]},
        {:parse, :value, :current_value},
        %{current_key: current_key, current_value: current_value} = data
      ) do
    ckey = IO.chardata_to_string(current_key)
    cval = String.trim_trailing(IO.chardata_to_string(current_value))

    ## TODO add checks on attribute & value, emit warnings if invalid;

    new_data =
      data
      |> add_to_attributes(ckey, cval)
      |> close_current()
      |> reset_current()
      |> inc_col()
      |> first_rule()

    {:next_state, {:parse, :next}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(:internal, {:parse, [?; | rem]}, {:parse, :next}, _),
    do: {:keep_state_and_data, [{:next_event, :internal, {:parse, rem}}]}

  def handle_event(
        :internal,
        {:terminate, rem},
        {:after_terminator, {:parse, type} = next},
        %{search_acc: acc} = data
      ) do
    new_data =
      case type != :next do
        true -> Map.put(data, type, [Map.fetch!(data, type), acc])
        _ -> data
      end

    {:next_state, next, %{new_data | search_acc: []}, [{:next_event, :internal, {:parse, rem}}]}
  end

  def handle_event(
        :internal,
        {:terminate, rem},
        {:after_terminator, {:parse, :value, _type} = next},
        %{search_acc: acc, current_value: cval} = data
      ) do
    new_data = %{data | search_acc: [], current_value: [cval, acc]}

    {:next_state, next, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  # we're accumulating on something, add the value to that type we're accumulating
  def handle_event(
        :internal,
        {:parse, [char | rem]},
        {:parse, type},
        data
      ),
      do:
        {:keep_state, Map.put(data, type, [Map.fetch!(data, type), char]),
         [{:next_event, :internal, {:parse, rem}}]}

  # we reached the termination ; char while assembling a special attribute,
  # @charset, cleanup and verify it's valid to add
  def handle_event(
        :internal,
        {:parse, [?; | rem]},
        {:parse, :value, :charset},
        data
      ) do
    new_data =
      data
      |> validate_charset()
      |> close_current()
      |> reset_current()
      |> inc_col()

    {:next_state, {:parse, :next}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  # we reached the termination ; char while assembling a special attribute, @import,
  # cleanup and verify it's valid to add
  def handle_event(
        :internal,
        {:parse, [?; | rem]},
        {:parse, :value, :import},
        data
      ) do
    new_data =
      data
      |> validate_import()
      |> close_current()
      |> reset_current()
      |> inc_col()

    {:next_state, {:parse, :next}, new_data, [{:next_event, :internal, {:parse, rem}}]}
  end

  # a valid char while we're accumulating for a value, add it and continue
  def handle_event(
        :internal,
        {:parse, [char | rem]},
        {:parse, :value, _type},
        %{current_value: cval} = data
      ),
      do:
        {:keep_state, %{inc_col(data) | current_value: [cval, char]},
         [{:next_event, :internal, {:parse, rem}}]}

  @doc false
  # set the scope for whatever we're doing, scopes can only be set by when
  # parsing variables or assigns if it's not nil there's a problem
  def set_scope(%{current_scope: nil} = data, scope), do: %{data | current_scope: scope}

  @doc false
  # set var, it should be always false when this is called for the same reasons as
  # set_scope
  def set_add_var(%{current_add_var: false} = data), do: %{data | current_add_var: true}

  @doc false
  # add the variable to the global and local scopes
  def add_to_var(
        %{current_scope: :global, scope: scope, local_scope: local_scope} = data,
        key,
        val
      ),
      do: %{
        data
        | scope: Map.put(scope, key, val),
          local_scope: Map.put(local_scope, key, val)
      }

  # add the variable only to the local scope
  def add_to_var(
        %{current_scope: :local, local_scope: local_scope} = data,
        key,
        val
      ),
      do: %{data | local_scope: Map.put(local_scope, key, val)}

  # conditionally add variable to the local scope if it's not in scope
  def add_to_var(
        %{current_scope: :conditional, local_scope: local_scope, scope: scope} = data,
        key,
        val
      ) do
    case Map.get(scope, key) do
      nil ->
        case Map.get(local_scope, key) do
          nil -> %{data | scope: Map.put(scope, key, val)}
          _ -> data
        end

      _ ->
        data
    end
  end

  @doc false
  # add to font-face ETS table when dealing with a font-face block
  def add_to_attributes(
        %{font_face: true, ets_fontface: ets, font_face_count: ffc} = data,
        key,
        val
      ) do
    case maybe_replace_val(val, data) do
      {:ok, new_val} ->
        new_val = String.trim(new_val)

        case HShared.valid_attribute_kv?(key, new_val) do
          true ->
            case :ets.lookup(ets, ffc) do
              [{_, existing}] -> :ets.insert(ets, {ffc, Map.put(existing, key, new_val)})
              [] -> :ets.insert(ets, {ffc, Map.put(%{}, key, new_val)})
            end

            data

          false ->
            add_error(data, error_msg({:invalid_declaration, key, new_val}))
        end

      {:error, {:not_declared, _, _} = error} ->
        add_error(data, error_msg(error))
    end
  end

  # add attribute to the ETS table
  def add_to_attributes(data, key, val) do
    case maybe_replace_val(val, data) do
      {:ok, new_val} ->
        new_val = String.trim(new_val)

        case HShared.valid_attribute_kv?(key, new_val) do
          true ->
            Output.write_element(data, key, new_val)

          false ->
            add_error(data, error_msg({:invalid_declaration, key, new_val}))
        end

      {:error, {:not_declared, _, _} = error} ->
        add_error(data, error_msg(error))
    end
  end

  @doc false
  # add a special case for when parsing a font-face
  def add_current_selector(%{font_face: true} = data), do: data

  # add the current_selector to the current_chain
  def add_current_selector(%{current_key: ck} = data) do
    current_selector = String.trim(IO.chardata_to_string(ck))

    case maybe_replace_val(current_selector, data) do
      {:ok, replaced_selector} ->
        HShared.add_selector_to_chain(data, replaced_selector)

      {:error, error} ->
        add_error(data, error_msg(error))
    end
  end

  @doc false
  # reset the accumulators and scope
  def reset_current(data),
    do: %{
      data
      | current_key: [],
        current_value: [],
        current_var: [],
        current_assign: [],
        current_scope: nil,
        current_add_var: false,
        current_function: []
    }

  @doc false
  # TODO when tightening the scopes this has to take into account creating a variable in a given selector, right now it will crash when variables that create css vars (@*) are declared inside elements
  def maybe_add_css_var(%{current_add_var: false} = data, _, _), do: data

  def maybe_add_css_var(
        %{
          current_add_var: true,
          current_scope: current_scope,
          local_scope: local_scope,
          scope: scope,
          current_chain: current_chain,
          split_chain: split_chain
        } = data,
        key,
        val
      ) do
    new_val =
      case current_scope do
        :conditional -> Map.get(local_scope, key, Map.get(scope, key, false)) || val
        _ -> val
      end

    new_cc =
      case current_chain do
        [] -> ":root"
        _ -> split_chain
      end

    case maybe_replace_val(new_val, data) do
      {:ok, new_val_2} ->
        add_css_var(data, new_cc, key, new_val_2)

      {:error, {:not_declared, _, _} = error} ->
        add_error(data, error_msg(error))
    end
  end

  @doc false
  def add_css_var(%{ets: ets, order_map: %{c: c} = om} = data, cc, key, val) do
    new_om =
      case :ets.lookup(ets, cc) do
        [{_, existing}] ->
          :ets.insert(ets, {cc, Map.put(existing, "--#{key}", val)})
          om

        [] ->
          :ets.insert(ets, {cc, Map.put(%{}, "--#{key}", val)})

          om
          |> Map.put(:c, c + 1)
          |> Map.put(cc, c)
          |> Map.put(c, cc)
      end

    %{data | order_map: new_om}
  end

  @doc false
  def validate_charset(%{current_value: charset, charset: nil, first_rule: true} = data) do
    new_charset =
      charset
      |> IO.chardata_to_string()
      |> String.trim(~s("))

    %{data | charset: ~s("#{new_charset}")}
  end

  def validate_charset(%{charset: charset, first_rule: first_rule} = data) do
    case charset do
      nil -> data
      _ -> add_warning(data, warning_msg(:single_charset))
    end
    |> case do
      new_data ->
        case first_rule do
          true ->
            new_data

          _ ->
            add_warning(data, warning_msg(:charset_position))
        end
    end
    |> reset_current()
  end

  @doc false
  def validate_import(
        %{current_value: current_value, first_rule: true, imports: imports, pretty_print?: pp?} =
          data
      ) do
    {:ok, cval} =
      current_value
      |> IO.chardata_to_string()
      |> String.trim()
      |> maybe_replace_val(data)

    no_quotes = String.trim(cval, "\"")

    terminator =
      case pp? do
        true -> ";\n"
        _ -> ";"
      end

    %{data | imports: [imports | ["@import", " ", cval, terminator]]}
    |> add_to_dependencies(no_quotes)
  end

  def validate_import(%{first_rule: false} = data),
    do: add_warning(data, warning_msg(:import_declaration))

  @doc false
  def first_rule(%{first_rule: false} = data), do: data
  def first_rule(data), do: %{data | first_rule: false}

  @doc false
  # reply back according to the level
  def reply_finish(%{answer_to: from, level: 0} = data) do
    reply =
      case Output.do_finish(data) do
        {:ok, %Output{acc: final_css}} ->
          {:ok, data, final_css}

        {:error, %Output{data: data}} ->
          {:error, data}
      end

    {
      :stop_and_reply,
      :normal,
      [{:reply, from, reply}]
    }
  end

  def reply_finish(%{answer_to: from} = data) do
    {
      :stop_and_reply,
      :normal,
      [{:reply, from, {:finished, data}}]
    }
  end

  @doc false
  def add_inner_result(
        %{current_value: current_value} = data,
        %{ets: inner_ets, order_map: om} = inner_data,
        type
      )
      when type in [:media, :page, :supports] do
    selector = "@#{type}"
    parent_selector_key = String.to_existing_atom("#{type}_parent")
    parent_selector = Map.fetch!(data, parent_selector_key)

    inner_map_acc = Map.fetch!(inner_data, type)

    parsed =
      current_value
      |> IO.chardata_to_string()
      |> String.trim()
      |> to_charlist()

    {parsed_2, data} = CSSEx.Helpers.AtParser.parse(parsed, data, type)

    case maybe_replace_val(parsed_2, data) do
      {:ok, cval} ->
        selector_query =
          [selector, parent_selector, cval]
          |> Enum.filter(fn element -> String.length(element) > 0 end)
          |> Enum.join(" ")

        new_type_acc =
          case Map.get(inner_map_acc, selector_query) do
            nil ->
              Map.put(inner_map_acc, selector_query, {inner_ets, om})

            {original_ets, existing_om} ->
              new_om = Output.transfer_mergeable(inner_ets, original_ets, existing_om)
              :ets.delete(inner_ets)
              Map.put(inner_map_acc, selector_query, {original_ets, new_om})
          end

        Map.put(data, type, new_type_acc)

      {:error, {:not_declared, _, _} = error} ->
        add_error(data, error_msg(error))
    end
  end

  @doc false
  def add_keyframe(
        %{current_value: current_value} = data,
        %{ets: inner_ets} = _inner_data
      ) do
    parsed = IO.chardata_to_string(current_value)

    case maybe_replace_val(parsed, data) do
      {:ok, cval} ->
        full_path = "@keyframes #{String.trim(cval)}"
        new_data = Output.write_keyframe(data, full_path, inner_ets)
        :ets.delete(inner_ets)
        new_data

      {:error, {:not_declared, _, _} = error} ->
        add_error(data, error_msg(error))
    end
  end

  @doc false
  def create_data_for_inner(
        %{
          line: line,
          column: col,
          level: level,
          ets_fontface: etsff,
          ets_keyframes: etskf,
          font_face_count: ffc,
          assigns: assigns,
          local_assigns: l_assigns,
          scope: scope,
          local_scope: l_scope,
          functions: functions,
          media: media,
          media_parent: media_parent,
          source_pid: source_pid,
          order_map: order_map,
          keyframes_order_map: keyframe_order_map,
          no_count: no_count,
          expandables: expandables,
          expandables_order_map: eom,
          file_list: file_list,
          pretty_print?: pp?
        } = data,
        ets \\ nil,
        prefix \\ nil
      ) do
    inner_ets =
      if(ets, do: ets, else: :ets.new(:inner, [:public, {:heir, source_pid, "INNER_ETS"}]))

    inner_prefix =
      if(prefix,
        do: prefix,
        else: if(prefix == false, do: nil, else: CSSEx.Helpers.Shared.generate_prefix(data))
      )

    inner_assigns = Map.merge(assigns, l_assigns)
    inner_scope = Map.merge(scope, l_scope)

    inner_split_chain = [if(inner_prefix, do: inner_prefix, else: [])]

    %__MODULE__{
      ets: inner_ets,
      line: line,
      column: col,
      no_count: no_count,
      level: level + 1,
      prefix: inner_prefix,
      ets_fontface: etsff,
      ets_keyframes: etskf,
      font_face_count: ffc,
      local_assigns: inner_assigns,
      local_scope: inner_scope,
      functions: functions,
      split_chain: inner_split_chain,
      media: media,
      source_pid: source_pid,
      media_parent: media_parent,
      order_map: order_map,
      keyframes_order_map: keyframe_order_map,
      expandables: expandables,
      expandables_order_map: eom,
      file_list: file_list,
      pretty_print?: pp?
    }
  end

  @doc false
  def add_parent_information(
        data,
        %{current_value: current_value} = parent_data,
        type
      )
      when type in [:media, :supports, :page] do
    parent_key = String.to_existing_atom("#{type}_parent")
    parent_current = Map.fetch!(parent_data, parent_key)

    {parsed, data} =
      current_value
      |> :lists.flatten()
      |> CSSEx.Helpers.AtParser.parse(data, type)

    new_media_parent =
      [
        parent_current,
        IO.chardata_to_string(parsed)
      ]
      |> Enum.map(fn element -> String.trim(element) end)
      |> Enum.join(" ")
      |> String.trim()

    Map.put(data, parent_key, new_media_parent)
  end

  @doc false
  def merge_inner_data(
        %{
          warnings: existing_warnings,
          scope: existing_scope,
          assigns: existing_assigns,
          functions: existing_functions
          # media: media
        } = data,
        %{
          warnings: warnings,
          media: media,
          scope: scope,
          assigns: assigns,
          valid?: valid?,
          font_face_count: ffc,
          error: error,
          functions: functions,
          order_map: om,
          keyframes_order_map: kom,
          expandables: expandables,
          expandables_order_map: eom
        }
      ) do
    %__MODULE__{
      data
      | valid?: valid?,
        font_face_count: ffc,
        warnings: :lists.concat([existing_warnings, warnings]),
        scope: Map.merge(existing_scope, scope),
        assigns: Map.merge(existing_assigns, assigns),
        functions: Map.merge(existing_functions, functions),
        error: error,
        media: media,
        order_map: om,
        keyframes_order_map: kom,
        expandables: expandables,
        expandables_order_map: eom
    }
  end

  @doc false
  def merge_dependencies(%{dependencies: deps} = data, %__MODULE__{dependencies: new_deps}),
    do: %{data | dependencies: Enum.concat(deps, new_deps)}

  @doc false
  def add_to_dependencies(%{dependencies: deps, file: file} = data, val) do
    new_deps =
      case not is_nil(file) and not is_nil(val) do
        true ->
          base_path = Path.dirname(file)
          final_path = CSSEx.assemble_path(val, base_path)
          [final_path | deps]

        _ ->
          deps
      end

    %{data | dependencies: new_deps}
  end

  @doc false
  def stop_with_error(%{answer_to: from}, {:error, %__MODULE__{} = invalid}),
    do: {:stop_and_reply, invalid, [{:reply, from, {:error, invalid}}]}

  def stop_with_error(%{answer_to: from} = data, {:error, error}) do
    new_data = add_error(data, error_msg(error))
    {:stop_and_reply, new_data, [{:reply, from, {:error, new_data}}]}
  end

  @doc false
  def add_error(%{current_reg: [{s_l, s_c, step} | _]} = data),
    do:
      add_error(
        %{data | current_reg: []},
        "#{error_msg({:terminator, step})} at l:#{s_l} col:#{s_c} to"
      )

  @doc false
  def add_error(%{line: l, column: c} = data, error) do
    %{data | valid?: false, error: "#{inspect(error)} :: l:#{l} c:#{c}"}
    |> finish_error()
  end

  @doc false
  def finish_error(%{file_list: file_list, error: error} = data) do
    %{
      data
      | error:
          Enum.reduce(file_list, error, fn file, acc ->
            acc <> "\n on file: " <> file
          end)
    }
  end

  @doc false
  def add_warning(%{warnings: warnings, line: l, column: c, file: f} = data, msg),
    do: %{data | warnings: ["#{msg} :: l:#{l} c:#{c} in file: #{f}" | warnings]}

  @doc false
  def open_current(%{current_reg: creg, line: l, column: c} = data, element) do
    %{data | current_reg: [{l, c, element} | creg]}
  end

  @doc false
  def close_current(%{current_reg: [_ | t]} = data), do: %{data | current_reg: t}
  def close_current(%{current_reg: [], level: level} = data) when level > 0, do: data
end
