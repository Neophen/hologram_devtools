defmodule HologramDevtools.Web.WebSocketHandlerTest do
  use ExUnit.Case

  alias HologramDevtools.Web.WebSocketHandler

  describe "handle_in/2" do
    setup do
      # Ensure Store ETS table exists (it's created by the application on boot)
      {:ok, state} = WebSocketHandler.init([])
      %{state: state}
    end

    test "get_overview returns version and counts", %{state: state} do
      msg = Jason.encode!(%{type: "get_overview"})
      {:push, {:text, response}, _state} = WebSocketHandler.handle_in({msg, opcode: :text}, state)

      decoded = Jason.decode!(response)
      assert decoded["type"] == "overview"
      assert is_binary(decoded["data"]["version"])
      assert is_integer(decoded["data"]["pages"])
      assert is_integer(decoded["data"]["components"])
      assert is_integer(decoded["data"]["resources"])
    end

    test "get_routes returns list of routes", %{state: state} do
      msg = Jason.encode!(%{type: "get_routes"})
      {:push, {:text, response}, _state} = WebSocketHandler.handle_in({msg, opcode: :text}, state)

      decoded = Jason.decode!(response)
      assert decoded["type"] == "routes"
      assert is_list(decoded["data"])
    end

    test "get_component_tree returns tree structure", %{state: state} do
      msg = Jason.encode!(%{type: "get_component_tree"})
      {:push, {:text, response}, _state} = WebSocketHandler.handle_in({msg, opcode: :text}, state)

      decoded = Jason.decode!(response)
      assert decoded["type"] == "component_tree"
      assert decoded["data"]["root"]["id"] == "root"
      assert decoded["data"]["root"]["type"] == "root"
    end

    test "unknown message type returns error", %{state: state} do
      msg = Jason.encode!(%{type: "nonexistent"})
      {:push, {:text, response}, _state} = WebSocketHandler.handle_in({msg, opcode: :text}, state)

      decoded = Jason.decode!(response)
      assert decoded["type"] == "error"
      assert decoded["data"]["message"] =~ "Unknown message type"
    end

    test "invalid JSON returns error", %{state: state} do
      {:push, {:text, response}, _state} = WebSocketHandler.handle_in({"not json", opcode: :text}, state)

      decoded = Jason.decode!(response)
      assert decoded["type"] == "error"
      assert decoded["data"]["message"] =~ "Invalid JSON"
    end

    test "subscribe returns confirmation", %{state: state} do
      msg = Jason.encode!(%{type: "subscribe"})
      {:push, {:text, response}, new_state} = WebSocketHandler.handle_in({msg, opcode: :text}, state)

      decoded = Jason.decode!(response)
      assert decoded["type"] == "subscribed"
      assert new_state.subscribed_events
    end
  end

  describe "handle_info/2" do
    test "introspection_updated pushes overview to client" do
      {:ok, state} = WebSocketHandler.init([])
      {:push, {:text, response}, _state} = WebSocketHandler.handle_info(:introspection_updated, state)

      decoded = Jason.decode!(response)
      assert decoded["type"] == "introspection_updated"
      assert is_map(decoded["data"])
    end
  end
end
