defmodule CSSEx.Helpers.Output do
  @enforce_keys [:data]
  @temp_ext "-cssex.temp"
  defstruct [:data, :to_file, :file_path, valid?: true, acc: []]

  def do_finish(%{to_file: nil} = data) do
    %__MODULE__{data: data}
    |> finish()
  end

  def do_finish(%{to_file: to_file} = data) do
    base = %__MODULE__{data: data, file_path: to_file}

    case File.mkdir_p(Path.dirname(to_file)) do
      :ok ->
        case File.open("#{to_file}#{@temp_ext}", [:write, :raw]) do
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
    |> add_general()
    |> maybe_add_media()
    |> maybe_add_keyframes()
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
      ) do
    new_acc =
      Enum.reduce(media, acc, fn {media_rule, {ets_table, om}}, acc ->
        [acc, media_rule, "{", fold_attributes_table(ets_table, om), "}"]
      end)

    %__MODULE__{ctx | acc: new_acc}
  end

  def maybe_add_media(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{media: media},
          valid?: true
        } = ctx
      ) do
    Enum.reduce_while(media, :ok, fn {media_rule, {ets_table, om}}, _acc ->
      case IO.binwrite(to_file, [media_rule, "{"]) do
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
    |> case do
      :ok -> ctx
      error -> add_error(ctx, error)
    end
  end

  def maybe_add_media(ctx), do: ctx

  def maybe_add_keyframes(
        %__MODULE__{
          to_file: nil,
          acc: acc,
          data: %CSSEx.Parser{ets_keyframes: ets, keyframes_order_map: om}
        } = ctx
      ),
      do: %__MODULE__{ctx | acc: [acc | fold_attributes_table(ets, om)]}

  def maybe_add_keyframes(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{ets_keyframes: ets, keyframes_order_map: om},
          valid?: true
        } = ctx
      ) do
    case fold_attributes_table(ets, om, to_file) do
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
          file_path: file_path
        } = ctx
      ) do
    case IO.binwrite(to_file, "\n") do
      :ok ->
        case File.close(to_file) do
          :ok ->
            case File.cp("#{file_path}#{@temp_ext}", file_path) do
              :ok ->
                spawn(fn -> File.rm!("#{file_path}#{@temp_ext}") end)
                ctx

              error ->
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
        [acc, selector, "{", attributes, "}"]
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
          [acc, selector, "{", attrs, "}"]
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
            case IO.binwrite(to_file, [selector, "{", attrs, "}"]) do
              :ok -> :ok
              error -> error
            end
        end
    end)
  end

  def fold_font_faces_table(ets) do
    :ets.foldl(
      fn {_, attributes}, acc ->
        [acc, "@font-face{", attributes, "}"]
      end,
      [],
      ets
    )
  end

  def fold_font_faces_table(ets, to_file) do
    :ets.foldl(
      fn {_, attributes}, acc ->
        case acc == :ok && IO.binwrite(to_file, ["@font-face{", attributes, "}"]) do
          :ok -> :ok
          error -> error
        end
      end,
      :ok,
      ets
    )
  end

  def add_error(%__MODULE__{data: data} = ctx, error) do
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
          :ets.insert(ets, {chain, [existing, ";", attr_key, ":", attr_val]})
          om

        [] ->
          :ets.insert(ets, {chain, [attr_key, ":", attr_val]})

          om
          |> Map.put(:c, c + 1)
          |> Map.put(chain, c)
          |> Map.put(c, chain)
      end

    %{data | order_map: new_om}
  end

  def write_media(to_read_from, to_write_to, om) do
    :ets.foldl(
      fn {selector, attributes}, %{c: c} = acc ->
        case :ets.lookup(to_write_to, selector) do
          [{_, existing}] ->
            :ets.insert(to_write_to, {selector, [existing, ";" | attributes]})
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
        content
      ) do
    new_om =
      case :ets.lookup(ets, selector) do
        [{_, existing}] ->
          :ets.insert(ets, {selector, [existing, ";", content]})
          om

        [] ->
          :ets.insert(ets, {selector, content})

          om
          |> Map.put(:c, c + 1)
          |> Map.put(selector, c)
          |> Map.put(c, selector)
      end

    %CSSEx.Parser{data | keyframes_order_map: new_om}
  end
end
