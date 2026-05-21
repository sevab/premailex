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

  The tree will be traversed depth-first, and the function will be called on
  every node matching a needle, replacing each with the result.

  ## Examples

      iex> Premailex.Util.traverse({"div", [], [{"p", [], ["First paragraph"]}, {"p", [], ["Second paragraph"]}]}, "p", fn {name, attrs, _children} -> {name, attrs, ["Updated"]} end)
      {"div", [], [{"p", [], ["Updated"]}, {"p", [], ["Updated"]}]}

      iex> Premailex.Util.traverse({"div", [], [{"p", [], ["First paragraph"]}, {"p", [], ["Second paragraph"]}]}, {"p", [], ["Second paragraph"]}, fn {name, attrs, _children} -> {name, attrs, ["Updated"]} end)
      {"div", [], [{"p", [], ["First paragraph"]}, {"p", [], ["Updated"]}]}

      iex> Premailex.Util.traverse({"div", [], [{:comment, "This is a comment"}, {"p", [], ["Paragraph"]}]}, :comment, fn {:comment, _comment} -> {:comment, "Updated"} end)
      {"div", [], [{:comment, "Updated"}, {"p", [], ["Paragraph"]}]}
  """
  @spec traverse(html_tree(), needle() | [needle()], (html_node() -> html_node())) :: html_tree()
  def traverse(tree, needle_or_needles, fun),
    do: do_traverse(tree, List.wrap(needle_or_needles), fun)

  defp do_traverse(children, needles, fun) when is_list(children),
    do: Enum.map(children, &do_traverse(&1, needles, fun))

  defp do_traverse(text, _needles, _fun) when is_binary(text), do: text

  defp do_traverse({:comment, _comment} = element, needles, fun) do
    case :comment in needles do
      true -> fun.(element)
      false -> element
    end
  end

  defp do_traverse({name, attrs, children} = element, needles, fun) do
    cond do
      name in needles -> fun.(element)
      element in needles -> fun.(element)
      true -> {name, attrs, do_traverse(children, needles, fun)}
    end
  end

  defp do_traverse(other, _needles, _fun), do: other

  @doc """
  Traverses tree until first match for needle.

  The tree will be traversed depth-first, and the function will be called on
  the first node matching a needle, replacing it with the result.

  ## Examples

      iex> Premailex.Util.traverse_until_first({"div", [], [{"p", [], ["First paragraph"]}, {"p", [], ["Second paragraph"]}]}, "p", fn {name, attrs, _children} -> {name, attrs, ["Updated"]} end)
      {"div", [], [{"p", [], ["Updated"]}, {"p", [], ["Second paragraph"]}]}
  """
  @spec traverse_until_first(html_tree(), needle(), (html_node() -> html_node())) :: html_tree()
  def traverse_until_first(tree, needle, fun) do
    case do_traverse_until_first(tree, needle, fun) do
      {:halt, tree} -> tree
      tree -> tree
    end
  end

  defp do_traverse_until_first(children, needle, fun) when is_list(children) do
    children
    |> Enum.reduce({:cont, []}, fn
      child, {:cont, acc} ->
        case do_traverse_until_first(child, needle, fun) do
          {:halt, result} -> {:halt, [result | acc]}
          other -> {:cont, [other | acc]}
        end

      child, {:halt, acc} ->
        {:halt, [child | acc]}
    end)
    |> case do
      {:halt, acc} -> {:halt, Enum.reverse(acc)}
      {:cont, acc} -> Enum.reverse(acc)
    end
  end

  defp do_traverse_until_first(text, _needle, _fun) when is_binary(text), do: text

  defp do_traverse_until_first({:comment, _comment} = element, :comment, fun) do
    {:halt, fun.(element)}
  end

  defp do_traverse_until_first({name, _attrs, _children} = element, name, fun) do
    {:halt, fun.(element)}
  end

  defp do_traverse_until_first({_, _, _} = element, element, fun) do
    {:halt, fun.(element)}
  end

  defp do_traverse_until_first({name, attrs, children}, needle, fun) do
    case do_traverse_until_first(children, needle, fun) do
      {:halt, new_children} -> {:halt, {name, attrs, new_children}}
      new_children -> {name, attrs, new_children}
    end
  end

  defp do_traverse_until_first(other, _needle, _fun), do: other

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
