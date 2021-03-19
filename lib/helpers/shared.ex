defmodule CSSEx.Helpers.Shared do
  # increment the column token count
  def inc_col(%{column: column} = data, amount \\ 1),
    do: %{data | column: column + amount}

  # increment the line and reset the column
  def inc_line(%{line: line} = data, amount \\ 1),
    do: %{data | column: 0, line: line + amount}

  def generate_prefix(%{current_chain: cc, prefix: nil}), do: cc
  def generate_prefix(%{current_chain: cc, prefix: prefix}), do: prefix ++ cc

  def ampersand_join(initial), do: ampersand_join(initial, [])

  def ampersand_join([head, <<"&", rem::binary>> | t], acc),
    do: ampersand_join([head <> rem | t], acc)

  def ampersand_join([head | t], acc), do: ampersand_join(t, [acc | [head]])

  def ampersand_join([], acc), do: :lists.flatten(acc)

  def split_chains(initial), do: split_chains(initial, [])

  def split_chains([], acc),
    do:
      Enum.map(acc, fn
        chain when is_list(chain) ->
          chain
          |> :lists.flatten()
          |> ampersand_join()

        chain ->
          [chain]
      end)

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
