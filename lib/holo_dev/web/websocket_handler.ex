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
    # Check for loop instance ID format: "ModuleName#index"
    {base_id, instance_index} = parse_instance_id(id)

    pages = Store.pages()
    components = Store.components()

    # Try to find component info by module name first, then by CID
    data =
      case Map.get(pages, base_id) do
        nil -> Map.get(components, base_id)
        page -> page
      end

    # If not found by module name, try to find by CID from live data
    {data, _resolved_module} =
      if data do
        {data, base_id}
      else
        case get_live_data_for_component(base_id) do
          {:ok, %{module: mod_name}} ->
            static_data = Map.get(components, mod_name, %{})
            {static_data, mod_name}
          _ ->
            {nil, base_id}
        end
      end

    if data do
      data = Map.put(data, :id, id)

      # If this is a loop instance, resolve its props
      data =
        if instance_index != nil do
          resolve_loop_instance_props(data, base_id, instance_index, pages)
        else
          # Attach live state for pages
          case get_live_data_for_component(base_id) do
            {:ok, %{state: live_state, props: live_props}} ->
              data |> Map.put(:state, live_state) |> Map.put(:liveProps, live_props)

            {:ok, %{state: live_state}} ->
              Map.put(data, :state, live_state)

            _ ->
              data |> maybe_resolve_props_from_state(base_id)
          end
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
    {base_id, instance_index} = parse_instance_id(cid)

    # If it's a loop instance, resolve from page state
    if instance_index != nil do
      pages = Store.pages()
      components = Store.components()
      static_data = Map.get(components, base_id) || %{}

      result =
        %{
          "module" => base_id,
          "cid" => cid,
          "actions" => Map.get(static_data, :actions, []),
          "commands" => Map.get(static_data, :commands, []),
          "props" => Map.get(static_data, :props, []),
          "functions" => Map.get(static_data, :functions, []),
          "file" => Map.get(static_data, :file),
          "line" => Map.get(static_data, :line)
        }

      # Resolve instance props
      result = resolve_loop_instance_props(result, base_id, instance_index, pages)

      msg = JSON.encode!(%{type: "live_state", data: result})
      {:push, {:text, msg}, state}
    else
      snapshot = LiveStateStore.get_snapshot()
      live_state = resolve_live_state(base_id, snapshot)

      if live_state do
        module_name = live_state["module"]

        static_data =
          if module_name do
            Map.get(Store.pages(), module_name) || Map.get(Store.components(), module_name) || %{}
          else
            %{}
          end

        merged = Map.merge(
          %{
            "actions" => Map.get(static_data, :actions, []),
            "commands" => Map.get(static_data, :commands, []),
            "props" => Map.get(static_data, :props, []),
            "functions" => Map.get(static_data, :functions, []),
            "file" => Map.get(static_data, :file),
            "line" => Map.get(static_data, :line)
          },
          live_state
        )

        msg = JSON.encode!(%{type: "live_state", data: merged})
        {:push, {:text, msg}, state}
      else
        msg = JSON.encode!(%{type: "error", data: %{message: "No live state for: #{cid}"}})
        {:push, {:text, msg}, state}
      end
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

  defp build_template_children(info, component_lookup, depth \\ 0)

  defp build_template_children(_info, _component_lookup, depth) when depth > 10, do: []

  defp build_template_children(info, component_lookup, depth) do
    template_structure = Map.get(info, :templateStructure, %{})

    Map.get(info, :templateComponents, [])
    |> Enum.flat_map(fn comp_name ->
      case Map.get(template_structure, comp_name) do
        entries when is_list(entries) and entries != [] ->
          loop_entry = Enum.find(entries, fn e -> e[:loop] != nil end)

          if loop_entry do
            expand_loop_component(comp_name, loop_entry, component_lookup, info, depth)
          else
            [make_node(comp_name, component_lookup, "component", depth)]
          end

        _ ->
          [make_node(comp_name, component_lookup, "component", depth)]
      end
    end)
  end

  # Expand a loop component into N nodes based on page state
  defp expand_loop_component(comp_name, %{loop: %{source: source_key, iterator: iterator}, bindings: bindings}, component_lookup, page_info, depth) do
    # Try to get the list from page state
    items = get_page_state_list(source_key, page_info)

    case items do
      items when is_list(items) and items != [] ->
        {full_name, comp_info} =
          case Map.get(component_lookup, comp_name) do
            {name, info} -> {name, info}
            nil -> {comp_name, %{}}
          end

        items
        |> Enum.with_index()
        |> Enum.map(fn {item, idx} ->
          # Resolve props: substitute iterator variable with the list item
          instance_props =
            Enum.into(bindings, %{}, fn %{prop: prop_name, expression: expr} ->
              value =
                if expr == iterator do
                  item
                else
                  resolve_expression(expr, %{})
                end

              {prop_name, value}
            end)

          # Recursively build children from this component's own template
          children = build_template_children(comp_info, component_lookup, depth + 1)

          %{
            id: "#{full_name}##{idx}",
            name: "#{comp_name}[#{idx}]",
            type: "component",
            file: comp_info[:file],
            instance_index: idx,
            instance_props: instance_props,
            loop_source: source_key,
            children: children
          }
        end)

      _ ->
        # State unavailable — fall back to single node
        [make_node(comp_name, component_lookup, "component")]
    end
  end

  # Get a list value from page state (tries bridge snapshot first, then StateTracker)
  defp get_page_state_list(source_key, _page_info) do
    # Try bridge snapshot first
    snapshot = LiveStateStore.get_snapshot()

    bridge_list =
      if snapshot && snapshot["page"] && snapshot["page"]["state"] do
        case snapshot["page"]["state"][source_key] do
          %{"_t" => "list", "v" => items} when is_list(items) ->
            # Unbox typed values to plain maps for display
            Enum.map(items, &unbox_typed_value/1)

          items when is_list(items) ->
            items

          _ ->
            nil
        end
      end

    if bridge_list do
      bridge_list
    else
      # Fall back to StateTracker
      pages = Store.pages()

      page_name =
        Enum.find_value(pages, fn {name, info} ->
          if Map.get(info, :stateKeys, []) |> Enum.member?(source_key), do: name
        end)

      if page_name do
        page_mod =
          try do
            String.to_existing_atom("Elixir." <> page_name)
          rescue
            _ -> nil
          end

        case page_mod && StateTracker.get_state(page_mod) do
          %{page_state: page_state} ->
            case Map.get(page_state, source_key) do
              items when is_list(items) -> items
              _ -> nil
            end

          _ ->
            nil
        end
      end
    end
  end

  # Convert typed values from bridge snapshot to plain display values
  defp unbox_typed_value(%{"_t" => "map", "v" => fields}) when is_map(fields) do
    Map.new(fields, fn {k, v} -> {k, unbox_typed_value(v)} end)
  end

  defp unbox_typed_value(%{"_t" => "struct", "v" => fields, "module" => mod}) when is_map(fields) do
    Map.new(fields, fn {k, v} -> {k, unbox_typed_value(v)} end)
    |> Map.put("__struct__", mod)
  end

  defp unbox_typed_value(%{"_t" => "list", "v" => items}) when is_list(items) do
    Enum.map(items, &unbox_typed_value/1)
  end

  defp unbox_typed_value(%{"_t" => _, "v" => v}), do: v
  defp unbox_typed_value(other), do: other

  defp make_node(comp_name, component_lookup, default_type, depth \\ 0) do
    case Map.get(component_lookup, comp_name) do
      {full_name, info} ->
        type = if comp_name == "Runtime", do: "runtime", else: default_type
        children = build_template_children(info, component_lookup, depth + 1)
        %{id: full_name, name: comp_name, type: type, file: info[:file], children: children}
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

  # Parse "ModuleName#2" → {"ModuleName", 2} or "ModuleName" → {"ModuleName", nil}
  defp parse_instance_id(id) do
    case String.split(id, "#", parts: 2) do
      [base, idx_str] ->
        case Integer.parse(idx_str) do
          {idx, ""} -> {base, idx}
          _ -> {id, nil}
        end

      _ ->
        {id, nil}
    end
  end

  # Resolve props for a specific loop instance
  defp resolve_loop_instance_props(data, module_name, index, pages) do
    comp_short = short_name(module_name)

    # Find which page uses this component and its loop metadata
    Enum.find_value(pages, data, fn {_page_name, page_info} ->
      template_structure = Map.get(page_info, :templateStructure, %{})

      case Map.get(template_structure, comp_short) do
        entries when is_list(entries) ->
          loop_entry = Enum.find(entries, fn e -> e[:loop] != nil end)

          if loop_entry do
            %{loop: %{source: source_key, iterator: iterator}, bindings: bindings} = loop_entry
            items = get_page_state_list(source_key, page_info)

            if is_list(items) && index < length(items) do
              item = Enum.at(items, index)

              instance_props =
                Enum.into(bindings, %{}, fn %{prop: prop_name, expression: expr} ->
                  value = if expr == iterator, do: item, else: expr
                  {prop_name, value}
                end)

              Map.put(data, :instance_props, instance_props)
            else
              data
            end
          end

        _ ->
          nil
      end
    end)
  end

  defp short_name(full_name) do
    full_name |> String.split(".") |> List.last()
  end

  # Resolve live state from the snapshot by CID or module name
  defp resolve_live_state(_id, nil), do: nil

  defp resolve_live_state("page", snapshot) do
    snapshot["page"]
  end

  defp resolve_live_state(id, snapshot) do
    components = snapshot["components"] || %{}

    # Try direct CID lookup first
    case Map.get(components, id) do
      %{} = comp -> comp
      nil ->
        # Try matching by module name (full or short)
        Enum.find_value(components, fn {_cid, comp} ->
          module = comp["module"] || ""

          if module == id || short_name(module) == short_name(id) do
            comp
          end
        end)
    end
  end

  # Build a live tree showing only the currently active page from the snapshot
  defp build_live_tree(pages, components, snapshot) do
    component_lookup =
      components
      |> Enum.into(%{}, fn {name, info} ->
        {short_name(name), {name, info}}
      end)

    live_components = if snapshot, do: snapshot["components"] || %{}, else: %{}

    # Build CID lookup: module name -> list of CIDs
    cids_by_module =
      Enum.group_by(
        live_components,
        fn {_cid, comp} -> comp["module"] end,
        fn {cid, _comp} -> cid end
      )

    # Determine the active page from the snapshot
    active_page_module =
      if snapshot && snapshot["page"] do
        snapshot["page"]["module"]
      end

    # Filter pages to only the active one (or show all if no snapshot)
    filtered_pages =
      if active_page_module do
        Enum.filter(pages, fn {name, _info} ->
          name == active_page_module || short_name(name) == short_name(active_page_module)
        end)
      else
        Enum.into(pages, [])
      end

    page_nodes =
      filtered_pages
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map(fn {name, page_info} ->
        layout_module = Map.get(page_info, :layoutModule)
        children = build_page_children(layout_module, page_info, component_lookup)

        # Attach live CIDs to children
        children = attach_live_cids(children, live_components, cids_by_module)

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
      snapshot_timestamp: snapshot && snapshot["timestamp"],
      active_page: active_page_module
    }
  end

  # Attach live CIDs from the snapshot to the static tree nodes
  defp attach_live_cids(children, live_components, cids_by_module) do
    Enum.map(children, fn node ->
      module_name = node[:id]
      short = node[:name]

      # Try to find CIDs for this component by full module name or short name
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
      |> Map.update(:children, [], &attach_live_cids(&1, live_components, cids_by_module))
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
