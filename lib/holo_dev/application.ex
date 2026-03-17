defmodule HoloDev.Application do
  @moduledoc false
  use Application

  @impl Application
  def start(_type, _args) do
    if HoloDev.disabled?() do
      Supervisor.start_link([], strategy: :one_for_one, name: HoloDev.Supervisor)
    else
      children = [
        {Registry, keys: :duplicate, name: HoloDev.WebSocketRegistry},
        {Registry, keys: :duplicate, name: HoloDev.BridgeRegistry},
        HoloDev.Introspection.Store,
        HoloDev.Introspection.StateTracker,
        HoloDev.Introspection.LiveStateStore,
        HoloDev.Introspection.Watcher,
        {Bandit, plug: HoloDev.Web.Endpoint, port: HoloDev.port(), ip: {127, 0, 0, 1}}
      ]

      opts = [strategy: :one_for_one, name: HoloDev.Supervisor]

      case Supervisor.start_link(children, opts) do
        {:ok, pid} ->
          IO.puts("[HoloDev] Running at http://localhost:#{HoloDev.port()}")
          IO.puts("[HoloDev] WebSocket at ws://localhost:#{HoloDev.port()}/ws")
          IO.puts("[HoloDev] Bridge at ws://localhost:#{HoloDev.port()}/bridge")
          {:ok, pid}

        error ->
          error
      end
    end
  end
end
