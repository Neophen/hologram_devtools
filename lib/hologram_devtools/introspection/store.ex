defmodule HoloDev.Introspection.Store do
  @moduledoc false
  use GenServer

  alias HoloDev.Introspection.{Extractor, JsonWriter}

  @table :holo_dev_introspection

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def pages, do: lookup(:pages)
  def components, do: lookup(:components)
  def resources, do: lookup(:resources)
  def modules, do: lookup(:modules)

  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  end

  @impl GenServer
  def init(_) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    do_introspect()
    {:ok, %{}}
  end

  @impl GenServer
  def handle_cast(:refresh, state) do
    do_introspect()
    notify_websocket_clients()
    {:noreply, state}
  end

  defp do_introspect do
    data = Extractor.run()

    :ets.insert(@table, {:pages, data.pages})
    :ets.insert(@table, {:components, data.components})
    :ets.insert(@table, {:resources, data.resources})
    :ets.insert(@table, {:modules, data.modules})

    try do
      JsonWriter.write(data)
    rescue
      e -> IO.warn("[HoloDev] Failed to write JSON: #{inspect(e)}")
    end

    data
  end

  defp notify_websocket_clients do
    Registry.dispatch(HoloDev.WebSocketRegistry, :clients, fn entries ->
      for {pid, _value} <- entries do
        send(pid, :introspection_updated)
      end
    end)
  rescue
    _ -> :ok
  end

  defp lookup(key) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      [] -> %{}
    end
  rescue
    ArgumentError -> %{}
  end
end
