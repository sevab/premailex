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
      html
      |> Meeseeks.parse()
      |> Meeseeks.tree()
      |> unwrap_fragment(html)
    end

    # Meeseeks wraps all fragments in an <html> element, so we need to unwrap
    # it if the input was just a fragment.
    defp unwrap_fragment(tree, html) do
      case Regex.match?(~r/<html/i, html) do
        true ->
          tree

        false ->
          # This may break if Meeseeks changes how it wraps fragments. If it
          # does this should be moved into a function that handles the
          # different versions of Meeseeks.
          [{"html", [], [{"head", [], []}, {"body", [], fragment}]}] = tree

          fragment
      end
    end

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
