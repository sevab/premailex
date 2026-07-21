if Code.ensure_loaded?(Meeseeks) do
  defmodule Premailex.HTMLParser.Meeseeks do
    @moduledoc """
    HTML parser implementation using Meeseeks.

    Add `Meeseeks` to your dependencies in `mix.exs` to use this parser:

        defp deps do
          [
            {:meeseeks, "~> 0.11"}
          ]
        end
    """
    @behaviour Premailex.HTMLParser

    @impl true
    @doc false
    def parse(html) do
      case Meeseeks.parse(html) do
        %Meeseeks.Document{} = document ->
          document
          |> Meeseeks.tree()
          |> unwrap_fragment(html)

        {:error, reason} ->
          raise ArgumentError, "Meeseeks failed to parse HTML: #{inspect(reason)}"
      end
    end

    # Meeseeks wraps fragments in an <html> element, so we unwrap it if the
    # input was a fragment.
    defp unwrap_fragment(tree, html) do
      case Regex.match?(~r/<html/i, html) do
        true ->
          tree

        false ->
          # Head level content, such as <style>, <meta>, <link> and <title>, is
          # parsed into the <head> element, so the children of both <head> and
          # <body> are kept. Source order is preserved as <head> always precedes
          # <body>.
          Enum.flat_map(tree, &unwrap_fragment_node/1)
      end
    end

    defp unwrap_fragment_node({"html", _attrs, children}),
      do: Enum.flat_map(children, &unwrap_fragment_node/1)

    defp unwrap_fragment_node({tag, _attrs, children}) when tag in ["head", "body"],
      do: children

    defp unwrap_fragment_node(node), do: [node]

    @impl true
    @doc false
    def to_html(tree) do
      wrap_fragment(tree, fn tree ->
        tree
        |> Meeseeks.parse(:tuple_tree)
        |> Meeseeks.html()
      end)
    end

    @premailex_root "premailex-root"

    defp wrap_fragment(tree, fun) do
      case document?(tree) do
        true -> fun.(tree)
        false -> do_wrap_fragment(tree, fun)
      end
    end

    defp document?([]), do: false
    defp document?([{"html", _attrs, _children} | _]), do: true
    defp document?([_other | nodes]), do: document?(nodes)

    defp do_wrap_fragment(tree, fun) do
      html = fun.([{@premailex_root, [], tree}])
      [_, html] = Regex.run(~r/<#{@premailex_root}>(.*)<\/#{@premailex_root}>/s, html)

      html
    end
  end
end
