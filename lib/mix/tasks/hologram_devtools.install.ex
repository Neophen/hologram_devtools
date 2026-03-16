if Code.ensure_loaded?(Igniter.Mix.Task) do
  defmodule Mix.Tasks.HologramDevtools.Install do
    @moduledoc """
    Installs HologramDevtools into your project.

        mix igniter.install hologram_devtools

    This will:
    - Add `{:hologram_devtools, "~> 0.1", only: :dev}` to your deps
    - Add `.hologram/` to your `.gitignore`
    """
    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :hologram_devtools,
        adds_deps: [{:hologram_devtools, "~> 0.1"}]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter
      |> Igniter.Project.Deps.add_dep({:hologram_devtools, "~> 0.1", only: :dev})
      |> add_to_gitignore()
    end

    defp add_to_gitignore(igniter) do
      gitignore_path = ".gitignore"

      case Igniter.exists?(igniter, gitignore_path) do
        true ->
          Igniter.update_file(igniter, gitignore_path, fn source ->
            if String.contains?(source, ".hologram/") do
              source
            else
              String.trim_trailing(source) <> "\n\n# Hologram DevTools\n.hologram/\n"
            end
          end)

        false ->
          Igniter.create_new_file(igniter, gitignore_path, "# Hologram DevTools\n.hologram/\n")
      end
    end
  end
end
