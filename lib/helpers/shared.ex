defmodule CSSEx.Helpers.Shared do
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
    new_chain = :lists.reverse(new_chain)

    %{data | current_chain: new_chain, split_chain: split_chains(new_chain, prefix)}
  end

  def add_selector_to_chain(%{current_chain: cc, prefix: prefix} = data, selector) do
    new_chain = [selector | :lists.reverse(cc)] |> :lists.reverse()

    new_split =
      case new_chain do
        [_] when is_nil(prefix) -> [new_chain]
        [_] -> [prefix ++ new_chain]
        _ -> split_chains(new_chain, prefix)
      end

    %{data | current_chain: new_chain, split_chain: new_split}
  end

  def ampersand_join(initial), do: ampersand_join(initial, [])

  def ampersand_join([head, <<"&", rem::binary>> | t], acc),
    do: ampersand_join([head <> rem | t], acc)

  def ampersand_join([head | t], acc), do: ampersand_join(t, [acc | [head]])

  def ampersand_join([], acc), do: :lists.flatten(acc)

  def split_chains(initial, prefix), do: split_chains(initial, [], prefix)

  def split_chains([], acc, prefix) do
    Enum.map(acc, fn
      chain when is_list(chain) ->
        final = :lists.flatten(chain)

        if(prefix, do: prefix ++ final, else: final)
        |> ampersand_join()

      chain ->
        if(prefix, do: [prefix ++ [chain]], else: [chain])
    end)
  end

  def split_chains([head | t], [], prefix) do
    splits =
      head
      |> String.split(",")
      |> Enum.map(fn el -> String.trim(el) end)

    split_chains(t, splits, prefix)
  end

  def split_chains([head | t], acc, prefix) do
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

    split_chains(t, new_acc, prefix)
  end
end
