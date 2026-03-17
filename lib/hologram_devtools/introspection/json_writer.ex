defmodule HoloDev.Introspection.JsonWriter do
  @moduledoc false

  def write(data, output_dir \\ nil) do
    dir = output_dir || HoloDev.output_dir()
    File.mkdir_p!(dir)

    write_json(dir, "pages.json", data.pages)
    write_json(dir, "components.json", data.components)
    write_json(dir, "resources.json", data.resources)
    write_json(dir, "modules.json", data.modules)
  end

  defp write_json(dir, filename, data) do
    path = Path.join(dir, filename)
    json = Jason.encode!(data, pretty: true)
    File.write!(path, json)
  end
end
