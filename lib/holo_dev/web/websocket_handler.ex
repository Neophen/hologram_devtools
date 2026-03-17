defmodule HoloDev.Web.WebSocketHandler do
  @moduledoc false
  @behaviour WebSock

  alias HoloDev.Introspection.{Store, StateTracker, LiveStateStore}

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

  def handle_info({:state_updated, module_name}, state) do
    live_state = StateTracker.get_state(String.to_existing_atom("Elixir." <> module_name))

    if live_state do
      msg = JSON.encode!(%{
        type: "state_updated",
        data: %{module: module_name, state: live_state}
      })
      {:push, {:text, msg}, state}
    else
      {:ok, state}
    end
  rescue
    _ -> {:ok, state}
  end

  def handle_info({:bridge_event, _event_type, encoded_msg}, state) do
    {:push, {:text, encoded_msg}, state}
  end

  def handle_info(_msg, state) do
    {:ok, state}
  end

  @impl WebSock
  def terminate(_reason, _state) do
    :ok
  end

  defp handle_message(%{"type" => "get_component_tree"} = message, state) do
    pages = Store.pages()
    components = Store.components()
    route = Map.get(message, "route")

    tree = build_component_tree(pages, components, route)
    msg = JSON.encode!(%{type: "component_tree", data: tree})
    {:push, {:text, msg}, state}
  end

  defp handle_message(%{"type" => "get_component", "id" => id}, state) do
    pages = Store.pages()
    components = Store.components()

    # Try to find component info by module name first, then by CID
    data =
      case Map.get(pages, id) do
        nil -> Map.get(components, id)
        page -> page
      end

    # If not found by module name, try to find by CID from live data
    {data, _resolved_module} =
      if data do
        {data, id}
      else
        case get_live_data_for_component(id) do
          {:ok, %{module: mod_name}} ->
            static_data = Map.get(components, mod_name, %{})
            {static_data, mod_name}
          _ ->
            {nil, id}
        end
      end

    if data do
      data = Map.put(data, :id, id)

      # Attach live state for pages
      data =
        case get_live_data_for_component(id) do
          {:ok, %{state: live_state, props: live_props}} ->
            data |> Map.put(:state, live_state) |> Map.put(:liveProps, live_props)

          {:ok, %{state: live_state}} ->
            Map.put(data, :state, live_state)

          _ ->
            # For components without CIDs, resolve props from page state
            data |> maybe_resolve_props_from_state(id)
        end

      msg = JSON.encode!(%{type: "component", data: data})
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

  defp handle_message(%{"type" => "get_live_tree"}, state) do
    pages = Store.pages()
    components = Store.components()
    snapshot = LiveStateStore.get_snapshot()

    tree = build_live_tree(pages, components, snapshot)
    msg = JSON.encode!(%{type: "live_tree", data: tree})
    {:push, {:text, msg}, state}
  end

  defp handle_message(%{"type" => "get_live_state", "cid" => cid}, state) do
    snapshot = LiveStateStore.get_snapshot()

    live_state =
      if snapshot do
        cond do
          cid == "page" && snapshot["page"] ->
            snapshot["page"]

          snapshot["components"] && snapshot["components"][cid] ->
            snapshot["components"][cid]

          true ->
            nil
        end
      end

    if live_state do
      msg = JSON.encode!(%{type: "live_state", data: live_state})
      {:push, {:text, msg}, state}
    else
      msg = JSON.encode!(%{type: "error", data: %{message: "No live state for CID: #{cid}"}})
      {:push, {:text, msg}, state}
    end
  end

  defp handle_message(%{"type" => "edit_state", "cid" => cid, "path" => path, "value" => value}, state) do
    forward_to_bridge(%{type: "edit_state", cid: cid, path: path, value: value})
    msg = JSON.encode!(%{type: "state_edited", data: %{cid: cid, path: path}})
    {:push, {:text, msg}, state}
  end

  defp handle_message(%{"type" => "dispatch_action", "target" => target, "name" => name} = message, state) do
    params = Map.get(message, "params", %{})
    forward_to_bridge(%{type: "dispatch_action", target: target, name: name, params: params})
    {:ok, state}
  end

  defp handle_message(%{"type" => "get_action_history"} = message, state) do
    limit = Map.get(message, "limit", 200)
    actions = LiveStateStore.get_actions(limit)
    msg = JSON.encode!(%{type: "action_history", data: actions})
    {:push, {:text, msg}, state}
  end

  defp handle_message(%{"type" => "open_in_editor", "file" => file} = message, state) do
    line = Map.get(message, "line", 1)
    editor = Application.get_env(:holo_dev, :editor, "code")
    path = Path.expand(file, File.cwd!())

    Task.start(fn ->
      System.cmd(editor, ["--goto", "#{path}:#{line}"], stderr_to_stdout: true)
    end)

    msg = JSON.encode!(%{type: "editor_opened", data: %{file: file, line: line}})
    {:push, {:text, msg}, state}
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

  defp build_component_tree(pages, components, route) do
    component_lookup =
      components
      |> Enum.into(%{}, fn {name, info} ->
        {short_name(name), {name, info}}
      end)

    filtered_pages =
      if route do
        Enum.filter(pages, fn {_name, info} -> Map.get(info, :route) == route end)
      else
        Enum.into(pages, [])
      end

    page_nodes =
      filtered_pages
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map(fn {name, page_info} ->
        layout_module = Map.get(page_info, :layoutModule)

        # Always use static template structure for the tree
        children = build_page_children(layout_module, page_info, component_lookup)

        %{
          id: name,
          name: short_name(name),
          type: "page",
          route: Map.get(page_info, :route),
          file: page_info[:file],
          children: children
        }
      end)

    %{root: %{id: "root", name: "Application", type: "root", children: page_nodes}}
  end

  defp build_page_children(nil, page_info, component_lookup) do
    build_template_children(page_info, component_lookup)
  end

  defp build_page_children(layout_module_name, page_info, component_lookup) do
    layout_info = lookup_info(layout_module_name, component_lookup)
    layout_template_components = Map.get(layout_info, :templateComponents, [])

    {runtime_comps, regular_comps} =
      Enum.split_with(layout_template_components, fn name -> name == "Runtime" end)

    runtime_nodes = Enum.map(runtime_comps, &make_node(&1, component_lookup, "runtime"))
    layout_own = Enum.map(regular_comps, &make_node(&1, component_lookup, "component"))
    page_children = build_template_children(page_info, component_lookup)

    layout_node = %{
      id: layout_module_name,
      name: short_name(layout_module_name),
      type: "layout",
      file: layout_info[:file],
      children: layout_own ++ page_children
    }

    runtime_nodes ++ [layout_node]
  end

  defp build_template_children(info, component_lookup) do
    Map.get(info, :templateComponents, [])
    |> Enum.map(&make_node(&1, component_lookup, "component"))
  end

  defp make_node(comp_name, component_lookup, default_type) do
    case Map.get(component_lookup, comp_name) do
      {full_name, info} ->
        type = if comp_name == "Runtime", do: "runtime", else: default_type
        %{id: full_name, name: comp_name, type: type, file: info[:file], children: []}
      nil ->
        %{id: comp_name, name: comp_name, type: default_type, children: []}
    end
  end

  defp lookup_info(module_name, component_lookup) do
    case Map.get(component_lookup, short_name(module_name)) do
      {_full, info} -> info
      nil -> %{}
    end
  end

  # For stateless components (no CID), try to resolve their props
  # by looking at the page template's prop bindings and the page's live state
  defp maybe_resolve_props_from_state(data, component_module_name) do
    comp_short = short_name(component_module_name)
    pages = Store.pages()

    # Find which page(s) use this component and what props they pass
    resolved =
      Enum.find_value(pages, fn {page_name, page_info} ->
        bindings = Map.get(page_info, :templatePropBindings, %{})

        case Map.get(bindings, comp_short) do
          nil -> nil
          instances_bindings when is_list(instances_bindings) ->
            # Get the page's live state
            page_mod =
              try do
                String.to_existing_atom("Elixir." <> page_name)
              rescue
                _ -> nil
              end

            live = page_mod && StateTracker.get_state(page_mod)
            page_state = if live, do: live.page_state, else: %{}

            # Resolve each prop expression against page state
            # instances_bindings is a list of prop binding lists (one per template occurrence)
            resolved_instances =
              Enum.map(instances_bindings, fn prop_bindings ->
                Enum.into(prop_bindings, %{}, fn %{prop: prop_name, expression: expr} ->
                  value = resolve_expression(expr, page_state)
                  {prop_name, value}
                end)
              end)

            resolved_instances
        end
      end)

    if resolved && resolved != [] do
      # If there's only one instance, show its props directly
      # If multiple, show all instances
      live_props =
        case resolved do
          [single] -> single
          multiple -> %{"instances" => multiple}
        end

      Map.put(data, :liveProps, live_props)
    else
      data
    end
  end

  # Resolve a simple expression like "post", "@posts", "post.title" against page state
  defp resolve_expression(expr, page_state) do
    cond do
      # Direct state reference: @key
      String.starts_with?(expr, "@") ->
        key = String.trim_leading(expr, "@")
        Map.get(page_state, key, expr)

      # Simple variable (from a for loop - can't fully resolve)
      Regex.match?(~r/^[a-z_][a-z0-9_]*$/, expr) ->
        expr

      # Module reference or complex expression
      true ->
        expr
    end
  end

  # Get live state/props for a component by its CID or module name
  defp get_live_data_for_component(id) do
    all_state = StateTracker.get_state()

    # First check if it's a page module
    page_mod =
      try do
        String.to_existing_atom("Elixir." <> id)
      rescue
        _ -> nil
      end

    case page_mod && StateTracker.get_state(page_mod) do
      %{page_state: page_state} ->
        {:ok, %{state: page_state}}
      _ ->
        # Search by CID across all pages
        result =
          Enum.find_value(all_state, fn {_page_mod, %{components: components}} ->
            case Map.get(components, id) do
              %{} = inst -> inst
              nil -> nil
            end
          end)

        if result, do: {:ok, result}, else: :error
    end
  rescue
    _ -> :error
  end

  defp short_name(full_name) do
    full_name |> String.split(".") |> List.last()
  end

  # Build a live tree merging static metadata with live snapshot data
  defp build_live_tree(pages, components, snapshot) do
    component_lookup =
      components
      |> Enum.into(%{}, fn {name, info} ->
        {short_name(name), {name, info}}
      end)

    page_nodes =
      pages
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map(fn {name, page_info} ->
        layout_module = Map.get(page_info, :layoutModule)
        children = build_page_children(layout_module, page_info, component_lookup)

        # Merge live CIDs from snapshot
        children = attach_live_cids(children, snapshot)

        # Get page state summary from snapshot
        page_state_summary =
          if snapshot && snapshot["page"] && snapshot["page"]["state"] do
            Map.keys(snapshot["page"]["state"])
          else
            Map.get(page_info, :stateKeys, [])
          end

        %{
          id: name,
          name: short_name(name),
          type: "page",
          route: Map.get(page_info, :route),
          file: page_info[:file],
          cid: "page",
          state_keys: page_state_summary,
          children: children
        }
      end)

    %{
      root: %{id: "root", name: "Application", type: "root", children: page_nodes},
      bridge_connected: LiveStateStore.bridge_connected?(),
      snapshot_timestamp: snapshot && snapshot["timestamp"]
    }
  end

  # Attach live CIDs from the snapshot to the static tree nodes
  defp attach_live_cids(children, nil), do: children

  defp attach_live_cids(children, snapshot) do
    live_components = snapshot["components"] || %{}

    # Build a lookup of module name -> list of CIDs
    cids_by_module =
      Enum.group_by(
        live_components,
        fn {_cid, comp} -> comp["module"] end,
        fn {cid, _comp} -> cid end
      )

    Enum.map(children, fn node ->
      module_name = node[:id]
      short = node[:name]

      # Try to find CIDs for this component
      cids =
        Map.get(cids_by_module, module_name, []) ++
          Map.get(cids_by_module, short, [])

      state_keys =
        case cids do
          [first_cid | _] ->
            comp = live_components[first_cid]
            if comp && comp["state"], do: Map.keys(comp["state"]), else: []
          [] ->
            []
        end

      node
      |> Map.put(:cids, cids)
      |> Map.put(:state_keys, state_keys)
      |> Map.update(:children, [], &attach_live_cids(&1, snapshot))
    end)
  end

  defp forward_to_bridge(message) do
    Registry.dispatch(HoloDev.BridgeRegistry, :bridge, fn entries ->
      for {pid, _value} <- entries do
        send(pid, {:forward_to_bridge, message})
      end
    end)
  rescue
    _ -> :ok
  end
end
