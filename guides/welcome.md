# Welcome to HoloDev

[HoloDev](https://github.com/Neophen/holo_dev) is a development companion for the [Hologram](https://github.com/nickmcdonnough/hologram) framework — providing introspection, a devtools UI, and IDE support for your Hologram applications.

Designed to enhance your development experience, HoloDev gives you:

- Introspect your pages, components, and resources
- Browse your application structure in a dedicated web UI
- Watch for file changes and auto-update introspection data
- IDE support for navigating your Hologram project

## How it works

When your application starts in development, HoloDev automatically:

1. **Scans your codebase** for Hologram pages, components, and Ash resources
2. **Starts a local web server** (default port `4008`) with a dashboard showing your app structure
3. **Watches for file changes** and re-scans automatically, keeping the dashboard up to date
4. **Exposes a WebSocket API** for IDE extensions and browser devtools to connect to

## Quick start

Add the dependency and start your app — that's it:

```elixir
# mix.exs
defp deps do
  [
    {:holo_dev, "~> 0.1.0", only: :dev}
  ]
end
```

Then visit `http://localhost:4008` to see your application's structure.

See the [Installation](installation.md) guide for more options, including Igniter support.
