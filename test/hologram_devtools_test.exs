defmodule HoloDevTest do
  use ExUnit.Case

  test "version/0 returns the package version" do
    assert HoloDev.version() == "0.1.0"
  end

  test "disabled?/0 defaults to false" do
    refute HoloDev.disabled?()
  end

  test "port/0 defaults to 4008" do
    assert HoloDev.port() == 4008
  end

  test "output_dir/0 defaults to .hologram" do
    assert HoloDev.output_dir() == ".hologram"
  end
end
