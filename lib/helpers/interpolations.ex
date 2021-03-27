defmodule CSSEx.Helpers.Interpolations do
  # replaces the value if it mentions a cssex variable and that variable is bound
  # in either the local_scope (first match) or the global scope (second match)
  alias CSSEx.Helpers.EEX, as: HEEX

  @regex_val ~r/(?<interpolation><\$.+\$>)|(?<eex_l><%=.+?end\s?%>)|(?<eex_s><%=.+?%>)/u
  @regex_arg ~r/(?<interpolation><\$.+\$>)|<%=\s?(?<eex_l>.+?)\?end\s+?%>|<%=(?<eex_s>.+?)%>/u

  def maybe_replace_val(<<"@$$", var_name::binary>>, %{local_scope: ls})
      when is_map_key(ls, var_name),
      do: {:ok, Map.fetch!(ls, var_name)}

  def maybe_replace_val(<<"@$$", var_name::binary>>, %{scope: scope})
      when is_map_key(scope, var_name),
      do: {:ok, Map.fetch!(scope, var_name)}

  def maybe_replace_val(<<"@$$", var_name::binary>>, _data),
    do: {:error, {:not_declared, :var, var_name}}

  def maybe_replace_val(val, data) do
    case Regex.scan(@regex_val, val, capture: [:interpolation, :eex_l, :eex_s]) do
      [] ->
        {:ok, val}

      tokens ->
        Enum.reduce_while(tokens, {:ok, val}, fn captures, {_result, acc} ->
          case captures do
            [interpol, "", ""] ->
              without_markers = String.replace(interpol, ~r/<\$\s*|\s*\$>/, "")

              case maybe_replace_val("@$$" <> without_markers, data) do
                {:ok, replaced} -> {:cont, {:ok, String.replace(acc, interpol, replaced)}}
                error -> {:halt, error}
              end

            ["", eex, ""] ->
              {:cont, {:ok, String.replace(acc, eex, HEEX.eval_with_bindings(eex, data))}}

            ["", "", eex] ->
              {:cont, {:ok, String.replace(acc, eex, HEEX.eval_with_bindings(eex, data))}}

            _ ->
              {:cont, {:ok, acc}}
          end
        end)
    end
  rescue
    error -> {:error, {:eex, error}}
  end

  def maybe_replace_arg(nil, data), do: {:ok, nil}

  def maybe_replace_arg(<<"@$$", _::binary>> = full, data),
    do: maybe_replace_val(full, data)

  def maybe_replace_arg(<<"%::", name::binary>> = full, %{local_assigns: la})
      when is_map_key(la, name),
      do: {:ok, Map.fetch!(la, name)}

  def maybe_replace_arg(<<"%::", name::binary>>, %{assigns: a})
      when is_map_key(a, name),
      do: {:ok, Map.fetch!(a, name)}

  def maybe_replace_arg(<<"%::", name::binary>>, _data),
    do: {:error, {:not_declared, :var, name}}

  def maybe_replace_arg(val, data) do
    case Regex.scan(@regex_arg, val, capture: [:interpolation, :eex_l, :eex_s]) do
      [] ->
        {:ok, val}

      tokens ->
        Enum.reduce_while(tokens, {:ok, val}, fn captures, {_result, acc} ->
          case captures do
            [interpol, "", ""] ->
              without_markers = String.replace(interpol, ~r/<\$\s*|\s*\$>/, "")

              case maybe_replace_val("@$$" <> without_markers, data) do
                {:ok, replaced} -> {:cont, {:ok, String.replace(acc, interpol, replaced)}}
                error -> {:halt, error}
              end

            ["", eex, ""] ->
              {:cont,
               {:ok, String.replace(acc, eex, HEEX.eval_with_bindings(String.trim(eex), data))}}

            ["", "", eex] ->
              {:cont,
               {:ok, String.replace(acc, eex, HEEX.eval_with_bindings(String.trim(eex), data))}}

            _ ->
              {:cont, {:ok, acc}}
          end
        end)
    end
  rescue
    error -> {:error, {:eex, error}}
  end
end
