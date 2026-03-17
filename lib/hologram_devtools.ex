defmodule HoloDev do
  @moduledoc """
  Development tools for the Hologram framework.

  Provides introspection, a devtools web UI, and IDE support.
  Auto-starts with your application in development.
  """

  @version Mix.Project.config()[:version]

  def version, do: @version

  def disabled? do
    Application.get_env(:holo_dev, :disabled?, false)
  end

  def port do
    Application.get_env(:holo_dev, :port, 4008)
  end

  def output_dir do
    Application.get_env(:holo_dev, :output_dir, ".hologram")
  end
end
