defmodule HologramDevtoolsTest do
  use ExUnit.Case

  test "version/0 returns the package version" do
    assert HologramDevtools.version() == "0.1.0"
  end

  test "disabled?/0 defaults to false" do
    refute HologramDevtools.disabled?()
  end

  test "port/0 defaults to 4008" do
    assert HologramDevtools.port() == 4008
  end

  test "output_dir/0 defaults to .hologram" do
    assert HologramDevtools.output_dir() == ".hologram"
  end
end
