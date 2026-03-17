defmodule HoloDev.Introspection.Watcher do
  @moduledoc false
  use GenServer

  @debounce_ms 500

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl GenServer
  def init(_) do
    dirs = watched_dirs()
    {:ok, pid} = FileSystem.start_link(dirs: dirs)
    FileSystem.subscribe(pid)
    {:ok, %{fs_pid: pid, timer: nil}}
  end

  defp watched_dirs do
    cwd = File.cwd!()

    Mix.Project.config()[:elixirc_paths]
    |> Kernel.||([])
    |> Enum.map(&Path.join(cwd, &1))
    |> Enum.filter(&File.dir?/1)
    |> case do
      [] -> [Path.join(cwd, "lib")]
      dirs -> dirs
    end
  end

  @impl GenServer
  def handle_info({:file_event, _pid, {path, _events}}, state) do
    if String.ends_with?(path, ".ex") do
      state = schedule_refresh(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info({:file_event, _pid, :stop}, state) do
    {:noreply, state}
  end

  def handle_info(:do_refresh, state) do
    try do
      Mix.Task.reenable("compile")
      Mix.Task.run("compile", ["--no-deps-check"])
    rescue
      _ -> :ok
    end

    HoloDev.Introspection.Store.refresh()
    IO.puts("[HoloDev] Introspection updated at #{DateTime.utc_now() |> DateTime.to_iso8601()}")

    {:noreply, %{state | timer: nil}}
  end

  defp schedule_refresh(%{timer: nil} = state) do
    timer = Process.send_after(self(), :do_refresh, @debounce_ms)
    %{state | timer: timer}
  end

  defp schedule_refresh(%{timer: timer} = state) do
    Process.cancel_timer(timer)
    new_timer = Process.send_after(self(), :do_refresh, @debounce_ms)
    %{state | timer: new_timer}
  end
end
