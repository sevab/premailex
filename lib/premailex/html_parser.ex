defmodule Premailex.HTMLParser do
  @moduledoc """
  Behaviour for HTML parsing.

  By default Premailex prefers `LazyHTML`, then `Floki`, then `Meeseeks`,
  falling back to the built-in `Premailex.HTMLParser.Xmerl` when none of
  them is loaded. The active parser can be configured:

      config :premailex, html_parser: Premailex.HTMLParser.LazyHTML
  """

  @doc """
  Parses an HTML string into a `t:Premailex.html_tree/0`.

  Adapters raise `ArgumentError` when the input cannot be parsed.
  """
  @callback parse(Premailex.html()) :: Premailex.html_tree()

  @doc """
  Serialises a `t:Premailex.html_tree/0` back into an HTML string.
  """
  @callback to_html(Premailex.html_tree()) :: Premailex.html()
end
