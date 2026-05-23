defmodule Premailex.HTMLToPlainText do
  @moduledoc """
  Module that converts HTML emails to plain text.
  """
  alias Premailex.DOM

  @line_length 65

  @doc """
  Processes an HTML tree into a plain text string.

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

  defp images(tree), do: DOM.replace_all_matches(tree, "img", &image(&1))

  defp image({_, attr, _}) do
    attr
    |> Enum.find({"", ""}, &(elem(&1, 0) == "alt"))
    |> elem(1)
  end

  defp line_breaks(tree), do: DOM.replace_all_matches(tree, "br", &line_break(&1))
  defp line_break(_), do: "\n"

  defp headings(tree), do: DOM.replace_all_matches(tree, Enum.map(1..6, &"h#{&1}"), &heading(&1))

  defp heading({type, _, content}) do
    text = DOM.text_content(content)

    length =
      text
      |> String.split("\n")
      |> Enum.map(&String.length(&1))
      |> Enum.max()

    "\n\n" <> heading(type, text, length) <> "\n\n"
  end

  defp heading("h1", text, length) do
    heading_line = String.duplicate("*", length)
    heading_line <> "\n" <> text <> "\n" <> heading_line
  end

  defp heading("h2", text, length) do
    heading_line = String.duplicate("-", length)
    heading_line <> "\n" <> text <> "\n" <> heading_line
  end

  defp heading(_, text, length) do
    heading_line = String.duplicate("-", length)
    text <> "\n" <> heading_line
  end

  defp links(tree), do: DOM.replace_all_matches(tree, "a", &link(&1))

  defp link({_, attr, content}) do
    url =
      attr
      |> Enum.find({"", ""}, &(elem(&1, 0) == "href"))
      |> elem(1)
      |> String.replace("mailto:", "")

    text = DOM.text_content(content)

    link(String.trim(url), String.trim(text))
  end

  defp link(url, text), do: link(url, text, String.downcase(url) == String.downcase(text))
  defp link(_, "", _), do: ""
  defp link(url, _, true), do: url
  defp link(url, text, false), do: "#{text} (#{url})"

  defp paragraphs(tree), do: DOM.replace_all_matches(tree, "p", &paragraph(&1))
  defp paragraph({_, _, content}), do: DOM.text_content(content) <> "\n\n"

  defp horizontal_rules(tree), do: DOM.replace_all_matches(tree, "hr", &horizontal_rule(&1))

  defp horizontal_rule({_, _, _}), do: String.duplicate("-", @line_length) <> "\n\n"

  defp unordered_lists(tree), do: DOM.replace_all_matches(tree, "ul", &unordered_list_items(&1))

  defp unordered_list_items({_, _, items}) do
    items
    |> DOM.replace_all_matches("li", &unordered_list_item(&1))
    |> join_binaries("")
  end

  defp unordered_list_item({_, _, content}) do
    "* " <> DOM.text_content(content) <> "\n"
  end

  defp join_binaries(elements, separator) do
    Enum.reduce(elements, "", fn
      element, "" when is_binary(element) ->
        element

      element, acc when is_binary(element) ->
        acc <> separator <> element

      _element, acc ->
        acc
    end)
  end

  defp ordered_lists(tree), do: DOM.replace_all_matches(tree, "ol", &ordered_list_items(&1))

  defp ordered_list_items({_, _, items}) do
    items
    |> Enum.with_index(1)
    |> Enum.map(fn {item, n} ->
      DOM.replace_all_matches(item, "li", &ordered_list_item(&1, n))
    end)
    |> join_binaries("")
  end

  defp ordered_list_item({_, _, content}, n) do
    "#{n}. " <> DOM.text_content(content) <> "\n"
  end

  defp tables(tree), do: DOM.replace_all_matches(tree, "table", &table(&1))

  defp table({_, _, table_rows}) do
    # Calling tables/1 to make sure all nested tables have been processed
    table_rows
    |> tables()
    |> flatten_table_elements()
    |> DOM.replace_all_matches("tr", &table_rows(&1))
    |> join_binaries("")
  end

  defp table_rows({_, _, [{"th", _, _} | _rest] = table_cells}) do
    table_cells
    |> DOM.replace_all_matches("th", &DOM.text_content(&1))
    |> join_binaries(" ")
    |> Kernel.<>("\n")
  end

  defp table_rows({_, _, table_cells}) do
    table_cells
    |> DOM.replace_all_matches("td", &DOM.text_content(&1))
    |> join_binaries(" ")
    |> Kernel.<>("\n")
  end

  defp flatten_table_elements(elements), do: Enum.flat_map(elements, &flatten_table_element/1)

  defp flatten_table_element({"thead", _, table_cells}), do: table_cells
  defp flatten_table_element({"tbody", _, table_cells}), do: table_cells
  defp flatten_table_element({"tfoot", _, table_cells}), do: table_cells
  defp flatten_table_element(elem), do: [elem]

  defp wordwrap(text) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", &wrap_paragraph(String.trim(&1)))
  end

  defp wrap_paragraph(""), do: ""

  defp wrap_paragraph(string) do
    [word | rest] = String.split(string, ~r/\s+/, trim: true)

    rest |> lines_assemble(@line_length, String.length(word), word, []) |> Enum.join("\n")
  end

  defp lines_assemble([], _, _, line, acc), do: [line | acc] |> Enum.reverse()

  defp lines_assemble([word | rest], max, line_length, line, acc) do
    if line_length + 1 + String.length(word) > max do
      lines_assemble(rest, max, String.length(word), word, [line | acc])
    else
      lines_assemble(rest, max, line_length + 1 + String.length(word), line <> " " <> word, acc)
    end
  end

  defp clear_linebreaks(text), do: Regex.replace(~r/[\n]{3,}/, text, "\n\n")

  defp clear_whitespace(list) when is_list(list) do
    list = Enum.map(list, &clear_whitespace(&1))

    list
    |> Enum.all?(&inline_element?/1)
    |> case do
      true -> list
      false -> Enum.reject(list, &empty?/1)
    end
  end

  defp clear_whitespace({elem, attr, children}) do
    {elem, attr, clear_whitespace(children)}
  end

  defp clear_whitespace(any), do: any

  defp empty?(text) when is_binary(text) do
    String.trim(text) == ""
  end

  defp empty?(_any), do: false

  @inline_elements [
    "a",
    "abbr",
    "acronym",
    "b",
    "bdo",
    "big",
    "br",
    "button",
    "cite",
    "code",
    "dfn",
    "em",
    "i",
    "img",
    "input",
    "kbd",
    "label",
    "map",
    "object",
    "q",
    "samp",
    "script",
    "select",
    "small",
    "span",
    "strong",
    "sub",
    "sup",
    "textarea",
    "time",
    "tt",
    "var"
  ]

  defp inline_element?({element, _attrs, _children})
       when element in @inline_elements,
       do: true

  defp inline_element?({_element, _attrs, _children}), do: false
  defp inline_element?(_any), do: true
end
