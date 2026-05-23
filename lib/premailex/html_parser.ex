defmodule Premailex.HTMLParser do
  @moduledoc """
  Behaviour for HTML parsing.

  By default Premailex prefers LazyHTML, then Floki, then Meeseeks,
  falling back to the built-in `Premailex.HTMLParser.Xmerl` when none of
  them is loaded. The active parser can be configured:

      config :premailex, html_parser: Premailex.HTMLParser.LazyHTML
  """

  @callback parse(Premailex.html()) :: Premailex.html_tree()
  @callback to_html(Premailex.html_tree()) :: Premailex.html()
end
