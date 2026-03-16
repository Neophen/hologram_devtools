defmodule HologramDevtools.Introspection.ExtractorTest do
  use ExUnit.Case

  alias HologramDevtools.Introspection.Extractor

  test "run/0 returns a map with pages, components, resources, and modules" do
    result = Extractor.run()

    assert is_map(result.pages)
    assert is_map(result.components)
    assert is_map(result.resources)
    assert is_map(result.modules)
  end
end
