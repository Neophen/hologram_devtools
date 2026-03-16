defmodule HologramDevtools do
  @moduledoc """
  Development tools for the Hologram framework.

  Provides introspection, a devtools web UI, and IDE support.
  Auto-starts with your application in development.
  """

  @version Mix.Project.config()[:version]

  def version, do: @version

  def disabled? do
    Application.get_env(:hologram_devtools, :disabled?, false)
  end

  def port do
    Application.get_env(:hologram_devtools, :port, 4008)
  end

  def output_dir do
    Application.get_env(:hologram_devtools, :output_dir, ".hologram")
  end
end
