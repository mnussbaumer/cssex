defmodule CSSEx.Helpers.Output do
  @enforce_keys [:data]
  defstruct [:data, :to_file, valid?: true, acc: []]

  def do_finish(%{ets: ets, to_file: nil} = data) do
    %__MODULE__{data: data}
    |> finish()
  end

  def do_finish(%{ets: ets, to_file: to_file} = data) do
    base = %__MODULE__{data: data}

    case File.mkdir_p(Path.dirname(to_file)) do
      :ok ->
        case File.open(to_file, [:write, :raw]) do
          {:ok, io_device} ->
            try do
              %__MODULE__{base | to_file: io_device}
              |> finish()
            after
              File.close(to_file)
            end

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
          acc: acc,
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
          data: %CSSEx.Parser{ets: ets}
        } = ctx
      ),
      do: %__MODULE__{ctx | acc: [acc | fold_attributes_table(ets)]}

  def add_general(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{ets: ets},
          valid?: true
        } = ctx
      ) do
    case fold_attributes_table(ets, to_file) do
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
      Enum.reduce(media, acc, fn {media_rule, ets_table}, acc ->
        [acc, media_rule, "{", fold_attributes_table(ets_table), "}"]
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
    Enum.reduce_while(media, :ok, fn {media_rule, ets_table}, _acc ->
      case IO.binwrite(to_file, [media_rule, "{"]) do
        :ok ->
          case fold_attributes_table(ets_table, to_file) do
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
          data: %CSSEx.Parser{ets_keyframes: ets}
        } = ctx
      ),
      do: %__MODULE__{ctx | acc: [acc | fold_attributes_table(ets)]}

  def maybe_add_keyframes(
        %__MODULE__{
          to_file: to_file,
          data: %CSSEx.Parser{ets_keyframes: ets},
          valid?: true
        } = ctx
      ) do
    case fold_attributes_table(ets, to_file) do
      :ok -> ctx
      error -> add_error(ctx, error)
    end
  end

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
          valid?: true
        } = ctx
      ) do
    case IO.binwrite(to_file, "\n") do
      :ok -> ctx
      error -> add_error(ctx, error)
    end
  end

  def add_final_new_line(ctx), do: ctx

  def maybe_add_keyframes(ctx), do: ctx

  def fold_attributes_table(ets) do
    :ets.foldl(
      fn {selector, attributes}, acc ->
        [acc, selector, "{", attributes, "}"]
      end,
      [],
      ets
    )
  end

  def fold_attributes_table(ets, to_file) do
    :ets.foldl(
      fn {selector, attributes}, acc ->
        case acc == :ok && IO.binwrite(to_file, [selector, "{", attributes, "}"]) do
          :ok -> :ok
          error -> error
        end
      end,
      :ok,
      ets
    )
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
end
