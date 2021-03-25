defmodule CSSEx.Helpers.Shared do
  alias CSSEx.Helpers.Error
  @appendable_first_char CSSEx.Helpers.SelectorChars.appendable_first_char()

  # increment the column token count
  def inc_col(%{column: column} = data, amount \\ 1),
    do: %{data | column: column + amount}

  # increment the line and reset the column
  def inc_line(%{line: line} = data, amount \\ 1),
    do: %{data | column: 0, line: line + amount}

  def generate_prefix(%{current_chain: cc, prefix: nil}), do: cc
  def generate_prefix(%{current_chain: cc, prefix: prefix}), do: prefix ++ cc

  # we only have one element but we do have a prefix, set the split chain to the prefix and reset the current_chain
  def remove_last_from_chain(%{current_chain: [_], prefix: prefix} = data)
      when not is_nil(prefix),
      do: %{data | current_chain: [], split_chain: [prefix]}

  # we only have one element so reset both chains
  def remove_last_from_chain(%{current_chain: [_]} = data),
    do: %{data | current_chain: [], split_chain: []}

  # we have more than one
  def remove_last_from_chain(%{current_chain: [_ | _] = chain, prefix: prefix} = data) do
    [_ | new_chain] = :lists.reverse(chain)

    new_chain =
      case prefix do
        nil -> :lists.reverse(new_chain)
        _ -> prefix ++ :lists.reverse(new_chain)
      end

    case split_chains(new_chain) do
      [_ | _] = splitted ->
        %{data | current_chain: new_chain, split_chain: splitted}

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
        %{data | current_chain: new_chain, split_chain: new_split}

      {:error, error} ->
        CSSEx.Parser.add_error(data, Error.error_msg(error))
    end
  end

  def ampersand_join(initial), do: ampersand_join(initial, [])

  def ampersand_join([<<"&", rem::binary>> | _], []),
    do: throw({:error, {:invalid_parent_concat, rem}})

  def ampersand_join([head, <<"&", rem::binary>> | t], acc) do
    case is_trail_concat(rem) do
      true ->
        ampersand_join([head <> rem | t], acc)

      false ->
        case is_lead_concat(head) do
          true ->
            ampersand_join([rem <> head | t], acc)

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

      [_] ->
        ampersand_join(t, [acc | [head]])
    end
  end

  def ampersand_join([], acc), do: :lists.flatten(acc)

  Enum.each(@appendable_first_char, fn char ->
    def is_trail_concat(<<unquote(char), _::binary>>), do: true
  end)

  def is_trail_concat(_), do: false

  Enum.each(@appendable_first_char, fn char ->
    def is_lead_concat(<<unquote(char), _::binary>>), do: true
  end)

  def is_lead_concat(_), do: false

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
    splits =
      head
      |> String.split(",")
      |> Enum.map(fn el -> String.trim(el) end)

    split_chains(t, splits)
  end

  def split_chains([head | t], acc) do
    splits =
      head
      |> String.split(",")
      |> Enum.map(fn el -> String.trim(el) end)

    new_acc =
      Enum.reduce(acc, [], fn chain, i_acc_1 ->
        Enum.reduce(splits, i_acc_1, fn cur, i_acc_2 ->
          [[[chain | [cur]] |> :lists.flatten()] | i_acc_2]
        end)
      end)

    split_chains(t, new_acc)
  end
end
