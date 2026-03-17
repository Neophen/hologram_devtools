defmodule HoloDev.Introspection.Extractor do
  @moduledoc false

  alias HoloDev.Introspection.{
    PageExtractor,
    ComponentExtractor,
    ResourceExtractor,
    ModuleLocator
  }

  def run do
    ensure_all_modules_loaded()
    modules = :code.all_loaded() |> Enum.map(&elem(&1, 0))

    %{
      pages: PageExtractor.extract(modules),
      components: ComponentExtractor.extract(modules),
      resources: ResourceExtractor.extract(modules),
      modules: ModuleLocator.extract(modules)
    }
  end

  defp ensure_all_modules_loaded do
    for dir <- :code.get_path(),
        file <- Path.wildcard(Path.join(to_string(dir), "*.beam")) do
      mod = file |> Path.basename(".beam") |> String.to_atom()
      Code.ensure_loaded(mod)
    end

    :ok
  end
end
