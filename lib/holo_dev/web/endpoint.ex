defmodule HoloDev.Web.Endpoint do
  @moduledoc false
  use Plug.Router

  plug :cors
  plug Plug.Logger, log: :debug
  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: JSON
  plug :dispatch

  defp cors(conn, _opts) do
    conn
    |> Plug.Conn.put_resp_header("access-control-allow-origin", "*")
    |> Plug.Conn.put_resp_header("access-control-allow-methods", "GET, OPTIONS")
    |> Plug.Conn.put_resp_header("access-control-allow-headers", "content-type")
  end

  get "/ws" do
    conn
    |> Plug.Conn.upgrade_adapter(:websocket, {HoloDev.Web.WebSocketHandler, [], []})
  end

  get "/bridge" do
    conn
    |> Plug.Conn.upgrade_adapter(:websocket, {HoloDev.Web.BridgeHandler, [], []})
  end

  get "/bridge.js" do
    bridge_path = :code.priv_dir(:holo_dev) |> to_string() |> Path.join("bridge.js")

    if File.exists?(bridge_path) do
      conn
      |> put_resp_content_type("application/javascript")
      |> send_resp(200, File.read!(bridge_path))
    else
      send_resp(conn, 404, "bridge.js not found")
    end
  end

  get "/" do
    pages = HoloDev.Introspection.Store.pages()
    components = HoloDev.Introspection.Store.components()
    resources = HoloDev.Introspection.Store.resources()

    html = render_overview(pages, components, resources)
    send_resp(conn, 200, html)
  end

  get "/api/pages" do
    data = HoloDev.Introspection.Store.pages()
    send_json(conn, data)
  end

  get "/api/components" do
    data = HoloDev.Introspection.Store.components()
    send_json(conn, data)
  end

  get "/api/resources" do
    data = HoloDev.Introspection.Store.resources()
    send_json(conn, data)
  end

  get "/api/modules" do
    data = HoloDev.Introspection.Store.modules()
    send_json(conn, data)
  end

  get "/api/overview" do
    pages = HoloDev.Introspection.Store.pages()
    components = HoloDev.Introspection.Store.components()
    resources = HoloDev.Introspection.Store.resources()

    overview = %{
      version: HoloDev.version(),
      pages: map_size(pages),
      components: map_size(components),
      resources: map_size(resources)
    }

    send_json(conn, overview)
  end

  get "/health" do
    send_json(conn, %{status: "ok", version: HoloDev.version()})
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  defp send_json(conn, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, JSON.encode!(data))
  end

  defp render_overview(pages, components, resources) do
    page_count = map_size(pages)
    component_count = map_size(components)
    resource_count = map_size(resources)

    pages_html =
      pages
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map(fn {name, info} ->
        route = Map.get(info, :route, "—")
        props = info |> Map.get(:props, []) |> length()
        actions = info |> Map.get(:actions, []) |> length()
        commands = info |> Map.get(:commands, []) |> length()

        """
        <tr>
          <td><code>#{escape(name)}</code></td>
          <td><code>#{escape(to_string(route))}</code></td>
          <td>#{props}</td>
          <td>#{actions}</td>
          <td>#{commands}</td>
          <td><code>#{escape(info[:file] || "—")}</code></td>
        </tr>
        """
      end)
      |> Enum.join()

    components_html =
      components
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map(fn {name, info} ->
        props = info |> Map.get(:props, []) |> length()
        actions = info |> Map.get(:actions, []) |> length()

        """
        <tr>
          <td><code>#{escape(name)}</code></td>
          <td>#{props}</td>
          <td>#{actions}</td>
          <td><code>#{escape(info[:file] || "—")}</code></td>
        </tr>
        """
      end)
      |> Enum.join()

    resources_html =
      resources
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map(fn {name, info} ->
        attrs = info |> Map.get(:attributes, []) |> length()
        rels = info |> Map.get(:relationships, []) |> length()

        """
        <tr>
          <td><code>#{escape(name)}</code></td>
          <td>#{attrs}</td>
          <td>#{rels}</td>
          <td><code>#{escape(info[:file] || "—")}</code></td>
        </tr>
        """
      end)
      |> Enum.join()

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Hologram DevTools</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0f172a; color: #e2e8f0; padding: 2rem; }
        h1 { font-size: 1.5rem; margin-bottom: 0.5rem; color: #38bdf8; }
        .subtitle { color: #94a3b8; margin-bottom: 2rem; }
        .stats { display: flex; gap: 1rem; margin-bottom: 2rem; }
        .stat { background: #1e293b; border-radius: 8px; padding: 1.5rem; flex: 1; text-align: center; }
        .stat-value { font-size: 2rem; font-weight: 700; color: #38bdf8; }
        .stat-label { color: #94a3b8; font-size: 0.875rem; margin-top: 0.25rem; }
        h2 { font-size: 1.125rem; margin: 1.5rem 0 0.75rem; color: #f1f5f9; }
        table { width: 100%; border-collapse: collapse; background: #1e293b; border-radius: 8px; overflow: hidden; margin-bottom: 1.5rem; }
        th { text-align: left; padding: 0.75rem 1rem; background: #334155; color: #94a3b8; font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.05em; }
        td { padding: 0.5rem 1rem; border-top: 1px solid #334155; font-size: 0.875rem; }
        code { font-family: 'JetBrains Mono', 'Fira Code', monospace; font-size: 0.8125rem; }
        .empty { color: #64748b; padding: 2rem; text-align: center; }
        .version { color: #64748b; font-size: 0.75rem; margin-top: 2rem; }
        .api-links { margin-top: 1rem; }
        .api-links a { color: #38bdf8; text-decoration: none; margin-right: 1rem; font-size: 0.875rem; }
        .api-links a:hover { text-decoration: underline; }
      </style>
    </head>
    <body>
      <h1>Hologram DevTools</h1>
      <p class="subtitle">v#{HoloDev.version()}</p>

      <div class="stats">
        <div class="stat">
          <div class="stat-value">#{page_count}</div>
          <div class="stat-label">Pages</div>
        </div>
        <div class="stat">
          <div class="stat-value">#{component_count}</div>
          <div class="stat-label">Components</div>
        </div>
        <div class="stat">
          <div class="stat-value">#{resource_count}</div>
          <div class="stat-label">Resources</div>
        </div>
      </div>

      <h2>Pages</h2>
      #{if page_count > 0 do
        """
        <table>
          <thead><tr><th>Module</th><th>Route</th><th>Props</th><th>Actions</th><th>Commands</th><th>File</th></tr></thead>
          <tbody>#{pages_html}</tbody>
        </table>
        """
      else
        "<div class=\"empty\">No Hologram pages detected</div>"
      end}

      <h2>Components</h2>
      #{if component_count > 0 do
        """
        <table>
          <thead><tr><th>Module</th><th>Props</th><th>Actions</th><th>File</th></tr></thead>
          <tbody>#{components_html}</tbody>
        </table>
        """
      else
        "<div class=\"empty\">No Hologram components detected</div>"
      end}

      <h2>Resources</h2>
      #{if resource_count > 0 do
        """
        <table>
          <thead><tr><th>Module</th><th>Attributes</th><th>Relationships</th><th>File</th></tr></thead>
          <tbody>#{resources_html}</tbody>
        </table>
        """
      else
        "<div class=\"empty\">No Ash resources detected</div>"
      end}

      <div class="api-links">
        <strong style="color: #94a3b8; font-size: 0.75rem;">JSON API:</strong>
        <a href="/api/pages">pages</a>
        <a href="/api/components">components</a>
        <a href="/api/resources">resources</a>
        <a href="/api/modules">modules</a>
        <a href="/api/overview">overview</a>
      </div>

      <p class="version">Auto-refreshes on file changes. JSON files at <code>#{HoloDev.output_dir()}/</code></p>
    </body>
    </html>
    """
  end

  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
