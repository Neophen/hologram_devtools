# HologramDevtools

<!-- TODO: Add screenshot/banner image -->
<!-- ![HologramDevtools](https://github.com/user-attachments/assets/PLACEHOLDER) -->

<div align="center">

[![Version Badge](https://img.shields.io/github/v/release/Neophen/hologram_devtools?color=lawn-green)](https://hexdocs.pm/hologram_devtools)
[![Hex.pm Downloads](https://img.shields.io/hexpm/dw/hologram_devtools?style=flat&label=downloads&color=blue)](https://hex.pm/packages/hologram_devtools)
[![GitHub License](https://img.shields.io/github/license/Neophen/hologram_devtools)](https://github.com/Neophen/hologram_devtools/blob/main/LICENSE)

</div>

[HologramDevtools](https://github.com/Neophen/hologram_devtools) is a development companion for the [Hologram](https://github.com/nickmcdonnough/hologram) framework — providing introspection, a devtools UI, and IDE support for your Hologram applications.

Designed to enhance your development experience, HologramDevtools gives you:

- 🌳 Introspect your pages, components, and resources
- 🔍 Browse your application structure in a dedicated web UI
- 🔗 Watch for file changes and auto-update introspection data
- 🔦 IDE support for navigating your Hologram project

<!-- TODO: Add demo video/gif -->
<!-- https://github.com/user-attachments/assets/PLACEHOLDER -->

## Getting started

> [!IMPORTANT]
> HologramDevtools should not be used in production — make sure the dependency is `:dev` only.

### Mix installation

Add `hologram_devtools` to your list of dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:hologram_devtools, "~> 0.1.0", only: :dev}
  ]
end
```

After you start your application, HologramDevtools will be running at `http://localhost:4008` by default.

### Igniter installation

HologramDevtools has [Igniter](https://github.com/ash-project/igniter) support — an alternative to standard mix installation. It will automatically add the dependency and update your `.gitignore`.

```bash
mix igniter.install hologram_devtools
```

### Chrome Extension

<!-- TODO: Add Chrome Web Store link once published -->
<!-- [Chrome extension](https://chromewebstore.google.com/detail/PLACEHOLDER) -->

The Chrome extension is coming soon. It will give you the ability to interact with HologramDevtools features directly alongside your application in the browser.

You can find the extension source at [hologram_devtools_extension](https://github.com/Neophen/hologram_devtools_extension).

> [!NOTE]
> The main HologramDevtools hex dependency must be added to your mix project — the browser extension alone is not enough.

## Optional configuration

```elixir
# config/dev.exs
config :hologram_devtools,
  port: 4008,              # default port for the devtools UI
  output_dir: ".hologram", # directory for introspection output
  disabled?: false          # set to true to disable devtools
```

## License

Licensed under the [MIT License](LICENSE).
