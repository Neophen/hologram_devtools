defmodule HoloDev.Introspection.SourceParser do
  @moduledoc false

  def get_source_file(mod) do
    case mod.__info__(:compile)[:source] do
      nil -> nil
      source -> to_string(source)
    end
  rescue
    _ -> nil
  end

  def make_relative(path) do
    cwd = File.cwd!()

    if String.starts_with?(path, cwd) do
      String.replace_leading(path, cwd <> "/", "")
    else
      path
    end
  end

  def find_defmodule_line(path, mod) do
    mod_name = mod |> to_string() |> String.replace_leading("Elixir.", "")

    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.find_value(1, fn {line, idx} ->
          if String.match?(line, ~r/^\s*defmodule\s+#{Regex.escape(mod_name)}\s+do/) do
            idx
          end
        end)

      _ ->
        1
    end
  end

  def find_pattern_line(source_path, pattern) do
    case File.read(source_path) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.find_value(fn {line, idx} ->
          if Regex.match?(pattern, line), do: idx
        end)

      _ ->
        nil
    end
  end

  def extract_state_keys(source_path) do
    case File.read(source_path) do
      {:ok, content} ->
        atom_keys =
          Regex.scan(~r/put_state\s*\([^,]*,\s*:(\w+)/, content)
          |> Enum.map(fn [_, key] -> key end)

        kw_keys =
          Regex.scan(~r/put_state\s*\([^,]+,\s*((?:\w+:\s*[^,)]+,?\s*)+)/, content)
          |> Enum.flat_map(fn [_, kw_str] ->
            Regex.scan(~r/(\w+):/, kw_str) |> Enum.map(fn [_, k] -> k end)
          end)

        map_keys =
          Regex.scan(~r/put_state\s*\([^,]+,\s*%\{([^}]+)\}/, content)
          |> Enum.flat_map(fn [_, map_str] ->
            Regex.scan(~r/(\w+):/, map_str) |> Enum.map(fn [_, k] -> k end)
          end)

        (atom_keys ++ kw_keys ++ map_keys) |> Enum.uniq()

      _ ->
        []
    end
  end

  @doc """
  Extracts component tag names from a template in a source file.
  Looks for PascalCase tags like <Runtime />, <Link>, <PostPreview post={post} />.
  Returns a list of unique component names found.
  """
  def extract_template_components(source_path) do
    case File.read(source_path) do
      {:ok, content} ->
        case Regex.run(~r/~HOLO\s*"""\s*\n(.*?)"""/s, content) do
          [_, template_body] ->
            Regex.scan(~r/<([A-Z][a-zA-Z0-9]*)[\s\/>]/, template_body)
            |> Enum.map(fn [_, name] -> name end)
            |> Enum.uniq()

          _ ->
            []
        end

      _ ->
        []
    end
  end

  @doc """
  Extracts prop assignments from component tags in a template.
  Returns a map of %{"ComponentName" => [%{prop: "name", expression: "expr"}, ...]}.
  E.g. `<PostPreview post={post} />` → %{"PostPreview" => [%{prop: "post", expression: "post"}]}
  """
  def extract_template_prop_bindings(source_path) do
    case File.read(source_path) do
      {:ok, content} ->
        case Regex.run(~r/~HOLO\s*"""\s*\n(.*?)"""/s, content) do
          [_, template_body] ->
            # Match full component tags: <ComponentName prop={expr} prop2={expr2} ... />
            # or <ComponentName prop={expr}>...</ComponentName>
            Regex.scan(~r/<([A-Z][a-zA-Z0-9]*)((?:\s+[a-z_][a-z0-9_]*=\{[^}]*\})*)\s*\/?>/, template_body)
            |> Enum.map(fn
              [_, comp_name, attrs_str] ->
                props =
                  Regex.scan(~r/([a-z_][a-z0-9_]*)=\{([^}]*)\}/, attrs_str)
                  |> Enum.map(fn [_, prop_name, expression] ->
                    %{prop: prop_name, expression: String.trim(expression)}
                  end)

                {comp_name, props}
              _ ->
                nil
            end)
            |> Enum.reject(&is_nil/1)
            |> Enum.group_by(fn {name, _} -> name end, fn {_, props} -> props end)
            |> Enum.into(%{}, fn {name, prop_lists} ->
              {name, prop_lists}
            end)

          _ ->
            %{}
        end

      _ ->
        %{}
    end
  end

  @doc """
  Parses the ~HOLO template using Hologram's own parser and extracts
  component structure including for-loop relationships.

  Returns a map like:
    %{
      "PostPreview" => %{
        loop: %{iterator: "post", source: "posts"},
        bindings: [%{prop: "post", expression: "post"}]
      },
      "Link" => %{loop: nil, bindings: [%{prop: "to", expression: "PostPage"}]}
    }
  """
  def extract_template_structure(source_path) do
    with {:ok, content} <- File.read(source_path),
         [_, template_body] <- Regex.run(~r/~HOLO\s*"""\s*\n(.*?)"""/s, content) do
      tags = Hologram.Template.Parser.parse_markup(template_body)
      walk_tags(tags, [], %{})
    else
      _ -> %{}
    end
  rescue
    _ -> %{}
  end

  # Walk parsed tags maintaining a stack of active for-loop contexts
  defp walk_tags([], _loop_stack, acc), do: acc

  defp walk_tags([{:block_start, {"for", expr_str}} | rest], loop_stack, acc) do
    loop_ctx = parse_for_expression(expr_str)
    walk_tags(rest, [loop_ctx | loop_stack], acc)
  end

  defp walk_tags([{:block_end, "for"} | rest], [_ | loop_stack], acc) do
    walk_tags(rest, loop_stack, acc)
  end

  defp walk_tags([{:block_end, "for"} | rest], [], acc) do
    walk_tags(rest, [], acc)
  end

  defp walk_tags([{tag_type, {tag_name, attrs}} | rest], loop_stack, acc)
       when tag_type in [:self_closing_tag, :start_tag] do
    # Check if this is a component (PascalCase first char)
    acc =
      if component_tag?(tag_name) do
        bindings = extract_bindings_from_attrs(attrs)
        loop = List.first(loop_stack)

        entry = %{
          loop: loop,
          bindings: bindings
        }

        # Use Map.update to handle multiple occurrences (append as list)
        Map.update(acc, tag_name, [entry], fn existing -> existing ++ [entry] end)
      else
        acc
      end

    walk_tags(rest, loop_stack, acc)
  end

  defp walk_tags([_ | rest], loop_stack, acc) do
    walk_tags(rest, loop_stack, acc)
  end

  defp component_tag?(<<first::utf8, _rest::binary>>) when first in ?A..?Z, do: true
  defp component_tag?(_), do: false

  # Parse "{  post <- @posts}" → %{iterator: "post", source: "posts"}
  defp parse_for_expression(expr_str) do
    # Strip outer braces and trim
    inner =
      expr_str
      |> String.trim()
      |> String.replace_leading("{", "")
      |> String.replace_trailing("}", "")
      |> String.trim()

    case Regex.run(~r/(\w+)\s*<-\s*@(\w+)/, inner) do
      [_, iterator, source] ->
        %{iterator: iterator, source: source}

      _ ->
        # Fallback: try without @ (e.g. nested loops)
        case Regex.run(~r/(\w+)\s*<-\s*(\w+)/, inner) do
          [_, iterator, source] -> %{iterator: iterator, source: source}
          _ -> nil
        end
    end
  end

  # Extract prop bindings from parsed tag attributes
  # Attrs format: [{"prop_name", [{:expression, "{expr}"} | {:text, "val"}]}]
  defp extract_bindings_from_attrs(attrs) do
    Enum.map(attrs, fn {prop_name, value_parts} ->
      expression =
        value_parts
        |> Enum.map(fn
          {:expression, expr_str} ->
            # Strip outer braces: "{ post}" → "post"
            expr_str
            |> String.trim()
            |> String.replace_leading("{", "")
            |> String.replace_trailing("}", "")
            |> String.trim()

          {:text, text} ->
            text
        end)
        |> Enum.join()

      %{prop: prop_name, expression: expression}
    end)
  end

  def extract_params_info(source_path, func_name, action_name) do
    case File.read(source_path) do
      {:ok, content} ->
        lines = String.split(content, "\n")
        pattern = ~r/^\s*def\s+#{func_name}\s*\(\s*:#{action_name}\s*,\s*(\w+)/

        case Enum.find_value(lines, fn line ->
               case Regex.run(pattern, line) do
                 [_, params_var] -> params_var
                 _ -> nil
               end
             end) do
          nil ->
            {false, []}

          params_var when params_var in ["_params", "_"] ->
            {false, []}

          params_var ->
            params = extract_param_keys_from_source(lines, func_name, action_name, params_var)
            {length(params) > 0, params}
        end

      _ ->
        {false, []}
    end
  end

  defp extract_param_keys_from_source(lines, func_name, action_name, params_var) do
    func_pattern = ~r/^\s*def\s+#{func_name}\s*\(\s*:#{action_name}\b/
    start_idx = Enum.find_index(lines, fn line -> Regex.match?(func_pattern, line) end)

    if start_idx do
      body =
        lines
        |> Enum.slice((start_idx + 1)..-1//1)
        |> Enum.take_while(fn line -> !Regex.match?(~r/^\s*def(p)?\s+/, line) end)
        |> Enum.join("\n")

      dot_keys =
        Regex.scan(~r/#{Regex.escape(params_var)}\.(\w+)/, body)
        |> Enum.map(fn [_, key] -> key end)
        |> Enum.reject(&(&1 == "event"))

      bracket_keys =
        Regex.scan(~r/#{Regex.escape(params_var)}\[\s*:(\w+)\s*\]/, body)
        |> Enum.map(fn [_, key] -> key end)

      (dot_keys ++ bracket_keys) |> Enum.uniq()
    else
      []
    end
  end
end
