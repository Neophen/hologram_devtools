defmodule HoloDev.Introspection.ComponentExtractor do
  @moduledoc false

  alias HoloDev.Introspection.SourceParser

  def extract(modules) do
    modules
    |> Enum.filter(&component?/1)
    |> Enum.map(&extract_component/1)
    |> Enum.into(%{})
  end

  defp component?(mod) do
    Code.ensure_loaded?(mod) and
      function_exported?(mod, :__using__, 0) and
      try do
        mod.__using__() == Hologram.Component
      rescue
        _ -> false
      end
  end

  defp extract_component(mod) do
    name = mod |> to_string() |> String.replace_leading("Elixir.", "")
    source = SourceParser.get_source_file(mod)
    relative_path = if source, do: SourceParser.make_relative(source)
    mod_line = if source, do: SourceParser.find_defmodule_line(source, mod), else: 1

    props = extract_props(mod)
    actions = extract_action_command_info(mod, source, :action)
    commands = extract_action_command_info(mod, source, :command)

    template_line = if source, do: SourceParser.find_pattern_line(source, ~r/^\s*def\s+template\b/)
    init_line = if source, do: SourceParser.find_pattern_line(source, ~r/^\s*def\s+init\b/)
    functions = extract_functions(mod, source)

    result = %{
      file: relative_path,
      line: mod_line,
      props: props,
      actions: actions,
      commands: commands,
      functions: functions
    }

    result = if template_line, do: Map.put(result, :templateLine, template_line), else: result
    result = if init_line, do: Map.put(result, :initLine, init_line), else: result

    {name, result}
  end

  defp extract_props(mod) do
    mod.__props__()
    |> Enum.map(fn {prop_name, prop_type, opts} ->
      resolved_type =
        case prop_type do
          type when is_atom(type) ->
            if function_exported?(type, :__info__, 1) do
              type |> to_string() |> String.replace_leading("Elixir.", "")
            else
              inspect(type)
            end

          other ->
            inspect(other)
        end

      %{
        name: prop_name,
        type: resolved_type,
        required: !Keyword.has_key?(opts, :default)
      }
    end)
  rescue
    _ -> []
  end

  defp extract_action_command_info(mod, source, func_name) do
    arity = 3

    names =
      case Code.fetch_docs(mod) do
        {:docs_v1, _, _, _, _, _, docs} ->
          docs
          |> Enum.filter(fn
            {{:function, ^func_name, ^arity}, _, _, _, _} -> true
            _ -> false
          end)
          |> Enum.flat_map(fn {{:function, _, _}, _, signatures, _, _} ->
            signatures
            |> Enum.flat_map(fn sig ->
              case Regex.run(~r/#{func_name}\(:(\w+)/, sig) do
                [_, name] -> [name]
                _ -> []
              end
            end)
          end)

        _ ->
          []
      end

    Enum.map(names, fn name ->
      line =
        if source do
          SourceParser.find_pattern_line(source, ~r/^\s*def\s+#{func_name}\s*\(\s*:#{name}\b/)
        end

      {uses_params, params} =
        if source do
          SourceParser.extract_params_info(source, func_name, name)
        else
          {false, []}
        end

      %{
        name: name,
        line: line || 0,
        usesParams: uses_params,
        params: params
      }
    end)
  end

  defp extract_functions(mod, source) do
    skip = [:__using__, :__props__, :template, :init, :action, :command]

    mod.__info__(:functions)
    |> Enum.reject(fn {name, _arity} -> name in skip end)
    |> Enum.reject(fn {name, _arity} -> String.starts_with?(to_string(name), "__") end)
    |> Enum.map(fn {name, arity} ->
      line =
        if source do
          SourceParser.find_pattern_line(source, ~r/^\s*def\s+#{name}\s*[\(]/)
        end

      %{name: to_string(name), line: line || 0, arity: arity}
    end)
  rescue
    _ -> []
  end
end
