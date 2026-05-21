defmodule Premailex.HTMLInlineStyles do
  @moduledoc """
  Module that processes inline styling in HTML.
  """
  require Logger

  alias Premailex.{CSSParser, HTMLParser, Util}

  @type html_or_html_tree() :: String.t() | HTMLParser.html_tree()
  @type css_rules_or_options() :: [CSSParser.rule()] | keyword()

  @doc """
  Processes an HTML string adding inline styles.

  Options:
    * `:css_selector` - the style tags to be processed for inline styling, defaults to `style,link[rel="stylesheet"][href]`
    * `:optimize` - list or atom option for optimizing the output. The following values can be used:
      * `:none` - no optimization (default)
      * `:all` - apply all optimization steps
      * `:remove_style_tags` - Remove style tags (can be combined in a list)
  """
  @spec process(html_or_html_tree(), css_rules_or_options() | nil, keyword() | nil) ::
          String.t()
  def process(html_or_tree, css_rules_or_options \\ nil, options \\ nil)

  def process(html, css_rules_or_options, options) when is_binary(html) do
    html
    |> HTMLParser.parse()
    |> process(css_rules_or_options, options)
  end

  def process(tree, css_rules_or_options, nil) do
    case Keyword.keyword?(css_rules_or_options) do
      true -> process(tree, nil, css_rules_or_options)
      false -> process(tree, css_rules_or_options, [])
    end
  end

  def process(tree, nil, options) do
    css_selector = Keyword.get(options, :css_selector, "style,link[rel=\"stylesheet\"][href]")
    css_rules = load_styles(tree, css_selector)
    options = Keyword.put_new(options, :css_selector, css_selector)

    process(tree, css_rules, options)
  end

  def process(tree, css_rules, options) do
    optimize_steps = Keyword.get(options, :optimize, :none)
    optimize_options = Keyword.take(options, [:css_selector])

    css_rules
    |> apply_styles(tree)
    |> normalize_styles()
    |> optimize(optimize_steps, optimize_options)
    |> remove_empty_comments()
    |> HTMLParser.to_string()
  end

  defp load_styles(tree, css_selector) do
    tree
    |> HTMLParser.all(css_selector)
    |> Enum.map(&load_css(&1))
    |> Enum.filter(&(!is_nil(&1)))
    |> Enum.reduce([], &Enum.concat(&1, &2))
  end

  defp apply_styles(styles, tree) do
    hidden_elements =
      tree
      |> HTMLParser.all("head")
      |> Enum.reduce([], fn element, acc ->
        index = to_string(length(acc))

        acc ++ [{index, element, {"premailex", [{"data-index", index}], []}}]
      end)

    visible_tree =
      Enum.reduce(hidden_elements, tree, fn {_index, hidden_element, placeholder}, tree ->
        Util.traverse_until_first(tree, hidden_element, fn _element -> placeholder end)
      end)

    styles
    |> Enum.reduce(visible_tree, &add_rules_to_html_tree(&1, &2))
    |> Util.traverse("premailex", fn {"premailex", attrs, _children} ->
      {"data-index", index} = Enum.find(attrs, &(elem(&1, 0) == "data-index"))

      {_index, hidden_element, _replacement} = Enum.find(hidden_elements, &(elem(&1, 0) == index))

      hidden_element
    end)
  end

  defp load_css({"style", _, content}) do
    content
    |> Enum.join("\n")
    |> CSSParser.parse()
  end

  defp load_css({"link", attrs, _}), do: load_css({"link", List.keyfind(attrs, "href", 0)})

  defp load_css({"link", {"href", url}}) do
    {http_adapter, opts} = http_adapter()

    :get
    |> http_adapter.request(url, nil, [], opts)
    |> parse_body(http_adapter, url)
  end

  defp parse_body({:ok, %{status: status, body: body}}, _http_adapter, _url)
       when status in 200..399 do
    CSSParser.parse(body)
  end

  defp parse_body({:ok, %{status: status}}, _http_adapter, url) do
    Logger.warning("Ignoring #{url} styles because received unexpected HTTP status: #{status}")

    nil
  end

  defp parse_body({:error, error}, http_adapter, url) do
    Logger.warning(
      "Ignoring #{url} styles because of unexpected error from #{inspect(http_adapter)}:\n\n#{inspect(error)}"
    )

    nil
  end

  defp add_rules_to_html_tree(
         %{selector: selector, declarations: declarations, specificity: specificity},
         tree
       ) do
    update_selector_matches_in_tree(
      tree,
      selector,
      &update_style_for_element(&1, declarations, specificity)
    )
  end

  # `HTMLParser.all/2` arrive in document order, so a single depth-first walk
  # consumes them via the `[^element | rest]` head match with O(1) per check,
  # O(N) walk worst case.

  defp update_selector_matches_in_tree(tree, selector, fun) do
    tree
    |> HTMLParser.all(selector)
    |> case do
      [] -> {tree, []}
      matches -> update_node_matches_in_tree(tree, matches, fun)
    end
    |> elem(0)
  end

  defp update_node_matches_in_tree(nodes, matches, fun) when is_list(nodes),
    do: Enum.map_reduce(nodes, matches, &update_node_matches_in_tree(&1, &2, fun))

  defp update_node_matches_in_tree({_, _, _} = element, [element | rest], fun) do
    {tag, attrs, children} = fun.(element)
    {updated_children, remaining} = update_node_matches_in_tree(children, rest, fun)

    {{tag, attrs, updated_children}, remaining}
  end

  defp update_node_matches_in_tree({tag, attrs, children}, matches, fun) do
    {updated_children, remaining} = update_node_matches_in_tree(children, matches, fun)

    {{tag, attrs, updated_children}, remaining}
  end

  defp update_node_matches_in_tree(other, matches, _fun), do: {other, matches}

  defp update_style_for_element({name, attrs, children}, declarations, specificity) do
    style =
      attrs
      |> Enum.into(%{})
      |> Map.get("style", nil)
      |> set_inline_style_specificity()
      |> add_styles_with_specificity(declarations, specificity)

    {name, put_style_attr(attrs, style), children}
  end

  defp put_style_attr(attrs, style) do
    List.keystore(attrs, "style", 0, {"style", style})
  end

  defp set_inline_style_specificity(nil), do: ""
  defp set_inline_style_specificity("[SPEC=" <> _rest = style), do: style

  defp set_inline_style_specificity(style),
    do: "[SPEC=#{format_specificity({1, 0, 0, 0})}[#{style}]]"

  defp add_styles_with_specificity(style, declarations, specificity) do
    "#{style}[SPEC=#{format_specificity(specificity)}[#{CSSParser.to_string(declarations)}]]"
  end

  defp format_specificity({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  defp parse_specificity(str) do
    [a, b, c, d] = str |> String.split(".") |> Enum.map(&String.to_integer/1)
    {a, b, c, d}
  end

  defp normalize_styles(tree) do
    update_selector_matches_in_tree(tree, "[style]", &merge_style/1)
  end

  defp merge_style({name, attrs, children}) do
    current_style =
      attrs
      |> Enum.into(%{})
      |> Map.get("style")

    style =
      ~r/\[SPEC\=(\d+\.\d+\.\d+\.\d+)\[(.[^\]\]]*)\]\]/
      |> Regex.scan(current_style)
      |> Enum.map(fn [_, specificity, declaration_block] ->
        %{
          specificity: parse_specificity(specificity),
          declarations: CSSParser.parse_declaration_block(declaration_block)
        }
      end)
      |> CSSParser.merge()
      |> CSSParser.to_string()
      |> case do
        "" -> current_style
        style -> style
      end

    {name, put_style_attr(attrs, style), children}
  end

  defp optimize(tree, steps, options) when is_atom(steps), do: optimize(tree, [steps], options)
  defp optimize(tree, [:none], _options), do: tree
  defp optimize(tree, [:all], options), do: optimize(tree, [:remove_style_tags], options)

  defp optimize(tree, steps, options) do
    maybe_remove_style_tags(tree, steps, Keyword.get(options, :css_selector))
  end

  defp maybe_remove_style_tags(tree, _steps, nil), do: tree

  defp maybe_remove_style_tags(tree, steps, css_selector) do
    case Enum.member?(steps, :remove_style_tags) do
      true -> HTMLParser.filter(tree, css_selector)
      false -> tree
    end
  end

  defp remove_empty_comments(tree) do
    Util.traverse(tree, :comment, fn
      {:comment, "[if " <> _rest} = element -> element
      {:comment, "<![endif]" <> _rest} = element -> element
      {:comment, _comment} -> ""
    end)
  end

  defp http_adapter do
    case Application.get_env(:premailex, :http_adapter, Premailex.HTTPAdapter.Httpc) do
      {adapter, opts} -> {adapter, opts}
      adapter -> {adapter, nil}
    end
  end
end
