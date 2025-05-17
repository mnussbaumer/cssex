defmodule CSSEx.Helpers.Output do
  @moduledoc false

  @enforce_keys [:data]
  @temp_ext "-cssex.temp"
  defstruct [:data, :to_file, :temp_file, :file_path, valid?: true, acc: [], pretty_print?: false]

  def do_finish(%{to_file: nil, pretty_print?: pp?} = data) do
    %__MODULE__{data: data, pretty_print?: pp?}
    |> finish()
  end

  def do_finish(%{to_file: to_file, pretty_print?: pp?} = data) do
    random_string =
      Enum.shuffle(1..255)
      |> Enum.take(12)
      |> to_string
      |> Base.encode16(padding: false)

    temp_file = "#{to_file}#{random_string}#{@temp_ext}"

    base = %__MODULE__{
      data: data,
      file_path: to_file,
      temp_file: temp_file,
      pretty_print?: pp?
    }

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

  def maybe_add_formatting_new_line(%__MODULE__{pretty_print?: true} = ctx) do
    case ctx do
      %__MODULE__{to_file: nil, acc: acc} ->
        %__MODULE__{ctx | acc: [acc | ["\n"]]}

      %__MODULE__{to_file: to_file, valid?: true} ->
        case IO.binwrite(to_file, "\n") do
          :ok -> ctx
          error -> add_error(ctx, error)
        end
    end
  end

  def maybe_add_formatting_new_line(ctx),
    do: ctx

  def maybe_add_charset(
        %__MODULE__{
          to_file: nil,
          acc: acc,
          data: %CSSEx.Parser{charset: charset}
        } = ctx
      )
      when is_binary(charset) do
    %__MODULE__{ctx | acc: [build_charset(charset), acc]}
    |> maybe_add_formatting_new_line()
  end

  def maybe_add_charset(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{charset: charset},
          valid?: true
        } = ctx
      )
      when is_binary(charset) do
    case IO.binwrite(to_file, build_charset(charset)) do
      :ok ->
        ctx
        |> maybe_add_formatting_new_line()

      error ->
        add_error(ctx, error)
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
      ) do
    %__MODULE__{ctx | acc: [acc, imports]}
  end

  def maybe_add_imports(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{imports: imports},
          valid?: true
        } = ctx
      ) do
    case IO.binwrite(to_file, imports) do
      :ok ->
        ctx

      error ->
        add_error(ctx, error)
    end
  end

  def maybe_add_imports(ctx), do: ctx

  def maybe_add_font_faces(
        %__MODULE__{
          to_file: nil,
          acc: acc,
          data: %CSSEx.Parser{ets_fontface: ets, font_face_count: ffc},
          pretty_print?: pp?
        } = ctx
      )
      when ffc > 0 do
    %__MODULE__{ctx | acc: [acc, fold_font_faces_table(ets, pretty_print?: pp?)]}
  end

  def maybe_add_font_faces(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{ets_fontface: ets, font_face_count: ffc},
          valid?: true,
          pretty_print?: pp?
        } = ctx
      )
      when ffc > 0 do
    case fold_font_faces_table(ets, to_file, pretty_print?: pp?) do
      :ok ->
        ctx

      error ->
        add_error(ctx, error)
    end
  end

  def maybe_add_font_faces(ctx), do: ctx

  def maybe_add_css_variables(
        %__MODULE__{
          to_file: nil,
          acc: acc,
          data: %CSSEx.Parser{ets: ets},
          pretty_print?: pp?
        } = ctx
      ) do
    opts = [pretty_print?: pp?]

    case take_root(ets) do
      [] ->
        ctx

      [{k, values}] ->
        %__MODULE__{ctx | acc: [acc | [k, open_curly(opts), values, close_curly(opts)]]}
        |> maybe_add_formatting_new_line()
    end
  end

  def maybe_add_css_variables(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{ets: ets},
          valid?: true,
          pretty_print?: pp?
        } = ctx
      ) do
    opts = [pretty_print?: pp?]

    case take_root(ets) do
      [] ->
        ctx

      [{k, values}] ->
        case IO.binwrite(to_file, [k, open_curly(opts), values, close_curly(opts)]) do
          :ok ->
            ctx
            |> maybe_add_formatting_new_line()

          error ->
            add_error(ctx, error)
        end
    end
  end

  def maybe_add_css_variables(ctx), do: ctx

  def take_root(ets), do: :ets.take(ets, [":root"])

  def maybe_add_expandables(
        %__MODULE__{
          to_file: nil,
          acc: acc,
          data: %CSSEx.Parser{expandables: expandables, expandables_order_map: %{c: c} = eom},
          pretty_print?: pp?
        } = ctx
      )
      when c > 0 do
    opts = [pretty_print?: pp?]

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
                _ -> [selector, open_curly(opts), selector_exp, close_curly(opts)]
              end

            [acc_i | [selector_list | other_selectors]]
        end
      end)

    %__MODULE__{ctx | acc: [acc | new_acc]}
    |> maybe_add_formatting_new_line()
  end

  def maybe_add_expandables(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{expandables: expandables, expandables_order_map: %{c: c} = eom},
          valid?: true,
          pretty_print?: pp?
        } = ctx
      )
      when c > 0 do
    opts = [pretty_print?: pp?]

    Enum.reduce_while(0..c, :ok, fn n, acc ->
      case Map.get(eom, n) do
        nil ->
          {:cont, acc}

        selector ->
          {selector_exp, other_selectors, _, _, _} = Map.get(expandables, selector)

          selector_list =
            case selector_exp do
              [] -> ""
              _ -> [selector, open_curly(opts), selector_exp, close_curly(opts)]
            end

          case IO.binwrite(to_file, [selector_list, other_selectors]) do
            :ok -> {:cont, acc}
            error -> {:halt, error}
          end
      end
    end)
    |> case do
      :ok ->
        ctx

      error ->
        add_error(ctx, error)
    end
  end

  def maybe_add_expandables(ctx), do: ctx

  def add_general(
        %__MODULE__{
          to_file: nil,
          acc: acc,
          data: %CSSEx.Parser{ets: ets, order_map: %{c: c} = om},
          pretty_print?: pp?
        } = ctx
      )
      when c > 0 do
    %__MODULE__{ctx | acc: [acc | fold_attributes_table(ets, om, pretty_print?: pp?)]}
  end

  def add_general(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{ets: ets, order_map: %{c: c} = om},
          valid?: true,
          pretty_print?: pp?
        } = ctx
      )
      when c > 0 do
    case fold_attributes_table(ets, om, to_file, pretty_print?: pp?) do
      :ok ->
        ctx

      error ->
        add_error(ctx, error)
    end
  end

  def add_general(ctx), do: ctx

  def maybe_add_media(
        %__MODULE__{
          to_file: nil,
          acc: acc,
          data: %CSSEx.Parser{media: media},
          pretty_print?: pp?
        } = ctx
      )
      when map_size(media) > 0 do
    %__MODULE__{ctx | acc: write_map_based_rules(nil, media, acc, pretty_print?: pp?)}
  end

  def maybe_add_media(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{media: media},
          valid?: true,
          pretty_print?: pp?
        } = ctx
      )
      when map_size(media) > 0 do
    case write_map_based_rules(to_file, media, nil, pretty_print?: pp?) do
      :ok -> ctx
      error -> add_error(ctx, error)
    end
  end

  def maybe_add_media(ctx), do: ctx

  def maybe_add_supports(
        %__MODULE__{
          to_file: nil,
          acc: acc,
          data: %CSSEx.Parser{supports: supports},
          pretty_print?: pp?
        } = ctx
      )
      when map_size(supports) > 0 do
    %__MODULE__{ctx | acc: write_map_based_rules(nil, supports, acc, pretty_print?: pp?)}
  end

  def maybe_add_supports(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{supports: supports},
          valid?: true,
          pretty_print?: pp?
        } = ctx
      )
      when map_size(supports) > 0 do
    case write_map_based_rules(to_file, supports, nil, pretty_print?: pp?) do
      :ok ->
        ctx

      error ->
        add_error(ctx, error)
    end
  end

  def maybe_add_supports(ctx), do: ctx

  def maybe_add_page(
        %__MODULE__{
          to_file: nil,
          acc: acc,
          data: %CSSEx.Parser{page: page},
          pretty_print?: pp?
        } = ctx
      )
      when map_size(page) > 0 do
    %__MODULE__{ctx | acc: write_map_based_rules(nil, page, acc, pretty_print?: pp?)}
  end

  def maybe_add_page(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{page: page},
          valid?: true,
          pretty_print?: pp?
        } = ctx
      )
      when map_size(page) > 0 do
    case write_map_based_rules(to_file, page, nil, pretty_print?: pp?) do
      :ok ->
        ctx

      error ->
        add_error(ctx, error)
    end
  end

  def maybe_add_page(ctx), do: ctx

  defp write_map_based_rules(nil, map_content, acc, options) when is_list(options) do
    opts =
      options
      |> Keyword.put_new(:indent, 8)
      |> Keyword.put_new(:curly_indent, 4)

    pp? = Keyword.get(options, :pretty_print?, false)

    Enum.reduce(map_content, acc, fn {rule, {ets_table, om}}, acc_i ->
      case fold_attributes_table(ets_table, om, opts) do
        [] ->
          acc_i

        folded ->
          [
            acc_i,
            rule,
            open_curly(opts),
            add_indent(if(pp?, do: 4, else: 0)),
            folded,
            close_curly(Keyword.delete(opts, :curly_indent))
          ]
      end
    end)
  end

  defp write_map_based_rules(to_file, map_content, _acc, options) when is_list(options) do
    opts =
      options
      |> Keyword.put_new(:indent, 8)
      |> Keyword.put_new(:curly_indent, 4)

    pp? = Keyword.get(options, :pretty_print?, false)

    Enum.reduce_while(map_content, :ok, fn {rule, {ets_table, om}}, _acc ->
      case fold_attributes_table(ets_table, om, opts) do
        [] ->
          {:cont, :ok}

        folded ->
          case IO.binwrite(to_file, [
                 rule,
                 open_curly(opts),
                 add_indent(if(pp?, do: 4, else: 0)),
                 folded,
                 close_curly(Keyword.delete(opts, :curly_indent))
               ]) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
      end
    end)
  end

  def maybe_add_keyframes(
        %__MODULE__{
          to_file: nil,
          acc: acc,
          data: %CSSEx.Parser{ets_keyframes: ets, keyframes_order_map: %{c: c} = om},
          pretty_print?: pp?
        } = ctx
      )
      when c > 0 do
    %__MODULE__{ctx | acc: [acc | fold_mapped_table(ets, om, pretty_print?: pp?)]}
    |> maybe_add_formatting_new_line()
  end

  def maybe_add_keyframes(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{ets_keyframes: ets, keyframes_order_map: %{c: c} = om},
          valid?: true,
          pretty_print?: pp?
        } = ctx
      )
      when c > 0 do
    case fold_mapped_table(ets, om, to_file, pretty_print?: pp?) do
      :ok ->
        ctx
        |> maybe_add_formatting_new_line()

      error ->
        add_error(ctx, error)
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

  def fold_attributes_table(ets),
    do: fold_attributes_table(ets, [])

  def fold_attributes_table(ets, options) when is_list(options) do
    :ets.foldl(
      fn {selector, attributes}, acc ->
        [
          acc,
          selector,
          open_curly(options),
          attributes_to_list(attributes, Keyword.put_new(options, :indent, 4)),
          close_curly(options)
        ]
      end,
      [],
      ets
    )
  end

  def fold_attributes_table(ets, %{c: _} = om),
    do: fold_attributes_table(ets, om, [])

  def fold_attributes_table(ets, %{c: c} = om, options) when is_list(options) do
    opts = Keyword.put_new(options, :indent, 4)

    Enum.reduce(0..c, [], fn n, acc ->
      selector = Map.get(om, n)

      case :ets.lookup(ets, selector) do
        [] ->
          acc

        [{_, []}] ->
          acc

        [{_, attrs}] ->
          case selector do
            "" ->
              case attributes_to_list(attrs, opts) do
                [] ->
                  acc

                attrs_list ->
                  [acc, attrs_list, ";"]
              end

            [[]] ->
              case attributes_to_list(attrs, opts) do
                [] ->
                  acc

                attrs_list ->
                  [acc, attrs_list, ";"]
              end

            _ ->
              [
                acc,
                selector,
                open_curly(opts),
                attributes_to_list(attrs, opts),
                close_curly(opts)
              ]
          end
      end
    end)
  end

  def fold_attributes_table(ets, %{c: _} = om, to_file),
    do: fold_attributes_table(ets, om, to_file, [])

  def fold_attributes_table(ets, %{c: c} = om, to_file, options) do
    opts = Keyword.put(options, :indent, 4)

    Enum.reduce(0..c, :ok, fn
      n, :ok ->
        selector = Map.get(om, n)

        case :ets.lookup(ets, selector) do
          [] ->
            :ok

          [{_, []}] ->
            :ok

          [{_, attrs}] ->
            case attributes_to_list(attrs, opts) do
              [] ->
                :ok

              attrs_list ->
                case IO.binwrite(to_file, [
                       selector,
                       open_curly(opts),
                       attrs_list,
                       close_curly(opts)
                     ]) do
                  :ok -> :ok
                  error -> error
                end
            end
        end
    end)
  end

  def fold_mapped_table(ets, %{c: _} = om),
    do: fold_mapped_table(ets, om, [])

  def fold_mapped_table(ets, %{c: c} = om, options) when is_list(options) do
    opts = Keyword.put(options, :indent, 8)
    pp? = Keyword.get(options, :pretty_print?, false)

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
                open_curly(opts),
                Enum.reduce(maps, [], fn {prop, attrs}, acc_1 ->
                  [
                    acc_1,
                    add_indent(if(pp?, do: 4, else: 0)),
                    prop,
                    open_curly(opts),
                    attributes_to_list(attrs, opts),
                    close_curly(Keyword.put(opts, :curly_indent, 4))
                  ]
                end),
                close_curly(opts)
              ]
          ]
      end
    end)
  end

  def fold_mapped_table(ets, %{c: _} = om, to_file) when not is_list(to_file),
    do: fold_mapped_table(ets, om, to_file, [])

  def fold_mapped_table(ets, %{c: c} = om, to_file, options) when is_list(options) do
    opts = Keyword.put(options, :indent, 8)
    pp? = Keyword.get(options, :pretty_print?, false)

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
                open_curly(opts),
                Enum.reduce(maps, [], fn {prop, attrs}, acc_1 ->
                  [
                    acc_1,
                    add_indent(if(pp?, do: 4, else: 0)),
                    prop,
                    open_curly(opts),
                    attributes_to_list(attrs, opts),
                    close_curly(Keyword.put(opts, :curly_indent, 4))
                  ]
                end),
                close_curly(opts)
              ]
            )
            |> case do
              :ok -> :ok
              error -> error
            end
        end
    end)
  end

  def fold_font_faces_table(ets, opts) when is_list(opts) do
    :ets.foldl(
      fn {_, attributes}, acc ->
        [
          acc,
          "@font-face",
          open_curly(opts),
          attributes_to_list(attributes, Keyword.put(opts, :indent, 4)),
          close_curly(opts)
        ]
      end,
      [],
      ets
    )
  end

  def fold_font_faces_table(ets, to_file, opts) when is_list(opts) do
    :ets.foldl(
      fn {_, attributes}, acc ->
        case acc == :ok do
          true ->
            case IO.binwrite(to_file, [
                   "@font-face",
                   open_curly(opts),
                   attributes_to_list(attributes, Keyword.put(opts, :indent, 4)),
                   close_curly(opts)
                 ]) do
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
    actual_chain =
      case chain do
        list when is_list(list) ->
          list
          |> List.flatten()
          |> Enum.join(" ")

        binary when is_binary(binary) ->
          binary
      end

    new_om =
      case :ets.lookup(ets, actual_chain) do
        [{_, existing}] ->
          :ets.insert(ets, {actual_chain, Map.put(existing, attr_key, String.trim(attr_val))})
          om

        [] ->
          :ets.insert(ets, {actual_chain, Map.put(%{}, attr_key, String.trim(attr_val))})

          om
          |> Map.put(:c, c + 1)
          |> Map.put(actual_chain, c)
          |> Map.put(c, actual_chain)
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

  def attributes_to_list(attributes_map, opts \\ [])

  def attributes_to_list(attributes_map, opts) do
    pp? = Keyword.get(opts, :pretty_print?)
    indent = Keyword.get(opts, :indent)

    Enum.reduce(attributes_map, [], fn
      {k, v}, [_ | _] = acc when pp? == true ->
        [acc | [";\n", add_indent(indent), k, ": ", v]]

      {k, v}, [_ | _] = acc ->
        [acc | [";", k, ":", v]]

      {k, v}, [] when pp? == true ->
        [add_indent(indent), k, ": ", v]

      {k, v}, [] ->
        [k, ":", v]
    end)
  end

  def open_curly(opts) do
    case Keyword.get(opts, :pretty_print?) do
      true -> " {\n"
      _ -> "{"
    end
  end

  def close_curly(opts) do
    case Keyword.get(opts, :pretty_print?) do
      true ->
        case Keyword.get(opts, :curly_indent) do
          n when is_integer(n) and n > 0 ->
            "\n#{add_indent(n)}}\n\n"

          _ ->
            "\n}\n\n"
        end

      _ ->
        "}"
    end
  end

  def add_indent(n) when is_integer(n) and n > 0 do
    String.duplicate(" ", n)
  end

  def add_indent(_),
    do: ""
end
