defmodule HologramDevtools.MixProject do
  use Mix.Project

  @version "0.1.3"
  @source_url "https://github.com/Neophen/hologram_devtools"

  def project do
    [
      app: :hologram_devtools,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: false,
      deps: deps(),
      name: "HologramDevtools",
      description: "Development tools for the Hologram framework — introspection, devtools UI, and IDE support",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {HologramDevtools.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:plug, "~> 1.14"},
      {:bandit, "~> 1.0"},
      {:file_system, "~> 1.0"},
      {:igniter, "~> 0.7", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
