defmodule HologramDevtools.Application do
  @moduledoc false
  use Application

  @impl Application
  def start(_type, _args) do
    if HologramDevtools.disabled?() do
      Supervisor.start_link([], strategy: :one_for_one, name: HologramDevtools.Supervisor)
    else
      children = [
        {Registry, keys: :duplicate, name: HologramDevtools.WebSocketRegistry},
        HologramDevtools.Introspection.Store,
        HologramDevtools.Introspection.Watcher,
        {Bandit, plug: HologramDevtools.Web.Endpoint, port: HologramDevtools.port(), ip: {127, 0, 0, 1}}
      ]

      opts = [strategy: :one_for_one, name: HologramDevtools.Supervisor]

      case Supervisor.start_link(children, opts) do
        {:ok, pid} ->
          IO.puts("[HologramDevtools] Running at http://localhost:#{HologramDevtools.port()}")
          IO.puts("[HologramDevtools] WebSocket at ws://localhost:#{HologramDevtools.port()}/ws")
          {:ok, pid}

        error ->
          error
      end
    end
  end
end
