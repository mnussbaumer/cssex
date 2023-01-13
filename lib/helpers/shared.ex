defmodule CSSEx.Helpers.Shared do
  @moduledoc false

  alias CSSEx.Helpers.Error
  @appendable_first_char CSSEx.Helpers.SelectorChars.appendable_first_char()
  @line_terminators CSSEx.Helpers.LineTerminators.code_points()

  # increment the column token count
  def inc_col(data, amount \\ 1)

  def inc_col(%{column: column, no_count: 0} = data, amount),
    do: %{data | column: column + amount}

  def inc_col(data, _), do: data

  # increment the line and reset the column
  def inc_line(data, amount \\ 1)

  def inc_line(%{line: line, no_count: 0} = data, amount),
    do: %{data | column: 0, line: line + amount}

  def inc_line(data, _), do: data

  def inc_no_count(%{no_count: no_count} = data, amount \\ 1) do
    new_count =
      case no_count + amount do
        n when n >= 0 -> n
        _ -> 0
      end

    %{data | no_count: new_count}
  end

  def generate_prefix(%{current_chain: cc, prefix: nil}), do: cc
  def generate_prefix(%{current_chain: cc, prefix: prefix}), do: prefix ++ cc

  # we only have one element but we do have a prefix, set the split chain to the prefix and reset the current_chain
  def remove_last_from_chain(%{current_chain: [_], prefix: prefix} = data)
      when not is_nil(prefix),
      do: %{data | current_chain: [], split_chain: Enum.join(prefix, ",")}

  # we only have one element so reset both chains
  def remove_last_from_chain(%{current_chain: [_]} = data),
    do: %{data | current_chain: [], split_chain: []}

  # we have more than one
  def remove_last_from_chain(%{current_chain: [_ | _] = chain, prefix: prefix} = data) do
    [_ | new_chain] = :lists.reverse(chain)

    new_chain_for_merge =
      case prefix do
        nil -> :lists.reverse(new_chain)
        _ -> prefix ++ :lists.reverse(new_chain)
      end

    case split_chains(new_chain_for_merge) do
      [_ | _] = splitted ->
        %{data | current_chain: :lists.reverse(new_chain), split_chain: merge_split(splitted)}

      {:error, error} ->
        CSSEx.Parser.add_error(data, Error.error_msg(error))
    end
  end

  def add_selector_to_chain(%{current_chain: cc, prefix: prefix} = data, selector) do
    new_chain = [selector | :lists.reverse(cc)] |> :lists.reverse()

    new_split =
      case new_chain do
        [_] when is_nil(prefix) -> [new_chain]
        _ when is_nil(prefix) -> split_chains(new_chain)
        _ -> split_chains(prefix ++ new_chain)
      end

    case new_split do
      [_ | _] ->
        %{data | current_chain: new_chain, split_chain: merge_split(new_split)}

      {:error, error} ->
        CSSEx.Parser.add_error(data, Error.error_msg(error))
    end
  end

  def merge_split(split_chain) do
    split_chain
    |> Enum.map(fn chain -> Enum.join(chain, " ") end)
    |> Enum.join(",")
  end

  def ampersand_join(initial), do: ampersand_join(initial, [])

  def ampersand_join([<<"&", rem::binary>> | _], []),
    do: throw({:error, {:invalid_parent_concat, rem}})

  def ampersand_join([head, <<"&", rem::binary>> | t], acc) do
    {new_head, joint} = check_head(head)

    case is_trail_concat(rem) do
      true ->
        ampersand_join([new_head <> rem <> joint | t], acc)

      false ->
        case is_lead_concat(new_head) do
          true ->
            ampersand_join([rem <> new_head <> joint | t], acc)

          false ->
            throw({:error, {:invalid_component_concat, rem, head}})
        end
    end
  end

  def ampersand_join([head | t], acc) do
    case Regex.split(~r/.?(?<amper>\(?&\)?).?$/, head,
           include_captures: true,
           on: [:amper],
           trim: true
         ) do
      [_] ->
        ampersand_join(t, [acc | [head]])

      [parent, "&"] ->
        case :lists.reverse(acc) do
          [previous | rem] ->
            new_acc = :lists.reverse([previous, String.trim(parent) | rem])
            ampersand_join(t, new_acc)

          _ ->
            throw({:error, {:invalid_parent_concat, parent}})
        end

      [pseudo, "(&)"] ->
        case :lists.reverse(acc) do
          [previous | rem] ->
            new_acc = :lists.reverse(["#{pseudo}(#{previous})" | rem])
            ampersand_join(t, new_acc)

          _ ->
            throw({:error, {:invalid_parent_concat, pseudo}})
        end
    end
  end

  def ampersand_join([], acc), do: :lists.flatten(acc)

  def check_head(head) do
    case Regex.split(~r/.?(?<amper>\(?&\)?).?$/, head,
           include_captures: true,
           on: [:amper],
           trim: true
         ) do
      [_] -> {head, ""}
      [parent, "&"] -> {parent, "&"}
      [pseudo, "(&)"] -> {pseudo, "(&)"}
    end
  end

  Enum.each(@appendable_first_char, fn char ->
    def is_trail_concat(<<unquote(char)::utf8, _::binary>>), do: true
  end)

  def is_trail_concat(_), do: false

  Enum.each(@appendable_first_char, fn char ->
    def is_lead_concat(<<unquote(char)::utf8, _::binary>>), do: true
  end)

  def is_lead_concat(_), do: false

  @doc """
  Produces a list of lists where each list is a chain of selectors, representing all combinations between the selectors that need to occurr when a "," comma is found.
  If we have a cssex rule of:

  .class_1, .class_2 {
     &.class_3, .class_4 {
     }
  }

  Then we have a chain that we can split as:
  iex> split_chains([".class_1, .class_2", "&.class_3, .class_4"])
  [
    [".class_1", "&.class_3"],
    [".class_1", ".class_4"],
    [".class_2", "&.class_3"],
    [".class_2", ".class_4"]
  ]

  These then can be passed through `ampersand_join` in order to produce:
  [
    [".class_1.class_3"],
    [".class_1", ".class_4"],
    [".class_2.class_3"],
    [".class_2", ".class_4"]
  ]

  Then a list of final strings:
  [
    ".class_1.class_3",
    ".class_1 .class_4",
    ".class_2.class_3",
    ".class_2 .class_4"
  ]

  Which then can be joined together into a single css declaration:
  ".class_1.class_3, .class_1 .class_4, .class_2.class_3, .class_2 .class_4"
  """
  @spec split_chains(list(String.t())) :: list(list(String.t()))
  def split_chains(initial), do: split_chains(initial, [])

  def split_chains([], acc) do
    try do
      Enum.map(acc, fn
        chain when is_list(chain) ->
          chain
          |> :lists.flatten()
          |> ampersand_join()

        chain ->
          [chain]
      end)
    catch
      {:error, _} = error -> error
    end
  end

  def split_chains([head | t], []) do
    splits = split_chains_comma_and_brackets(head)

    split_chains(t, splits)
  end

  def split_chains([head | t], acc) do
    splits = split_chains_comma_and_brackets(head)

    new_acc =
      Enum.reduce(acc, [], fn chain, i_acc_1 ->
        Enum.reduce(splits, i_acc_1, fn cur, i_acc_2 ->
          [[[chain | [cur]] |> :lists.flatten()] | i_acc_2]
        end)
      end)

    split_chains(t, new_acc)
  end

  def split_chains_comma_and_brackets(head) do
    case split_chains_maybe_brackets(head) do
      {string, []} ->
        string
        |> String.split(",")
        |> Enum.map(fn el -> String.trim(el) end)

      {string, replacements} ->
        splits_temp =
          string
          |> String.split(",")

        Enum.reduce(replacements, splits_temp, fn {replacement, original}, splits ->
          Enum.map(splits, fn split ->
            String.trim(String.replace(split, replacement, original))
          end)
        end)
    end
  end

  def split_chains_maybe_brackets(value) do
    {value, acc, _} =
      case Regex.scan(~r/\(.*?\)/, value) do
        nil ->
          {value, [], 0}

        matches ->
          Enum.reduce(matches, {value, [], 0}, fn [match], {string, acc, count} ->
            replacement = "<!@>#{count}<@!>"
            {String.replace(string, match, replacement), [{replacement, match} | acc], count + 1}
          end)
      end

    {value, acc}
  end

  def search_args_split(text, n), do: search_args_split(text, n, 0, [], [])

  def search_args_split([], _, _, acc, full_acc) do
    final_full_acc =
      case IO.chardata_to_string(acc) |> String.trim() do
        "" -> full_acc
        final_arg -> [final_arg | full_acc]
      end

    :lists.reverse(final_full_acc)
  end

  def search_args_split([char | rem], 0, levels, acc, full_acc) do
    search_args_split(rem, 0, levels, [acc, char], full_acc)
  end

  def search_args_split([?) | rem], n, levels, acc, full_acc)
      when levels > 0 and n > 0 do
    search_args_split(rem, n, levels - 1, [acc, ?)], full_acc)
  end

  def search_args_split([?( | rem], n, levels, acc, full_acc),
    do: search_args_split(rem, n, levels + 1, [acc, ?(], full_acc)

  def search_args_split([?, | rem], n, 0, acc, full_acc),
    do: search_args_split(rem, n - 1, 0, [], [IO.chardata_to_string(acc) | full_acc])

  def search_args_split([char | rem], n, levels, acc, full_acc) do
    search_args_split(rem, n, levels, [acc, char], full_acc)
  end

  def search_for(content, target), do: search_for(content, target, [])

  Enum.each(['{', ';'], fn chars ->
    def search_for(unquote(chars) ++ rem, unquote(chars), acc), do: {:ok, {rem, acc}}
  end)

  def search_for([char | rem], chars, acc), do: search_for(rem, chars, [acc | [char]])
  def search_for([], _, acc), do: {:error, {[], acc}}

  def block_search([125 | _rem], 1, acc), do: {:ok, acc}
  def block_search([125 | rem], n, acc), do: block_search(rem, n - 1, [acc, "}"])
  def block_search([123 | rem], n, acc), do: block_search(rem, n + 1, [acc, "{"])
  def block_search([char | rem], n, acc), do: block_search(rem, n, [acc, char])
  def block_search([], _, _acc), do: {:error, {:block_search, :no_closing}}

  def valid_attribute_kv?(key, val)
      when is_binary(key) and
             is_binary(val) and
             byte_size(key) > 0 and
             byte_size(val) > 0,
      do: true

  def valid_attribute_kv?(_, _), do: false

  def calc_line_offset(eex_lines, final) do
    lines =
      for <<char <- final>>, <<char>> in @line_terminators, reduce: 0 do
        acc -> acc + 1
      end

    eex_lines - lines
  end

  def file_and_line_opts(%{file: nil, line: line}), do: [line: line || 0]

  def file_and_line_opts(%{file: file, line: line}),
    do: [file: file, line: line || 0]
end
