defmodule CSSEx.Helpers.Interpolations do

  # replaces the value if it mentions a cssex variable and that variable is bound
  # in either the local_scope (first match) or the global scope (second match)
  def maybe_replace_val(<<"@$$", var_name::binary>>, %{local_scope: ls})
      when is_map_key(ls, var_name),
      do: {:ok, Map.fetch!(ls, var_name)}

  def maybe_replace_val(<<"@$$", var_name::binary>>, %{scope: scope})
      when is_map_key(scope, var_name),
      do: {:ok, Map.fetch!(scope, var_name)}

  def maybe_replace_val(<<"@$$", var_name::binary>>, _data),
    do: {:error, {:not_declared, :var, var_name}}

  def maybe_replace_val(val, data) do
    case Regex.scan(~r/<\$(.+?)\$>/u, val) do
      [] ->
        {:ok, val}

      tokens ->
        Enum.reduce_while(tokens, {:ok, val}, fn [token, var_name], {_result, acc} ->
          case var_name do
            <<"@$$", _::binary>> ->
              case maybe_replace_val(var_name, data) do
                {:ok, replaced} -> {:cont, {:ok, String.replace(acc, token, replaced)}}
                error -> {:halt, error}
              end

            _ ->
	      trimmed = String.trim(var_name)
              case maybe_replace_val("@$$" <> trimmed, data) do
                {:ok, replaced} -> {:cont, {:ok, String.replace(acc, token, replaced)}}
                error -> {:halt, error}
              end
          end
        end)
    end
  end

  def maybe_replace_arg(<<"@$$", _::binary>> = full, data),
    do: maybe_replace_val(full, data)

  def maybe_replace_arg(<<"@", assign_name::binary>>, %{local_assigns: la})
      when is_map_key(la, assign_name),
      do: {:ok, Map.fetch!(la, assign_name)}

  def maybe_replace_arg(<<"@", assign_name::binary>>, %{assigns: assigns})
      when is_map_key(assigns, assign_name),
      do: {:ok, Map.fetch!(assigns, assign_name)}

  def maybe_replace_arg(<<"@", assign_name::binary>>, _data),
    do: {:error, {:not_declared, :assign, assign_name}}

  def maybe_replace_arg(<<"<$", _::binary>> = full, data) do
    case Regex.run(~r/<\$(.+?)\$>/u, full) do
      [] -> {:error, {:invalid_argument, full}}
      [_, token] ->
	trimmed = String.trim(token)
	maybe_replace_val("@$$" <> token, data)
    end
  end

  def maybe_replace_arg(val, _), do: {:ok, val}
  
end
