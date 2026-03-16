defmodule HologramDevtools.MixProject do
  use Mix.Project

  @version "0.1.4"
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
      main: "welcome",
      source_url: @source_url,
      homepage_url: @source_url,
      extras: [
        "guides/welcome.md",
        "guides/installation.md",
        "guides/configuration.md",
        "CHANGELOG.md",
        LICENSE: [title: "License"]
      ],
      groups_for_extras: [
        "Welcome to HologramDevtools": ~w(guides/welcome.md guides/installation.md),
        Configuration: ~w(guides/configuration.md),
        Changelog: ~w(CHANGELOG.md)
      ],
      groups_for_modules: [
        "Introspection": [
          HologramDevtools.Introspection.Extractor,
          HologramDevtools.Introspection.PageExtractor,
          HologramDevtools.Introspection.ComponentExtractor,
          HologramDevtools.Introspection.ResourceExtractor,
          HologramDevtools.Introspection.ModuleLocator,
          HologramDevtools.Introspection.SourceParser,
          HologramDevtools.Introspection.JsonWriter,
          HologramDevtools.Introspection.Store,
          HologramDevtools.Introspection.Watcher
        ],
        "Web": [
          HologramDevtools.Web.Endpoint,
          HologramDevtools.Web.WebSocketHandler
        ]
      ]
    ]
  end
end
