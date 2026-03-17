defmodule HoloDev.Web.WebSocketHandler do
  @moduledoc false
  @behaviour WebSock

  alias HoloDev.Introspection.Store

  @impl WebSock
  def init(_args) do
    # Register this process to receive introspection updates
    Registry.register(HoloDev.WebSocketRegistry, :clients, %{})
    {:ok, %{subscribed_events: false}}
  end

  @impl WebSock
  def handle_in({text, opcode: :text}, state) do
    case JSON.decode(text) do
      {:ok, message} ->
        handle_message(message, state)

      {:error, _} ->
        error = JSON.encode!(%{type: "error", data: %{message: "Invalid JSON"}})
        {:push, {:text, error}, state}
    end
  end

  def handle_in(_other, state) do
    {:ok, state}
  end

  @impl WebSock
  def handle_info(:introspection_updated, state) do
    overview = build_overview()
    msg = JSON.encode!(%{type: "introspection_updated", data: overview})
    {:push, {:text, msg}, state}
  end

  def handle_info(_msg, state) do
    {:ok, state}
  end

  @impl WebSock
  def terminate(_reason, _state) do
    :ok
  end

  defp handle_message(%{"type" => "get_component_tree"}, state) do
    pages = Store.pages()
    components = Store.components()

    tree = build_component_tree(pages, components)
    msg = JSON.encode!(%{type: "component_tree", data: tree})
    {:push, {:text, msg}, state}
  end

  defp handle_message(%{"type" => "get_component", "id" => id}, state) do
    pages = Store.pages()
    components = Store.components()

    data =
      case Map.get(pages, id) do
        nil -> Map.get(components, id)
        page -> page
      end

    if data do
      msg = JSON.encode!(%{type: "component", data: Map.put(data, :id, id)})
      {:push, {:text, msg}, state}
    else
      msg = JSON.encode!(%{type: "error", data: %{message: "Component not found: #{id}"}})
      {:push, {:text, msg}, state}
    end
  end

  defp handle_message(%{"type" => "get_routes"}, state) do
    pages = Store.pages()

    routes =
      pages
      |> Enum.filter(fn {_name, info} -> Map.has_key?(info, :route) end)
      |> Enum.map(fn {name, info} ->
        %{
          module: name,
          route: info[:route],
          file: info[:file],
          line: info[:line]
        }
      end)
      |> Enum.sort_by(& &1.route)

    msg = JSON.encode!(%{type: "routes", data: routes})
    {:push, {:text, msg}, state}
  end

  defp handle_message(%{"type" => "get_resources"}, state) do
    resources = Store.resources()
    msg = JSON.encode!(%{type: "resources", data: resources})
    {:push, {:text, msg}, state}
  end

  defp handle_message(%{"type" => "get_overview"}, state) do
    overview = build_overview()
    msg = JSON.encode!(%{type: "overview", data: overview})
    {:push, {:text, msg}, state}
  end

  defp handle_message(%{"type" => "subscribe"}, state) do
    msg = JSON.encode!(%{type: "subscribed", data: %{message: "Subscribed to updates"}})
    {:push, {:text, msg}, %{state | subscribed_events: true}}
  end

  defp handle_message(%{"type" => type}, state) do
    msg = JSON.encode!(%{type: "error", data: %{message: "Unknown message type: #{type}"}})
    {:push, {:text, msg}, state}
  end

  defp build_overview do
    pages = Store.pages()
    components = Store.components()
    resources = Store.resources()

    %{
      version: HoloDev.version(),
      pages: map_size(pages),
      components: map_size(components),
      resources: map_size(resources)
    }
  end

  defp build_component_tree(pages, components) do
    page_nodes =
      pages
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map(fn {name, info} ->
        %{
          id: name,
          name: short_name(name),
          type: "page",
          route: Map.get(info, :route),
          file: info[:file],
          props: Map.get(info, :props, []),
          children: []
        }
      end)

    component_nodes =
      components
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map(fn {name, info} ->
        %{
          id: name,
          name: short_name(name),
          type: "component",
          file: info[:file],
          props: Map.get(info, :props, []),
          children: []
        }
      end)

    %{
      root: %{
        id: "root",
        name: "Application",
        type: "root",
        children: page_nodes ++ component_nodes
      }
    }
  end

  defp short_name(full_name) do
    full_name |> String.split(".") |> List.last()
  end
end
