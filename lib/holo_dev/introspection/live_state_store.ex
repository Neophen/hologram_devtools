defmodule HoloDev.Introspection.LiveStateStore do
  @moduledoc """
  Stores live component state snapshots received from the bridge script.
  Maintains the latest snapshot and an action history ring buffer.
  """
  use GenServer

  @table :holo_dev_live_state
  @action_table :holo_dev_action_history
  @max_actions 200

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Store a snapshot from the bridge"
  def put_snapshot(snapshot) do
    :ets.insert(@table, {:latest, snapshot})
    notify_clients(:live_snapshot, snapshot)
  rescue
    ArgumentError -> :ok
  end

  @doc "Get the latest snapshot"
  def get_snapshot do
    case :ets.lookup(@table, :latest) do
      [{:latest, snapshot}] -> snapshot
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc "Record an action execution"
  def put_action(action) do
    counter = :ets.update_counter(@table, :action_counter, {2, 1}, {:action_counter, 0})
    :ets.insert(@action_table, {counter, action})

    # Trim old entries
    if counter > @max_actions do
      oldest = counter - @max_actions
      :ets.select_delete(@action_table, [{{:"$1", :_}, [{:<, :"$1", oldest}], [true]}])
    end

    notify_clients(:action_executed, action)
  rescue
    ArgumentError -> :ok
  end

  @doc "Get recent actions, optionally limited"
  def get_actions(limit \\ @max_actions) do
    @action_table
    |> :ets.tab2list()
    |> Enum.sort_by(fn {counter, _} -> counter end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {_counter, action} -> action end)
  rescue
    ArgumentError -> []
  end

  @doc "Check if bridge is connected"
  def bridge_connected? do
    case :ets.lookup(@table, :bridge_connected) do
      [{:bridge_connected, true}] -> true
      _ -> false
    end
  rescue
    ArgumentError -> false
  end

  @doc "Set bridge connection status"
  def set_bridge_connected(connected) do
    :ets.insert(@table, {:bridge_connected, connected})
  rescue
    ArgumentError -> :ok
  end

  @impl GenServer
  def init(_) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(@action_table, [:named_table, :ordered_set, :public, write_concurrency: true])
    :ets.insert(@table, {:action_counter, 0})
    {:ok, %{}}
  end

  defp notify_clients(event_type, data) do
    Registry.dispatch(HoloDev.WebSocketRegistry, :clients, fn entries ->
      msg = JSON.encode!(%{type: to_string(event_type), data: data})

      for {pid, _value} <- entries do
        send(pid, {:bridge_event, event_type, msg})
      end
    end)
  rescue
    _ -> :ok
  end
end
