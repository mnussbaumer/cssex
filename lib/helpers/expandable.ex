defmodule CSSEx.Helpers.Expandable do
  import CSSEx.Parser, only: [close_current: 1, create_data_for_inner: 3]
  import CSSEx.Helpers.Interpolations, only: [maybe_replace_val: 2]

  @moduledoc false

  def parse(rem, data) do
    case CSSEx.Helpers.Shared.search_for(rem, '{') do
      {:ok, {new_rem, selector}} ->
        case validate_selector(selector, data) do
          {:ok, validated} ->
            case CSSEx.Helpers.Shared.block_search(new_rem, 1, []) do
              {:ok, expandable_content} ->
                inner_data =
                  data
                  |> set_base_selector(validated)
                  |> create_data_for_inner(false, nil)

                case CSSEx.Parser.parse(inner_data, new_rem) do
                  {:finished,
                   {%{column: n_col, line: n_line, media: media} = new_inner_data, new_rem_2}} ->
                    new_data_2 =
                      %{data | line: n_line, column: n_col, media: media}
                      |> add(validated, new_inner_data, expandable_content)
                      |> close_current()

                    {:ok, {new_data_2, new_rem_2}}

                  error ->
                    error
                end

              error ->
                error
            end

          error ->
            error
        end

      error ->
        error
    end
  end

  def add(
        %{expandables: existing, expandables_order_map: %{c: c} = eom} = data,
        selector,
        %{ets: ets, order_map: om, media: media} = inner_data,
        expandable_content
      ) do
    taken_base =
      case :ets.take(ets, [[selector]]) do
        [{_, base}] ->
          CSSEx.Helpers.Output.attributes_to_list(base)

        _ ->
          []
      end

    media_fixed =
      Enum.reduce(media, [], fn {media_rule, {media_table, %{c: mc} = com}}, acc ->
        all_internals =
          Enum.reduce(0..mc, [], fn n, n_acc ->
            case Map.get(com, n) do
              nil ->
                n_acc

              m_selector ->
                case :ets.lookup(media_table, m_selector) do
                  [{[[^selector]], rules}] ->
                    [n_acc, CSSEx.Helpers.Output.attributes_to_list(rules)]

                  [{n_selector, rules}] ->
                    [n_acc, n_selector, "{", CSSEx.Helpers.Output.attributes_to_list(rules), "}"]

                  _ ->
                    n_acc
                end
            end
          end)

        [acc, media_rule, "{", all_internals, "}"]
      end)
      |> IO.iodata_to_binary()

    new_base =
      taken_base
      |> IO.iodata_to_binary()
      |> to_charlist()

    new_content =
      ets
      |> CSSEx.Helpers.Output.fold_attributes_table(om)
      |> IO.iodata_to_binary()
      |> to_charlist()

    new_expandable =
      expandable_content
      |> IO.iodata_to_binary()

    {:ok, new_expandable_fixed} =
      CSSEx.Helpers.Interpolations.maybe_replace_val(new_expandable, inner_data)

    new_expandables_om =
      eom
      |> Map.put(:c, c + 1)
      |> Map.put(selector, c)
      |> Map.put(c, selector)

    case Map.get(existing, selector) do
      nil ->
        %{
          data
          | expandables:
              Map.put(
                existing,
                selector,
                {new_base, new_content, media_fixed, new_expandable_fixed, new_expandable}
              ),
            expandables_order_map: new_expandables_om
        }

      _ ->
        # what to do if it has already been declared? overwrite and warn
        # or keep old and warn ?
        data
    end
  end

  def validate_selector(selector, data) do
    current_selector = String.trim(IO.chardata_to_string(selector))

    case maybe_replace_val(current_selector, data) do
      {:ok, replaced} ->
        case String.split(replaced, ~r/,|\s/) do
          [_] ->
            {:ok, replaced}

          _ ->
            {:error, {:invalid_expandable, current_selector}}
        end

      error ->
        {:error, {:invalid_expandable, current_selector}}
    end
  end

  def set_base_selector(%{order_map: om} = data, validated) do
    new_om =
      data
      |> Map.put([validated], 0)
      |> Map.put(0, [validated])
      |> Map.put(:c, 1)

    %{data | order_map: %{c: 0}, current_chain: [validated]}
  end

  def make_apply(rem, %{expandables: expandables} = data) do
    {:ok, {new_rem, identifiers}} = CSSEx.Helpers.Shared.search_for(rem, ';')

    identifiers
    |> IO.chardata_to_string()
    |> String.split(~r/\s/, trim: true)
    |> Enum.reduce_while({:ok, []}, fn identifier, {:ok, acc} ->
      {expand?, id} =
        case identifier do
          "!" <> id -> {:as_is, id}
          "?" <> id -> {:dynamic, id}
          id -> {:at_parse, id}
        end

      selector = ".#{String.trim(id)}"

      case Map.get(expandables, selector) do
        nil ->
          {:halt, {:error, {:not_declared, :expandable, selector}}}

        {attrs, other_selectors, media, expandable_fixed, expandable} = all ->
          to_add =
            case expand? do
              :as_is ->
                case attrs do
                  [] -> [media, "\n", other_selectors | []]
                  _ -> [attrs, ?;, media | other_selectors]
                end

              :at_parse ->
                expandable_fixed

              :dynamic ->
                expandable
            end

          {:cont, {:ok, [acc | to_add]}}
      end
    end)
    |> case do
      {:ok, expansion} ->
        new_2 =
          [expansion | new_rem]
          |> IO.iodata_to_binary()
          |> to_charlist

        {:ok, new_2}

      error ->
        error
    end
  end
end
