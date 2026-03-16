defmodule HologramDevtools.Introspection.ResourceExtractor do
  @moduledoc false

  alias HologramDevtools.Introspection.SourceParser

  def extract(modules) do
    modules
    |> Enum.filter(&ash_resource?/1)
    |> Enum.map(&extract_resource/1)
    |> Enum.into(%{})
  end

  defp ash_resource?(mod) do
    Code.ensure_loaded?(mod) and
      function_exported?(mod, :spark_is, 0) and
      mod.spark_is() == Ash.Resource
  rescue
    _ -> false
  end

  defp extract_resource(mod) do
    name = mod |> to_string() |> String.replace_leading("Elixir.", "")
    source = SourceParser.get_source_file(mod)
    relative_path = if source, do: SourceParser.make_relative(source)
    mod_line = if source, do: SourceParser.find_defmodule_line(source, mod), else: 1

    attributes = extract_attributes(mod, source)
    relationships = extract_relationships(mod, source)

    {name, %{
      file: relative_path,
      line: mod_line,
      attributes: attributes,
      relationships: relationships
    }}
  end

  defp extract_attributes(mod, source) do
    Ash.Resource.Info.attributes(mod)
    |> Enum.map(fn attr ->
      line =
        if source do
          SourceParser.find_pattern_line(source, ~r/^\s*attribute\s+:#{attr.name}/)
        end

      %{
        name: attr.name,
        type: inspect(attr.type),
        line: line || 0,
        primaryKey: attr.primary_key?
      }
    end)
  rescue
    _ -> []
  end

  defp extract_relationships(mod, source) do
    Ash.Resource.Info.relationships(mod)
    |> Enum.map(fn rel ->
      dest = rel.destination |> to_string() |> String.replace_leading("Elixir.", "")

      line =
        if source do
          SourceParser.find_pattern_line(source, ~r/^\s*#{rel.type}\s+:#{rel.name}/)
        end

      %{
        name: rel.name,
        type: to_string(rel.type),
        destination: dest,
        line: line || 0
      }
    end)
  rescue
    _ -> []
  end
end
