# Holo Dev - Unofficial devtools for Hologram

<!-- TODO: Add screenshot/banner image -->
<!-- ![HoloDev](https://github.com/user-attachments/assets/PLACEHOLDER) -->

<div align="center">

[![Version Badge](https://img.shields.io/github/v/release/Neophen/holo_dev?color=lawn-green)](https://hexdocs.pm/holo_dev)
[![Hex.pm Downloads](https://img.shields.io/hexpm/dw/holo_dev?style=flat&label=downloads&color=blue)](https://hex.pm/packages/holo_dev)
[![GitHub License](https://img.shields.io/github/license/Neophen/holo_dev)](https://github.com/Neophen/holo_dev/blob/main/LICENSE)

</div>

[Holo Dev](https://github.com/Neophen/holo_dev) is a development companion for the [Hologram](https://github.com/nickmcdonnough/hologram) framework — providing introspection, a devtools UI, and IDE support for your Hologram applications.

Designed to enhance your development experience, HoloDev gives you:

- 🌳 Introspect your pages, components, and resources
- 🔍 Browse your application structure in a dedicated web UI
- 🔗 Watch for file changes and auto-update introspection data
- 🔦 IDE support for navigating your Hologram project

<!-- TODO: Add demo video/gif -->
<!-- https://github.com/user-attachments/assets/PLACEHOLDER -->

## Getting started

> [!IMPORTANT]
> HoloDev should not be used in production — make sure the dependency is `:dev` only.

### Mix installation

Add `holo_dev` to your list of dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:holo_dev, "~> 0.1.0", only: :dev}
  ]
end
```

After you start your application, HoloDev will be running at `http://localhost:4008` by default.

### Igniter installation

HoloDev has [Igniter](https://github.com/ash-project/igniter) support — an alternative to standard mix installation. It will automatically add the dependency and update your `.gitignore`.

```bash
mix igniter.install holo_dev
```

### Chrome Extension

<!-- TODO: Add Chrome Web Store link once published -->
<!-- [Chrome extension](https://chromewebstore.google.com/detail/PLACEHOLDER) -->

The Chrome extension is coming soon. It will give you the ability to interact with HoloDev features directly alongside your application in the browser.

You can find the extension source at [holo_dev_extension](https://github.com/Neophen/holo_dev_extension).

> [!NOTE]
> The main HoloDev hex dependency must be added to your mix project — the browser extension alone is not enough.

## Optional configuration

```elixir
# config/dev.exs
config :holo_dev,
  port: 4008,              # default port for the devtools UI
  output_dir: ".hologram", # directory for introspection output
  disabled?: false          # set to true to disable devtools
```

## License

Licensed under the [MIT License](LICENSE).
