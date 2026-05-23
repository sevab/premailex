defmodule Premailex.HTMLInlineStyles do
  @moduledoc """
  Module that inlines CSS styles into an HTML tree.
  """

  alias Premailex.{CSSParser, DOM}

  @inline_style_specificity {1, 0, 0, 0}

  @doc """
  Processes an HTML tree adding inline styles from a list of CSS rules.

  ## Examples

      iex> tree = Premailex.parse(~s(<html><head><style>p{background-color: #fff;}</style></head><body><p style="color: #000;">Text</p></body></html>))
      iex> css_rules = Premailex.CSSParser.parse("p{background-color: #fff;}")
      iex> Premailex.HTMLInlineStyles.process(tree, css_rules)
      [
        {"html", [],
        [
          {"head", [], [{"style", [], ["p{background-color: #fff;}"]}]},
          {"body", [], [{"p", [{"style", "background-color: #fff; color: #000;"}], ["Text"]}]}
        ]}
      ]
  """
  @spec process(Premailex.html_tree(), [CSSParser.rule()]) :: Premailex.html_tree()
  def process(tree, css_rules) do
    tree
    |> apply_css_rules(css_rules)
    |> remove_empty_comments()
  end

  defp apply_css_rules(tree, css_rules) do
    {visible_tree, hidden_heads} = hide_heads(tree)

    visible_tree
    |> DOM.traverse_with_matching_items(css_rules, fn {tag, attrs, children}, matched_css_rules ->
      {tag, merge_css_rules_into_style(attrs, matched_css_rules), children}
    end)
    |> DOM.replace_all_matches(:comment, fn
      {:comment, "premailex:head:" <> index} -> Map.fetch!(hidden_heads, index)
      {:comment, comment} -> {:comment, comment}
    end)
  end

  defp hide_heads(tree) do
    hidden_heads =
      tree
      |> DOM.all("head")
      |> Enum.with_index()
      |> Map.new(fn {head, index} ->
        {to_string(index), head}
      end)

    visible_tree =
      Enum.reduce(hidden_heads, tree, fn {index, head}, acc ->
        DOM.replace_first_match(acc, head, fn _ ->
          {:comment, "premailex:head:#{index}"}
        end)
      end)

    {visible_tree, hidden_heads}
  end

  defp merge_css_rules_into_style(attrs, matched_css_rules) do
    attrs
    |> List.keyfind("style", 0)
    |> case do
      nil ->
        matched_css_rules

      {"style", style} ->
        [
          %{
            selector: "",
            declarations: CSSParser.parse_declaration_block(style),
            specificity: @inline_style_specificity
          }
          | matched_css_rules
        ]
    end
    |> CSSParser.cascade()
    |> CSSParser.to_string()
    |> case do
      "" -> attrs
      style -> List.keystore(attrs, "style", 0, {"style", style})
    end
  end

  defp remove_empty_comments(tree) do
    DOM.replace_all_matches(tree, :comment, fn
      {:comment, "[if " <> _rest} = element -> element
      {:comment, "<![endif]" <> _rest} = element -> element
      {:comment, _comment} -> ""
    end)
  end
end
