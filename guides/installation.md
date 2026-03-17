# Installation

> #### Important {: .warning}
>
> HoloDev should not be used in production — make sure the dependency is `:dev` only.

## Mix installation

Add `holo_dev` to your list of dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:holo_dev, "~> 0.1.0", only: :dev}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

After you start your application, HoloDev will be running at `http://localhost:4008` by default.

## Igniter installation

HoloDev has [Igniter](https://github.com/ash-project/igniter) support — an alternative to standard mix installation. It will automatically add the dependency and update your `.gitignore`.

```bash
mix igniter.install holo_dev
```

## Chrome Extension

The Chrome extension gives you the ability to interact with HoloDev features directly alongside your application in the browser.

You can find the extension source at [holo_dev_extension](https://github.com/Neophen/holo_dev_extension).

> #### Note {: .info}
>
> The main HoloDev hex dependency must be added to your mix project — the browser extension alone is not enough.

## Verifying the installation

Once installed, start your application:

```bash
iex -S mix
```

You should see a log message indicating that HoloDev is running:

```
[info] HoloDev running at http://localhost:4008
```

Visit `http://localhost:4008` in your browser to see the dashboard.
