defmodule HologramDevtools.Introspection.SourceParserTest do
  use ExUnit.Case

  alias HologramDevtools.Introspection.SourceParser

  @fixture_dir Path.join([__DIR__, "..", "support", "fixtures"]) |> Path.expand()

  setup do
    File.mkdir_p!(@fixture_dir)

    fixture_path = Path.join(@fixture_dir, "sample_module.ex")

    File.write!(fixture_path, """
    defmodule MyApp.SamplePage do
      use Hologram.Page

      route "/sample/:id"

      prop :name, :string
      prop :place, Place

      def init(params, component, _server) do
        put_state(component, :count, 0)
        put_state(component, loading: true, name: "test")
        put_state(component, %{items: []})
      end

      def template do
        ~H\"\"\"
        <div>Hello</div>
        \"\"\"
      end

      def action(:increment, params, component) do
        step = params.step
        value = params[:value]
        put_state(component, :count, step + value)
      end

      def action(:reset, _params, component) do
        put_state(component, :count, 0)
      end

      def command(:save, params, component) do
        data = params.data
      end

      def page_title do
        "Sample"
      end
    end
    """)

    on_exit(fn -> File.rm(fixture_path) end)

    %{fixture_path: fixture_path}
  end

  test "make_relative/1 converts absolute path to relative" do
    cwd = File.cwd!()
    abs_path = Path.join(cwd, "lib/my_app/page.ex")
    assert SourceParser.make_relative(abs_path) == "lib/my_app/page.ex"
  end

  test "make_relative/1 returns path as-is if not under cwd" do
    assert SourceParser.make_relative("/other/path/file.ex") == "/other/path/file.ex"
  end

  test "find_defmodule_line/2 finds the correct line", %{fixture_path: path} do
    assert SourceParser.find_defmodule_line(path, MyApp.SamplePage) == 1
  end

  test "find_pattern_line/2 finds def template", %{fixture_path: path} do
    line = SourceParser.find_pattern_line(path, ~r/^\s*def\s+template\b/)
    assert line == 15
  end

  test "find_pattern_line/2 finds def init", %{fixture_path: path} do
    line = SourceParser.find_pattern_line(path, ~r/^\s*def\s+init\b/)
    assert line == 9
  end

  test "extract_state_keys/1 extracts all state key patterns", %{fixture_path: path} do
    keys = SourceParser.extract_state_keys(path) |> Enum.sort()
    assert "count" in keys
    assert "loading" in keys
    assert "name" in keys
    assert "items" in keys
  end

  test "extract_params_info/3 detects used params", %{fixture_path: path} do
    {uses_params, params} = SourceParser.extract_params_info(path, :action, "increment")
    assert uses_params
    assert "step" in params
    assert "value" in params
  end

  test "extract_params_info/3 detects unused params", %{fixture_path: path} do
    {uses_params, params} = SourceParser.extract_params_info(path, :action, "reset")
    refute uses_params
    assert params == []
  end
end
