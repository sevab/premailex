if Code.ensure_loaded?(LazyHTML) do
  defmodule Premailex.HTMLParser.LazyHTML do
    @moduledoc """
    HTML parser implementation using LazyHTML.

    Add `:lazy_html` to your dependencies in `mix.exs` to use this parser:

        defp deps do
          [
            {:lazy_html, "~> 0.1.11"}
          ]
        end
    """
    @behaviour Premailex.HTMLParser

    @impl true
    @doc false
    def parse(html) do
      ~r/<html/i
      |> Regex.match?(html)
      |> case do
        true -> LazyHTML.from_document(html)
        false -> LazyHTML.from_fragment(html)
      end
      |> LazyHTML.to_tree()
    end

    @impl true
    @doc false
    def to_html(tree) do
      tree
      |> LazyHTML.from_tree()
      |> LazyHTML.to_html()
    end
  end
end
