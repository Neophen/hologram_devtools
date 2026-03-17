defmodule HoloDev.Web.BridgeHandler do
  @moduledoc """
  WebSocket handler for the bridge connection from the Hologram page.
  Receives live snapshots and action events, forwards edit commands.
  """
  @behaviour WebSock

  alias HoloDev.Introspection.LiveStateStore

  @impl WebSock
  def init(_args) do
    Registry.register(HoloDev.BridgeRegistry, :bridge, %{})
    LiveStateStore.set_bridge_connected(true)
    IO.puts("[HoloDev] Bridge connected")
    {:ok, %{}}
  end

  @impl WebSock
  def handle_in({text, opcode: :text}, state) do
    case JSON.decode(text) do
      {:ok, message} ->
        handle_message(message, state)

      {:error, _} ->
        {:ok, state}
    end
  end

  def handle_in(_other, state) do
    {:ok, state}
  end

  @impl WebSock
  def handle_info({:forward_to_bridge, message}, state) do
    msg = JSON.encode!(message)
    {:push, {:text, msg}, state}
  end

  def handle_info(_msg, state) do
    {:ok, state}
  end

  @impl WebSock
  def terminate(_reason, _state) do
    LiveStateStore.set_bridge_connected(false)
    IO.puts("[HoloDev] Bridge disconnected")
    :ok
  end

  defp handle_message(%{"type" => "snapshot", "data" => data}, state) do
    LiveStateStore.put_snapshot(data)
    {:ok, state}
  end

  defp handle_message(%{"type" => "action", "data" => data}, state) do
    LiveStateStore.put_action(data)
    {:ok, state}
  end

  defp handle_message(%{"type" => "mounted"}, state) do
    IO.puts("[HoloDev] Bridge mounted, awaiting initial snapshot")
    {:ok, state}
  end

  defp handle_message(%{"type" => "pong"}, state) do
    {:ok, state}
  end

  defp handle_message(_msg, state) do
    {:ok, state}
  end
end
