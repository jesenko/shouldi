defmodule ShouldI.Having do
  @moduledoc false

  def having(_env, context, [do: block]) do
    quote1 =
      quote do
        import ExUnit.Callbacks, except: [setup: 1, setup: 2]
        import ExUnit.Case, except: [test: 2, test: 3]
        import ShouldI, except: [setup: 1, setup: 2]
        import ShouldI.Having

        matchers = @shouldi_matchers
        path     = @shouldi_having_path
        @shouldi_having_path [unquote(context)|path]
        @shouldi_matchers  []

        unquote(block)
      end

    quote2 =
      quote unquote: false do
        var!(define_matchers, ShouldI).()
        @shouldi_having_path path
        @shouldi_matchers Macro.escape(matchers)
      end

    quote do
      # Do not leak imports
      try do
        unquote(quote1)
        unquote(quote2)
      after
        :ok
      end
    end
  end

  defmacro test(name, var \\ quote(do: _), opts) do
    quote do
      @tag shouldi_having_path: Enum.reverse(@shouldi_having_path)
      ExUnit.Case.test(test_name(__MODULE__, unquote(name)), unquote(var), unquote(opts))
    end
  end

  defmacro setup(var \\ quote(do: context), [do: block]) do
    if_quote =
      quote unquote: false do
        starts_with?(unquote(shouldi_having_path), shouldi_path)
      end

    quote do
      shouldi_having_path = Enum.reverse(@shouldi_having_path)
      ExUnit.Callbacks.setup unquote(var) do
        shouldi_path = unquote(var)[:shouldi_having_path] || []

        if unquote(if_quote) do
          case unquote(block) do
            :ok -> :ok
            {:ok, list} -> {:ok, list}
            map  -> {:ok, map}
          end
        else
          :ok
        end
      end
    end
  end

  @avail_test_name_length 255 - byte_size("test having '")

  def test_name(module, name) do
    path = Module.get_attribute(module, :shouldi_having_path)
    full_name = path_to_name(path) <> "': " <> name
    trunc_name =
      case full_name do
        str when byte_size(str) <= @avail_test_name_length -> str
        str -> "..." <> (str |> String.slice(-(@avail_test_name_length - 3)..-1))
      end
    "having '" <> trunc_name
  end

  defp path_to_name(path) do
    Enum.reverse(path)
    |> Enum.join(" AND ")
  end

  def starts_with?([], _),
    do: true

  def starts_with?([elem|left], [elem|right]),
    do: starts_with?(left, right)

  def starts_with?(_, _),
    do: false

  def prepare_matchers(matchers) do
    Enum.map(matchers, fn {call, meta, code} ->
      code = Macro.prewalk(code, fn ast ->
        Macro.update_meta(ast, &Keyword.merge(&1, meta))
      end)

      quote do
        try do
          unquote(code)
          nil
        catch
          kind, error ->
            stacktrace = System.stacktrace
            {unquote(Macro.escape(call)), {kind, error, stacktrace}}
        end
      end
    end)
  end
end
