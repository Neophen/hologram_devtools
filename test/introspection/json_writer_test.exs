defmodule HologramDevtools.Introspection.JsonWriterTest do
  use ExUnit.Case

  alias HologramDevtools.Introspection.JsonWriter

  @test_dir Path.join(System.tmp_dir!(), "hologram_devtools_test_#{:rand.uniform(100_000)}")

  setup do
    File.mkdir_p!(@test_dir)
    on_exit(fn -> File.rm_rf!(@test_dir) end)
    :ok
  end

  test "write/2 creates all four JSON files" do
    data = %{
      pages: %{"MyApp.HomePage" => %{file: "lib/home.ex", line: 1}},
      components: %{"MyApp.Button" => %{file: "lib/button.ex", line: 1}},
      resources: %{"MyApp.User" => %{file: "lib/user.ex", line: 1}},
      modules: %{"MyApp.Utils" => %{file: "lib/utils.ex", line: 1}}
    }

    JsonWriter.write(data, @test_dir)

    for file <- ~w(pages.json components.json resources.json modules.json) do
      path = Path.join(@test_dir, file)
      assert File.exists?(path), "Expected #{file} to exist"

      {:ok, content} = File.read(path)
      assert {:ok, _} = Jason.decode(content), "Expected #{file} to be valid JSON"
    end
  end

  test "write/2 produces correct JSON structure" do
    data = %{
      pages: %{
        "MyApp.HomePage" => %{
          file: "lib/home.ex",
          line: 1,
          route: "/",
          props: [%{name: "id", type: "integer", required: true}],
          actions: [],
          commands: [],
          stateKeys: ["count"],
          functions: []
        }
      },
      components: %{},
      resources: %{},
      modules: %{}
    }

    JsonWriter.write(data, @test_dir)

    {:ok, content} = File.read(Path.join(@test_dir, "pages.json"))
    {:ok, parsed} = Jason.decode(content)

    page = parsed["MyApp.HomePage"]
    assert page["file"] == "lib/home.ex"
    assert page["line"] == 1
    assert page["route"] == "/"
    assert page["stateKeys"] == ["count"]
    assert [%{"name" => "id", "type" => "integer", "required" => true}] = page["props"]
  end
end
