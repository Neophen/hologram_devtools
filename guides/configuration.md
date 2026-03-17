# Configuration

HoloDev works out of the box with sensible defaults, but you can customize its behavior in your `config/dev.exs`.

## Options

```elixir
# config/dev.exs
config :holo_dev,
  port: 4008,
  output_dir: ".hologram",
  disabled?: false
```

### `port`

The port for the devtools web UI and WebSocket server.

- **Default:** `4008`
- **Type:** integer

```elixir
config :holo_dev, port: 9000
```

### `output_dir`

The directory where introspection JSON files are written. These files contain the scanned structure of your pages, components, resources, and modules.

- **Default:** `".hologram"`
- **Type:** string (path)

```elixir
config :holo_dev, output_dir: ".hologram"
```

> #### Tip {: .tip}
>
> Add the output directory to your `.gitignore`. The Igniter installer does this automatically.

### `disabled?`

Completely disables HoloDev. When set to `true`, the web server and file watcher will not start.

- **Default:** `false`
- **Type:** boolean

```elixir
config :holo_dev, disabled?: true
```
