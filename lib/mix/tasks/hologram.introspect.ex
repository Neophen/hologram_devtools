defmodule Mix.Tasks.Hologram.Introspect do
  @moduledoc """
  One-shot introspection of Hologram/Ash modules.

  Generates `.hologram/*.json` files for the VS Code extension.

      mix hologram.introspect

  This is a fallback for when you want to run introspection without
  starting the full devtools server.
  """
  use Mix.Task

  @shortdoc "Generate .hologram/ introspection JSON files"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    alias HologramDevtools.Introspection.{Extractor, JsonWriter}

    output_dir = HologramDevtools.output_dir()
    data = Extractor.run()
    JsonWriter.write(data, output_dir)

    IO.puts("Hologram introspection written to #{output_dir}/")
    IO.puts("  pages: #{map_size(data.pages)}")
    IO.puts("  components: #{map_size(data.components)}")
    IO.puts("  resources: #{map_size(data.resources)}")
    IO.puts("  modules: #{map_size(data.modules)}")
  end
end
