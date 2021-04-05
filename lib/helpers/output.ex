defmodule CSSEx.Helpers.Output do
  @moduledoc false

  @enforce_keys [:data]
  @temp_ext "-cssex.temp"
  defstruct [:data, :to_file, :temp_file, :file_path, valid?: true, acc: []]

  def do_finish(%{to_file: nil} = data) do
    %__MODULE__{data: data}
    |> finish()
  end

  def do_finish(%{to_file: to_file} = data) do
    random_string =
      Enum.shuffle(1..255)
      |> Enum.take(12)
      |> to_string
      |> Base.encode16(padding: false)

    temp_file = "#{to_file}#{random_string}#{@temp_ext}"
    base = %__MODULE__{data: data, file_path: to_file, temp_file: temp_file}

    case File.mkdir_p(Path.dirname(to_file)) do
      :ok ->
        case File.open(temp_file, [:write, :raw]) do
          {:ok, io_device} ->
            %__MODULE__{base | to_file: io_device}
            |> finish()

          error ->
            add_error(base, error)
        end

      error ->
        add_error(base, error)
    end
  end

  def finish(%__MODULE__{} = ctx) do
    ctx
    |> maybe_add_charset()
    |> maybe_add_imports()
    |> maybe_add_font_faces()
    |> maybe_add_css_variables()
    |> maybe_add_expandables()
    |> add_general()
    |> maybe_add_media()
    |> maybe_add_keyframes()
    |> maybe_add_supports()
    |> maybe_add_page()
    |> add_final_new_line()
    |> case do
      %__MODULE__{valid?: true} = ctx -> {:ok, ctx}
      ctx -> {:error, ctx}
    end
  end

  def maybe_add_charset(
        %__MODULE__{
          to_file: nil,
          acc: acc,
          data: %CSSEx.Parser{charset: charset}
        } = ctx
      )
      when is_binary(charset),
      do: %__MODULE__{ctx | acc: [build_charset(charset), acc]}

  def maybe_add_charset(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{charset: charset},
          valid?: true
        } = ctx
      )
      when is_binary(charset) do
    case IO.binwrite(to_file, build_charset(charset)) do
      :ok -> ctx
      error -> add_error(ctx, error)
    end
  end

  def maybe_add_charset(ctx), do: ctx

  def build_charset(charset), do: "@charset #{charset};"

  def maybe_add_imports(
        %__MODULE__{
          to_file: nil,
          acc: acc,
          data: %CSSEx.Parser{imports: imports}
        } = ctx
      ),
      do: %__MODULE__{ctx | acc: [acc, imports]}

  def maybe_add_imports(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{imports: imports},
          valid?: true
        } = ctx
      ) do
    case IO.binwrite(to_file, imports) do
      :ok -> ctx
      error -> add_error(ctx, error)
    end
  end

  def maybe_add_imports(ctx), do: ctx

  def maybe_add_font_faces(
        %__MODULE__{
          to_file: nil,
          acc: acc,
          data: %CSSEx.Parser{ets_fontface: ets}
        } = ctx
      ),
      do: %__MODULE__{ctx | acc: [acc, fold_font_faces_table(ets)]}

  def maybe_add_font_faces(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{ets_fontface: ets},
          valid?: true
        } = ctx
      ) do
    case fold_font_faces_table(ets, to_file) do
      :ok -> ctx
      error -> add_error(ctx, error)
    end
  end

  def maybe_add_css_variables(
        %__MODULE__{
          to_file: nil,
          acc: acc,
          data: %CSSEx.Parser{ets: ets}
        } = ctx
      ) do
    case take_root(ets) do
      [] -> ctx
      [{k, values}] -> %__MODULE__{ctx | acc: [acc | [k, "{", values, "}"]]}
    end
  end

  def maybe_add_css_variables(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{ets: ets},
          valid?: true
        } = ctx
      ) do
    case take_root(ets) do
      [] ->
        ctx

      [{k, values}] ->
        case IO.binwrite(to_file, [k, "{", values, "}"]) do
          :ok -> ctx
          error -> add_error(ctx, error)
        end
    end
  end

  def maybe_add_css_variables(ctx), do: ctx

  def take_root(ets), do: :ets.take(ets, [":root"])

  def maybe_add_expandables(
        %__MODULE__{
          to_file: nil,
          acc: acc,
          data: %CSSEx.Parser{expandables: expandables, expandables_order_map: %{c: c} = eom}
        } = ctx
      ) do
    new_acc =
      Enum.reduce(0..c, [], fn n, acc_i ->
        case Map.get(eom, n) do
          nil ->
            acc_i

          selector ->
            {selector_exp, other_selectors, _, _, _} = Map.get(expandables, selector)

            selector_list =
              case selector_exp do
                [] -> ""
                _ -> [selector, "{", selector_exp, "}"]
              end

            [acc_i | [selector_list | other_selectors]]
        end
      end)

    %__MODULE__{ctx | acc: [acc | new_acc]}
  end

  def maybe_add_expandables(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{expandables: expandables, expandables_order_map: %{c: c} = eom},
          valid?: true
        } = ctx
      ) do
    Enum.reduce_while(0..c, :ok, fn n, acc ->
      case Map.get(eom, n) do
        nil ->
          {:cont, acc}

        selector ->
          {selector_exp, other_selectors, _, _, _} = Map.get(expandables, selector)

          selector_list =
            case selector_exp do
              [] -> ""
              _ -> [selector, "{", selector_exp, "}"]
            end

          case IO.binwrite(to_file, [selector_list, other_selectors]) do
            :ok -> {:cont, acc}
            error -> {:halt, error}
          end
      end
    end)
    |> case do
      :ok -> ctx
      error -> add_error(ctx, error)
    end
  end

  def add_general(
        %__MODULE__{
          to_file: nil,
          acc: acc,
          data: %CSSEx.Parser{ets: ets, order_map: om}
        } = ctx
      ),
      do: %__MODULE__{ctx | acc: [acc | fold_attributes_table(ets, om)]}

  def add_general(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{ets: ets, order_map: om},
          valid?: true
        } = ctx
      ) do
    case fold_attributes_table(ets, om, to_file) do
      :ok -> ctx
      error -> add_error(ctx, error)
    end
  end

  def add_general(ctx), do: ctx

  def maybe_add_media(
        %__MODULE__{
          to_file: nil,
          acc: acc,
          data: %CSSEx.Parser{media: media}
        } = ctx
      ),
      do: %__MODULE__{ctx | acc: write_map_based_rules(nil, media, acc)}

  def maybe_add_media(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{media: media},
          valid?: true
        } = ctx
      ) do
    case write_map_based_rules(to_file, media, nil) do
      :ok -> ctx
      error -> add_error(ctx, error)
    end
  end

  def maybe_add_media(ctx), do: ctx

  def maybe_add_supports(
        %__MODULE__{
          to_file: nil,
          acc: acc,
          data: %CSSEx.Parser{supports: supports}
        } = ctx
      ),
      do: %__MODULE__{ctx | acc: write_map_based_rules(nil, supports, acc)}

  def maybe_add_supports(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{supports: supports},
          valid?: true
        } = ctx
      ) do
    case write_map_based_rules(to_file, supports, nil) do
      :ok -> ctx
      error -> add_error(ctx, error)
    end
  end

  def maybe_add_supports(ctx), do: ctx

  def maybe_add_page(
        %__MODULE__{
          to_file: nil,
          acc: acc,
          data: %CSSEx.Parser{page: page}
        } = ctx
      ),
      do: %__MODULE__{ctx | acc: write_map_based_rules(nil, page, acc)}

  def maybe_add_page(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{page: page},
          valid?: true
        } = ctx
      ) do
    case write_map_based_rules(to_file, page, nil) do
      :ok -> ctx
      error -> add_error(ctx, error)
    end
  end

  def maybe_add_page(ctx), do: ctx

  defp write_map_based_rules(nil, map_content, acc) do
    Enum.reduce(map_content, acc, fn {rule, {ets_table, om}}, acc_i ->
      [acc_i, rule, "{", fold_attributes_table(ets_table, om), "}"]
    end)
  end

  defp write_map_based_rules(to_file, map_content, _acc) do
    Enum.reduce_while(map_content, :ok, fn {rule, {ets_table, om}}, _acc ->
      case IO.binwrite(to_file, [rule, "{"]) do
        :ok ->
          case fold_attributes_table(ets_table, om, to_file) do
            :ok ->
              case IO.binwrite(to_file, "}") do
                :ok -> {:cont, :ok}
                error -> {:halt, error}
              end

            error ->
              {:halt, error}
          end

        error ->
          {:halt, error}
      end
    end)
  end

  def maybe_add_keyframes(
        %__MODULE__{
          to_file: nil,
          acc: acc,
          data: %CSSEx.Parser{ets_keyframes: ets, keyframes_order_map: om}
        } = ctx
      ),
      do: %__MODULE__{ctx | acc: [acc | fold_mapped_table(ets, om)]}

  def maybe_add_keyframes(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{ets_keyframes: ets, keyframes_order_map: om},
          valid?: true
        } = ctx
      ) do
    case fold_mapped_table(ets, om, to_file) do
      :ok -> ctx
      error -> add_error(ctx, error)
    end
  end

  def maybe_add_keyframes(ctx), do: ctx

  def add_final_new_line(
        %__MODULE__{
          to_file: nil,
          acc: acc
        } = ctx
      ),
      do: %__MODULE__{ctx | acc: IO.iodata_to_binary([acc, "\n"])}

  def add_final_new_line(
        %__MODULE__{
          to_file: to_file,
          valid?: true,
          file_path: file_path,
          temp_file: temp_file
        } = ctx
      ) do
    case IO.binwrite(to_file, "\n") do
      :ok ->
        case File.close(to_file) do
          :ok ->
            case File.cp(temp_file, file_path) do
              :ok ->
                spawn(fn -> File.rm(temp_file) end)
                ctx

              error ->
                spawn(fn -> File.rm(temp_file) end)
                add_error(ctx, error)
            end

          error ->
            add_error(ctx, error)
        end

      error ->
        add_error(ctx, error)
    end
  end

  def add_final_new_line(ctx), do: ctx

  def fold_attributes_table(ets) do
    :ets.foldl(
      fn {selector, attributes}, acc ->
        [acc, selector, "{", attributes_to_list(attributes), "}"]
      end,
      [],
      ets
    )
  end

  def fold_attributes_table(ets, %{c: c} = om) do
    Enum.reduce(0..c, [], fn n, acc ->
      selector = Map.get(om, n)

      case :ets.lookup(ets, selector) do
        [] ->
          acc

        [{_, []}] ->
          acc

        [{_, attrs}] ->
          case selector do
            [[]] ->
              case attributes_to_list(attrs) do
                [] ->
                  acc

                attrs_list ->
                  [acc, attrs_list, ";"]
              end

            _ ->
              [acc, selector, "{", attributes_to_list(attrs), "}"]
          end
      end
    end)
  end

  def fold_attributes_table(ets, %{c: c} = om, to_file) do
    Enum.reduce(0..c, :ok, fn
      n, :ok ->
        selector = Map.get(om, n)

        case :ets.lookup(ets, selector) do
          [] ->
            :ok

          [{_, []}] ->
            :ok

          [{_, attrs}] ->
            case IO.binwrite(to_file, [selector, "{", attributes_to_list(attrs), "}"]) do
              :ok -> :ok
              error -> error
            end
        end
    end)
  end

  def fold_mapped_table(ets, %{c: c} = om) do
    Enum.reduce(0..c, [], fn n, acc ->
      selector = Map.get(om, n)

      case :ets.lookup(ets, selector) do
        [] ->
          acc

        [{_, maps}] ->
          [
            acc
            | [
                selector,
                "{",
                Enum.reduce(maps, [], fn {prop, attrs}, acc_1 ->
                  [acc_1, prop, "{", attributes_to_list(attrs), "}"]
                end),
                "}"
              ]
          ]
      end
    end)
  end

  def fold_mapped_table(ets, %{c: c} = om, to_file) do
    Enum.reduce(0..c, :ok, fn
      n, :ok ->
        selector = Map.get(om, n)

        case :ets.lookup(ets, selector) do
          [] ->
            :ok

          [{_, maps}] ->
            IO.binwrite(
              to_file,
              [
                selector,
                "{",
                Enum.reduce(maps, [], fn {prop, attrs}, acc_1 ->
                  [acc_1, prop, "{", attributes_to_list(attrs), "}"]
                end),
                "}"
              ]
            )
            |> case do
              :ok -> :ok
              error -> error
            end
        end
    end)
  end

  def fold_font_faces_table(ets) do
    :ets.foldl(
      fn {_, attributes}, acc ->
        [acc, "@font-face{", attributes_to_list(attributes), "}"]
      end,
      [],
      ets
    )
  end

  def fold_font_faces_table(ets, to_file) do
    :ets.foldl(
      fn {_, attributes}, acc ->
        case acc == :ok do
          true ->
            case IO.binwrite(to_file, ["@font-face{", attributes_to_list(attributes), "}"]) do
              :ok -> :ok
              error -> error
            end

          error ->
            error
        end
      end,
      :ok,
      ets
    )
  end

  def add_error(%__MODULE__{data: data} = ctx, error, optional \\ nil) do
    if(optional, do: IO.inspect(optional))

    %__MODULE__{
      ctx
      | valid?: false,
        data: %CSSEx.Parser{
          data
          | valid?: false,
            error: "error trying to write output: #{inspect(error)}"
        }
    }
  end

  def write_element(
        %CSSEx.Parser{ets: ets, split_chain: chain, order_map: %{c: c} = om} = data,
        attr_key,
        attr_val
      ) do
    new_om =
      case :ets.lookup(ets, chain) do
        [{_, existing}] ->
          :ets.insert(ets, {chain, Map.put(existing, attr_key, attr_val)})
          om

        [] ->
          :ets.insert(ets, {chain, Map.put(%{}, attr_key, attr_val)})

          om
          |> Map.put(:c, c + 1)
          |> Map.put(chain, c)
          |> Map.put(c, chain)
      end

    %{data | order_map: new_om}
  end

  def transfer_mergeable(to_read_from, to_write_to, om) do
    :ets.foldl(
      fn {selector, attributes}, %{c: c} = acc ->
        case :ets.lookup(to_write_to, selector) do
          [{_, existing}] ->
            :ets.insert(to_write_to, {selector, Map.merge(existing, attributes)})
            acc

          [] ->
            :ets.insert(to_write_to, {selector, attributes})

            acc
            |> Map.put(:c, c + 1)
            |> Map.put(selector, c)
            |> Map.put(c, selector)
        end
      end,
      om,
      to_read_from
    )
  end

  def write_keyframe(
        %CSSEx.Parser{ets_keyframes: ets, keyframes_order_map: %{c: c} = om} = data,
        selector,
        inner_ets
      ) do
    new_om =
      case :ets.lookup(ets, selector) do
        [{_, existing}] ->
          new_existing =
            :ets.foldl(
              fn {inner_selector, attributes}, acc ->
                Map.put(
                  acc,
                  inner_selector,
                  Map.merge(
                    Map.get(existing, inner_selector, %{}),
                    attributes
                  )
                )
              end,
              %{},
              inner_ets
            )

          :ets.insert(ets, {selector, new_existing})
          om

        [] ->
          new_existing =
            :ets.foldl(
              fn {inner_selector, attributes}, acc ->
                Map.put(acc, inner_selector, attributes)
              end,
              %{},
              inner_ets
            )

          :ets.insert(ets, {selector, new_existing})

          om
          |> Map.put(:c, c + 1)
          |> Map.put(selector, c)
          |> Map.put(c, selector)
      end

    %CSSEx.Parser{data | keyframes_order_map: new_om}
  end

  def attributes_to_list(attributes_map) do
    Enum.reduce(attributes_map, [], fn
      {k, v}, [_ | _] = acc ->
        [acc | [";", k, ":", v]]

      {k, v}, [] ->
        [k, ":", v]
    end)
  end
end
