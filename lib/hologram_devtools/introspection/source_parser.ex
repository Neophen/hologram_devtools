defmodule HologramDevtools.Introspection.SourceParser do
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
