if Code.ensure_loaded?(Floki) do
  defmodule Premailex.HTMLParser.Floki do
    @moduledoc """
    HTML parser implementation using Floki.

    Add `Floki` to your dependencies in `mix.exs` to use this parser:

        defp deps do
          [
            {:floki, "~> 0.24"}
          ]
        end
    """

    @behaviour Premailex.HTMLParser

    @impl true
    @doc false
    def parse(html) do
      html
      |> retain_inline_whitespace()
      |> Floki.parse_document()
      |> case do
        {:ok, document} ->
          document

        {:error, reason} ->
          raise ArgumentError, "Floki failed to parse HTML: #{inspect(reason)}"
      end
    end

    # Floki strips whitespace text nodes between tags which causes errors like:
    # https://github.com/mochi/mochiweb/issues/166
    # To prevent that and preserve whitespaces this encodes each whitespace
    # character as a numeric HTML entity so Floki's parser treats them as
    # content and preserves them. This keeps it consistent with the other
    # HTML parsers.
    defp retain_inline_whitespace(html) do
      Regex.replace(~r/>(\s+)</, html, fn _full, whitespace ->
        encoded = for <<char <- whitespace>>, into: "", do: "&##{char};"

        ">#{encoded}<"
      end)
    end

    @impl true
    @doc false
    def to_html(tree), do: Floki.raw_html(tree)
  end
end
