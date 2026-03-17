defmodule HoloDev.Introspection.Extractor do
  @moduledoc false

  alias HoloDev.Introspection.{
    PageExtractor,
    ComponentExtractor,
    ResourceExtractor,
    ModuleLocator
  }

  def run do
    modules = :code.all_loaded() |> Enum.map(&elem(&1, 0))

    %{
      pages: PageExtractor.extract(modules),
      components: ComponentExtractor.extract(modules),
      resources: ResourceExtractor.extract(modules),
      modules: ModuleLocator.extract(modules)
    }
  end
end
