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
    |> apply_rules(tree)
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

  defp apply_rules(rules, tree) do
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

    visible_tree
    |> match_rules_to_elements(rules)
    |> apply_matched_rules(visible_tree)
    |> Util.traverse("premailex", fn {"premailex", attrs, _children} ->
      {"data-index", index} = Enum.find(attrs, &(elem(&1, 0) == "data-index"))

      {_index, hidden_element, _replacement} = Enum.find(hidden_elements, &(elem(&1, 0) == index))

      hidden_element
    end)
  end

  defp match_rules_to_elements(tree, rules) do
    Enum.reduce(rules, %{}, fn rule, acc ->
      tree
      |> HTMLParser.all(rule.selector)
      |> Enum.reduce(acc, &prepend_deduped_rule(&2, &1, rule))
    end)
  end

  # NOTE: This match is not right as it doesn't account for identical elements.
  # A selector like `tr:nth-child(even)` would match identical siblings. A fix
  # would be to have the HTML parser adapters do positional selector
  # evaluation.
  defp prepend_deduped_rule(acc, element, rule) do
    Map.update(acc, element, [rule], fn
      [^rule | _] = list -> list
      list -> [rule | list]
    end)
  end

  defp apply_matched_rules(matches, tree) when map_size(matches) == 0, do: tree

  defp apply_matched_rules(matches, tree) do
    Util.traverse_and_update(tree, fn element ->
      case Map.get(matches, element) do
        nil -> element
        rules -> apply_inline_style(element, rules)
      end
    end)
  end

  defp apply_inline_style({name, attrs, children}, rules) do
    attrs =
      attrs
      |> get_inline_css_rule()
      |> List.wrap()
      |> Kernel.++(Enum.reverse(rules))
      |> CSSParser.merge()
      |> case do
        [] ->
          attrs

        declarations ->
          List.keystore(attrs, "style", 0, {"style", CSSParser.to_string(declarations)})
      end

    {name, attrs, children}
  end

  defp get_inline_css_rule(attrs) do
    case List.keyfind(attrs, "style", 0) do
      nil ->
        nil

      {"style", style} ->
        %{
          selector: "",
          declarations: CSSParser.parse_declaration_block(style),
          specificity: {1, 0, 0, 0}
        }
    end
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
