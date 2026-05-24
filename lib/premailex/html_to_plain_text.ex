defmodule Premailex.HTMLToPlainText do
  @moduledoc """
  Converts `t:Premailex.html_tree/0` into plain text.
  """
  alias Premailex.DOM

  @line_length 65
  @heading_tags Enum.map(1..6, &"h#{&1}")

  @inline_tags ~w(a abbr acronym b bdo big br button cite code dfn em i img
                  input kbd label map object q samp script select small span
                  strong sub sup textarea time tt var)

  @doc """
  Converts a `t:Premailex.html_tree/0` into a plain text string.

  ## Examples

      iex> tree = Premailex.parse("<html><body><ul><li>Test</li></ul></body></html>")
      iex> Premailex.HTMLToPlainText.process(tree)
      "* Test"
  """
  @spec process(Premailex.html_tree()) :: String.t()
  def process(tree) do
    tree
    |> get_visible_tree()
    |> clear_whitespace()
    |> line_breaks()
    |> horizontal_rules()
    |> images()
    |> links()
    |> headings()
    |> paragraphs()
    |> unordered_lists()
    |> ordered_lists()
    |> tables()
    |> DOM.text_content()
    |> wordwrap()
    |> clear_linebreaks()
    |> String.trim()
  end

  defp get_visible_tree(tree) do
    case DOM.all(tree, "body") do
      [] -> tree
      bodies -> bodies
    end
  end

  defp images(tree), do: DOM.replace_all_matches(tree, "img", &image/1)

  defp image({"img", attrs, []}) do
    case List.keyfind(attrs, "alt", 0) do
      {"alt", value} -> value
      nil -> ""
    end
  end

  defp line_breaks(tree), do: DOM.replace_all_matches(tree, "br", &line_break/1)

  defp line_break({"br", _attrs, []}), do: "\n"

  defp headings(tree), do: DOM.replace_all_matches(tree, @heading_tags, &heading/1)

  defp heading({type, _attrs, children}) do
    text = DOM.text_content(children)

    line_length =
      text
      |> String.split("\n")
      |> Enum.map(&String.length/1)
      |> Enum.max()

    "\n\n" <> heading(type, text, line_length) <> "\n\n"
  end

  defp heading("h1", text, line_length) do
    heading_line = String.duplicate("*", line_length)

    heading_line <> "\n" <> text <> "\n" <> heading_line
  end

  defp heading("h2", text, line_length) do
    heading_line = String.duplicate("-", line_length)

    heading_line <> "\n" <> text <> "\n" <> heading_line
  end

  defp heading(_, text, line_length) do
    heading_line = String.duplicate("-", line_length)

    text <> "\n" <> heading_line
  end

  defp links(tree), do: DOM.replace_all_matches(tree, "a", &link/1)

  defp link({"a", attrs, content}) do
    text = content |> DOM.text_content() |> String.trim()

    attrs
    |> List.keyfind("href", 0)
    |> case do
      {"href", href} ->
        href
        |> String.replace("mailto:", "")
        |> String.trim()
        |> link(text)

      nil ->
        text
    end
  end

  defp link(_url, ""), do: ""

  defp link(url, text) do
    case String.downcase(url) == String.downcase(text) do
      true -> url
      false -> "#{text} (#{url})"
    end
  end

  defp paragraphs(tree), do: DOM.replace_all_matches(tree, "p", &paragraph/1)

  defp paragraph({"p", _attrs, content}), do: DOM.text_content(content) <> "\n\n"

  defp horizontal_rules(tree), do: DOM.replace_all_matches(tree, "hr", &horizontal_rule/1)

  defp horizontal_rule({"hr", _attrs, []}), do: String.duplicate("-", @line_length) <> "\n\n"

  defp unordered_lists(tree), do: DOM.replace_all_matches(tree, "ul", &unordered_list/1)

  defp unordered_list({"ul", _attrs, children}) do
    children
    |> filter_by_tag("li")
    |> Enum.map_join(&unordered_list_item/1)
  end

  defp filter_by_tag(elements, tag_or_tags) do
    tags = List.wrap(tag_or_tags)

    Enum.filter(elements, fn
      {tag, _attrs, _children} -> tag in tags
      _any -> false
    end)
  end

  defp unordered_list_item({"li", _attrs, children}) do
    "* " <> DOM.text_content(children) <> "\n"
  end

  defp ordered_lists(tree), do: DOM.replace_all_matches(tree, "ol", &ordered_list/1)

  defp ordered_list({"ol", _attrs, children}) do
    children
    |> filter_by_tag("li")
    |> Enum.with_index(1)
    |> Enum.map_join(fn {element, n} ->
      ordered_list_item(element, n)
    end)
  end

  defp ordered_list_item({"li", _attrs, children}, n) do
    "#{n}. " <> DOM.text_content(children) <> "\n"
  end

  defp tables(tree), do: DOM.replace_all_matches(tree, "table", &table/1)

  defp table({"table", _attrs, children}) do
    # Calling tables/1 to make sure all nested tables have been processed first
    children
    |> tables()
    |> flatten_table_elements()
    |> filter_by_tag("tr")
    |> Enum.map_join(&table_row/1)
  end

  defp table_row({"tr", _attrs, children}) do
    children
    |> filter_by_tag(~w(th td))
    |> Enum.map_join(" ", &DOM.text_content/1)
    |> Kernel.<>("\n")
  end

  defp flatten_table_elements(elements), do: Enum.flat_map(elements, &flatten_table_element/1)

  defp flatten_table_element({"thead", _attrs, children}), do: children
  defp flatten_table_element({"tbody", _attrs, children}), do: children
  defp flatten_table_element({"tfoot", _attrs, children}), do: children
  defp flatten_table_element(element), do: [element]

  defp wordwrap(text) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", &wrap_paragraph(String.trim(&1)))
  end

  defp wrap_paragraph(""), do: ""

  defp wrap_paragraph(string) do
    [word | rest] = String.split(string)

    rest
    |> lines_assemble(@line_length, String.length(word), word, [])
    |> Enum.join("\n")
  end

  defp lines_assemble([], _max, _line_length, line, acc), do: [line | acc] |> Enum.reverse()

  defp lines_assemble([word | rest], max, line_length, line, acc) do
    new_line_length = line_length + 1 + String.length(word)

    case new_line_length > max do
      true -> lines_assemble(rest, max, String.length(word), word, [line | acc])
      false -> lines_assemble(rest, max, new_line_length, line <> " " <> word, acc)
    end
  end

  defp clear_linebreaks(text), do: Regex.replace(~r/\n{3,}/, text, "\n\n")

  defp clear_whitespace(tree) when is_list(tree) do
    cleared_tree = Enum.map(tree, &clear_whitespace/1)

    case Enum.all?(cleared_tree, &inline_element?/1) do
      true -> cleared_tree
      false -> Enum.reject(cleared_tree, &empty?/1)
    end
  end

  defp clear_whitespace({tag, attrs, children}) do
    {tag, attrs, clear_whitespace(children)}
  end

  defp clear_whitespace(any), do: any

  defp empty?(text) when is_binary(text), do: String.trim(text) == ""
  defp empty?(_any), do: false

  defp inline_element?({tag, _attrs, _children}) when tag in @inline_tags, do: true
  defp inline_element?({_tag, _attrs, _children}), do: false
  defp inline_element?(_any), do: true
end
