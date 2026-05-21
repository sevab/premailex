defmodule Premailex.Util do
  @moduledoc """
  Module that contains utility functions.
  """

  alias Premailex.HTMLParser

  @type html_tree :: HTMLParser.html_tree()
  @type html_node :: HTMLParser.html_node()
  @type html_element :: HTMLParser.html_element()
  @type needle :: html_element() | binary() | :comment

  @doc """
  Traverses tree searching for needle, and will call provided function on
  any occurances.

  If the function returns `{:halt, any}`, traverse will stop, and result will
  be `{:halt, html_tree}`.

  ## Examples

      iex> Premailex.Util.traverse({"div", [], [{"p", [], ["First paragraph"]}, {"p", [], ["Second paragraph"]}]}, "p", fn {name, attrs, _children} -> {name, attrs, ["Updated"]} end)
      {"div", [], [{"p", [], ["Updated"]}, {"p", [], ["Updated"]}]}

      iex> Premailex.Util.traverse({"div", [], [{"p", [], ["First paragraph"]}, {"p", [], ["Second paragraph"]}]}, {"p", [], ["Second paragraph"]}, fn {name, attrs, _children} -> {name, attrs, ["Updated"]} end)
      {"div", [], [{"p", [], ["First paragraph"]}, {"p", [], ["Updated"]}]}

      iex> Premailex.Util.traverse({"div", [], [{:comment, "This is a comment"}, {"p", [], ["Paragraph"]}]}, :comment, fn {:comment, _comment} -> {:comment, "Updated"} end)
      {"div", [], [{:comment, "Updated"}, {"p", [], ["Paragraph"]}]}
  """
  @spec traverse(html_tree(), needle() | [needle()], (html_node() -> html_node())) :: html_tree()
  @spec traverse(html_tree(), needle() | [needle()], (html_node() -> {:halt, html_node()})) ::
          html_tree() | {:halt, html_tree()}
  def traverse(tree, needles, fun) when is_list(needles),
    do: Enum.reduce(needles, tree, &traverse(&2, &1, fun))

  def traverse(children, needle, fun) when is_list(children) do
    children
    |> Enum.map_reduce(:ok, &maybe_traverse({&1, needle, fun}, &2))
    |> case do
      {children, :halt} -> {:halt, children}
      {children, :ok} -> children
    end
  end

  def traverse(text, _, _) when is_binary(text), do: text

  def traverse({:comment, _comment} = element, :comment, fun), do: fun.(element)

  def traverse({name, attrs, children} = element, needle, fun) do
    cond do
      needle == name -> fun.(element)
      needle == element -> fun.(element)
      true -> handle_traversed({name, attrs, children}, needle, fun)
    end
  end

  def traverse(element, _, _), do: element

  defp maybe_traverse({element, needle, fun}, :ok) do
    case traverse(element, needle, fun) do
      {:halt, children} -> {children, :halt}
      children -> {children, :ok}
    end
  end

  defp maybe_traverse({element, _needle, _fun}, :halt), do: {element, :halt}

  defp handle_traversed({name, attrs, children}, needle, fun) do
    case traverse(children, needle, fun) do
      {:halt, children} -> {:halt, {name, attrs, children}}
      children -> {name, attrs, children}
    end
  end

  @doc """
  Traverses each element in `children`, calling `fun.(element, index)` for any
  occurrence of `needle`, where `index` is the zero-based position of the
  element in `children`. Returns `{children, count}` where `count` is the total
  number of children traversed.

  ## Examples

      iex> Premailex.Util.traverse_reduce([{"p", [], ["First paragraph"]}, {"p", [], ["Second paragraph"]}], "p", fn({name, attrs, _children}, acc) -> {name, attrs, ["Updated " <> to_string(acc)]} end)
      {[{"p", [], ["Updated 0"]}, {"p", [], ["Updated 1"]}], 2}
  """
  @spec traverse_reduce([html_node()], needle(), (html_node(), non_neg_integer() -> html_node())) ::
          {[html_node()], non_neg_integer()}
  def traverse_reduce(children, needle, fun) when is_list(children),
    do:
      Enum.map_reduce(
        children,
        0,
        &{traverse(&1, needle, fn element -> fun.(element, &2) end), &2 + 1}
      )

  @doc """
  Traverses tree until first match for needle.

  ## Examples

      iex> Premailex.Util.traverse_until_first({"div", [], [{"p", [], ["First paragraph"]}, {"p", [], ["Second paragraph"]}]}, "p", fn {name, attrs, _children} -> {name, attrs, ["Updated"]} end)
      {"div", [], [{"p", [], ["Updated"]}, {"p", [], ["Second paragraph"]}]}
  """
  @spec traverse_until_first(html_tree(), needle(), (html_node() -> html_node())) :: html_tree()
  def traverse_until_first(tree, needle, fun) do
    case traverse(tree, needle, &{:halt, fun.(&1)}) do
      {:halt, tree} -> tree
      tree -> tree
    end
  end

  @doc """
  Traverses tree calling the function on every element and replacing each with
  the result.

  Children of the returned element are walked again, so the function can
  produce new subtrees that themselves contain matches.

  ## Examples

      iex> Premailex.Util.traverse_and_update({"div", [], [{"p", [], ["hi"]}]}, fn {tag, attrs, children} -> {tag, [{"class", "x"} | attrs], children} end)
      {"div", [{"class", "x"}], [{"p", [{"class", "x"}], ["hi"]}]}
  """
  @spec traverse_and_update(html_tree(), (html_element() -> html_element())) :: html_tree()
  def traverse_and_update(tree, fun), do: do_traverse_and_update(tree, fun)

  defp do_traverse_and_update(children, fun) when is_list(children),
    do: Enum.map(children, &do_traverse_and_update(&1, fun))

  defp do_traverse_and_update({_, _, _} = element, fun) do
    {tag, attrs, children} = fun.(element)

    {tag, attrs, do_traverse_and_update(children, fun)}
  end

  defp do_traverse_and_update(other, _fun), do: other
end
