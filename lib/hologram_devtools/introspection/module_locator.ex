defmodule HoloDev.Introspection.ModuleLocator do
  @moduledoc false

  alias HoloDev.Introspection.SourceParser

  def extract(modules) do
    modules
    |> Enum.filter(&Code.ensure_loaded?/1)
    |> Enum.map(fn mod ->
      name = mod |> to_string() |> String.replace_leading("Elixir.", "")
      source = SourceParser.get_source_file(mod)

      case source do
        nil ->
          {name, %{file: nil, line: 0}}

        path ->
          relative = SourceParser.make_relative(path)
          line = SourceParser.find_defmodule_line(path, mod)
          {name, %{file: relative, line: line}}
      end
    end)
    |> Enum.filter(fn {_name, %{file: file}} -> file != nil end)
    |> Enum.filter(fn {_name, %{file: file}} -> String.starts_with?(file, "lib/") end)
    |> Enum.into(%{})
  end
end
