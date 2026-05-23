defmodule Premailex.HTMLParser.Xmerl do
  @moduledoc """
  A simple HTML parser using Erlang's built-in `:xmerl` library.

  This is used as a fallback when no other HTML parsing libraries are
  available. It is designed to handle well-formed XML-like HTML emails, but it
  does not support real-world HTML that often can be malformed XML.

  For more robust HTML parsing, it's recommended to use
  `Premailex.HTMLParser.Floki`, `Premailex.HTMLParser.Meeseeks`, or
  `Premailex.HTMLParser.LazyHTML`.

  `:xmerl_sax_parser` is used to prevent atom leak.

  ## Known limitations

    * Only well-formed XML-like HTML is parsed. HTML5 shortcuts like unquoted
      attribute values (`<div data-x=a>`) or unclosed non-void tags are
      rejected.

    * Only `:first-of-type` pseudo-class is implemented. Other pseudo-classes
      (`:not`, `:nth-child`, `:hover`, ...) parse but never match and emit a
      debug log.

    * The column combinator (`||`) parses but never matches and emits a debug
      log.

    * A round-trip through this parser is not lossless:

      * XML normalises whitespace in attribute values (newlines/tabs become
        spaces).

      * Named entities decode to characters and serialise as the literal
        character (e.g. `&copy;` round-trips as `©`).

      * `xmlns:*` namespace declarations always appear first in the attribute
        list regardless of source position as `:xmerl_sax_parser` strips them
        from the element's attribute list).

      * Void elements always serialise as `<br>` (HTML style) regardless of
        whether the source used `<br/>`.
  """
  @behaviour Premailex.HTMLParser

  require Logger

  @fragment_root "premailex-root"
  @comment_tag "premailex-comment"
  @void_tags ~w(area base br col embed hr img input link meta param source track wbr)

  # This regex is to ensure we get all void tags that are not closed, as xmerl
  # will fail if the void tags are not properly closed.
  @void_tags_regex Regex.compile!(
                     ~s{<(#{Enum.join(@void_tags, "|")})(\\b(?:\\s(?:[^"'>]|"[^"]*"|'[^']*')*)?)>},
                     "i"
                   )

  @html_entities :code.priv_dir(:premailex)
                 |> Path.join("entities.txt")
                 |> File.read!()
                 |> String.split("\n", trim: true)
                 |> Map.new(fn line ->
                   [entity | codepoints] = String.split(line, " ")
                   chars = codepoints |> Enum.map(&String.to_integer/1) |> IO.chardata_to_string()

                   {entity, chars}
                 end)

  @impl true
  @doc false
  def parse(html) do
    html
    |> normalize_html()
    |> wrap_fragment()
    |> parse_with_xmerl()
    |> unwrap_fragment()
  end

  defp normalize_html(html) do
    html
    |> String.replace(~r/<!DOCTYPE[^>]*>/i, "")
    |> replace_comments_with_placeholders()
    |> close_void_elements()
  end

  defp replace_comments_with_placeholders(html) do
    Regex.replace(~r/<!--(.*?)-->/s, html, fn _full, comment ->
      encoded_comment = Base.url_encode64(comment, padding: false)

      ~s(<#{@comment_tag} data-comment="#{encoded_comment}"/>)
    end)
  end

  defp close_void_elements(html) do
    Regex.replace(@void_tags_regex, html, fn _full, tag, attrs ->
      attrs
      |> String.trim()
      |> String.ends_with?("/")
      |> case do
        true -> "<#{tag}#{attrs}>"
        false -> "<#{tag}#{attrs}/>"
      end
    end)
  end

  defp wrap_fragment(html), do: "<#{@fragment_root}>#{html}</#{@fragment_root}>"

  defp parse_with_xmerl(html) do
    opts = [
      event_fun: &sax_event/3,
      event_state: %{stack: [], result: nil, namespace_attrs: []},
      # HTML entities are handled separately in `replace_html_entities/1`.
      external_entities: :none,
      fail_undeclared_ref: false
    ]

    case :xmerl_sax_parser.stream(String.to_charlist(html), opts) do
      {:ok, %{result: result}, _rest} ->
        result

      {:fatal_error, _location, reason, _end_tags, _state} ->
        raise ArgumentError,
              """
              #{__MODULE__} could not parse the HTML.

              The built-in fallback parser only supports simple, XML-like HTML email markup.
              For more permissive HTML parsing, add Floki, Meeseeks, or LazyHTML to your dependencies.

              Original error: #{inspect(reason)}
              """
    end
  end

  defp sax_event({:startPrefixMapping, prefix, uri}, _location, state) do
    namespace =
      case prefix do
        [] -> {"xmlns", List.to_string(uri)}
        _prefix -> {"xmlns:" <> List.to_string(prefix), List.to_string(uri)}
      end

    %{state | namespace_attrs: [namespace | state.namespace_attrs]}
  end

  defp sax_event({:startElement, _uri, _local_name, qname, attrs}, _location, state) do
    tag =
      case qname do
        {[], name} -> List.to_string(name)
        {prefix, name} -> List.to_string(prefix) <> ":" <> List.to_string(name)
      end

    parsed_attrs =
      Enum.reverse(state.namespace_attrs) ++
        Enum.map(attrs, &sax_attribute_to_pair/1)

    %{state | stack: [{tag, parsed_attrs, []} | state.stack], namespace_attrs: []}
  end

  defp sax_event({type, chars}, _location, state)
       when type in ~w(characters ignorableWhitespace)a do
    [{tag, attrs, children} | rest] = state.stack
    text = replace_html_entities(List.to_string(chars))

    %{state | stack: [{tag, attrs, [text | children]} | rest]}
  end

  defp sax_event({:endElement, _uri, _local_name, _qname}, _location, state) do
    [{tag, attrs, children} | rest] = state.stack

    node =
      case {tag, attrs} do
        {@comment_tag, attrs} -> {:comment, decode_comment(attrs)}
        _ -> {tag, attrs, Enum.reverse(children)}
      end

    case rest do
      [] ->
        %{state | stack: [], result: node}

      [{parent_tag, parent_attrs, parent_children} | remaining] ->
        %{state | stack: [{parent_tag, parent_attrs, [node | parent_children]} | remaining]}
    end
  end

  defp sax_event(_event, _location, state), do: state

  defp sax_attribute_to_pair({_uri, prefix, name, value}) do
    attr_name =
      case prefix do
        [] -> List.to_string(name)
        _prefix -> List.to_string(prefix) <> ":" <> List.to_string(name)
      end

    {attr_name, List.to_string(value)}
  end

  defp replace_html_entities(text) do
    Regex.replace(~r/&([a-zA-Z0-9]+);/, text, fn full, entity ->
      Map.get(@html_entities, "&#{entity};", full)
    end)
  end

  defp decode_comment(attrs) do
    {_, encoded} = List.keyfind!(attrs, "data-comment", 0)

    Base.url_decode64!(encoded, padding: false)
  end

  defp unwrap_fragment({@fragment_root, _attrs, []}), do: []
  defp unwrap_fragment({@fragment_root, _attrs, [single]}), do: single
  defp unwrap_fragment({@fragment_root, _attrs, many}), do: many

  @impl true
  @doc false
  def all(tree, selector) do
    tree
    |> List.wrap()
    |> traverse(compile_selector_groups(selector), [], fn
      node, true, descendants -> [node | descendants]
      _node, false, descendants -> descendants
    end)
  end

  defp compile_selector_groups(selector) do
    selector
    |> Premailex.CSSParser.parse_selector_groups()
    |> Enum.map(fn group ->
      Enum.map(group, fn step ->
        compiled_class_patterns =
          Enum.map(step.classes, &:binary.compile_pattern(<<" ", &1::binary, " ">>))

        # Override `:classes` with the compiled patterns as the selector group
        # will only be used internally here
        %{step | classes: compiled_class_patterns}
      end)
    end)
  end

  defp traverse(nodes, compiled_selector_groups, ancestors, fun) when is_list(nodes) do
    {results, _previous_siblings} =
      Enum.flat_map_reduce(nodes, [], fn
        {tag, attrs, children} = node, previous_siblings ->
          context =
            %{
              tag: tag,
              attrs: attrs,
              first_of_type?: not Enum.any?(previous_siblings, &(&1.tag == tag)),
              previous_siblings: previous_siblings
            }

          matched? =
            Enum.any?(compiled_selector_groups, &matches_selector_group?(context, &1, ancestors))

          descendants = traverse(children, compiled_selector_groups, [context | ancestors], fun)

          {fun.(node, matched?, descendants), [context | previous_siblings]}

        node, previous_siblings ->
          {fun.(node, false, []), previous_siblings}
      end)

    results
  end

  defp traverse(node, compiled_selector_groups, ancestors, fun) do
    case traverse([node], compiled_selector_groups, ancestors, fun) do
      [single] -> single
      list -> list
    end
  end

  defp matches_selector_group?(_context, [], _ancestors), do: false

  defp matches_selector_group?(context, compiled_selector_group, ancestors) do
    do_match_selector_steps?(compiled_selector_group, context, ancestors)
  end

  defp do_match_selector_steps?([step | rest], context, ancestors) do
    match_segment?(context, step) and
      match_remaining_selector_steps?(rest, context, ancestors)
  end

  defp match_segment?(%{tag: tag, attrs: attrs} = context, selector_segment) do
    # Guard each check on the *expected* value first so we skip the
    # `List.keyfind/3` when the selector doesn't constrain that field — the
    # common case for tag/descendant selectors.
    match_tag?(tag, selector_segment.tag) and
      match_id?(attrs, selector_segment.id) and
      match_classes?(attrs, selector_segment.classes) and
      match_attributes?(attrs, selector_segment.attrs) and
      match_pseudos?(context, selector_segment.pseudos)
  end

  defp match_tag?(_tag, nil), do: true
  defp match_tag?(_tag, "*"), do: true
  defp match_tag?(tag, tag), do: true
  defp match_tag?(_tag, _expected_tag), do: false

  defp get_attr(attrs, name) do
    case List.keyfind(attrs, name, 0) do
      {_, value} -> value
      nil -> nil
    end
  end

  defp match_id?(_attrs, nil), do: true
  defp match_id?(attrs, expected_id), do: get_attr(attrs, "id") == expected_id

  defp match_classes?(_attrs, []), do: true

  defp match_classes?(attrs, expected_classes) do
    case List.keyfind(attrs, "class", 0) do
      nil ->
        false

      {_, classes} ->
        padded = <<" ", classes::binary, " ">>

        Enum.all?(expected_classes, &(:binary.match(padded, &1) != :nomatch))
    end
  end

  defp match_attributes?(_attrs, []), do: true

  defp match_attributes?(attrs, expected_attrs) do
    Enum.all?(expected_attrs, fn
      {name, value} -> get_attr(attrs, name) == value
      name -> has_attr?(attrs, name)
    end)
  end

  defp has_attr?(attrs, name), do: List.keymember?(attrs, name, 0)

  defp match_pseudos?(_context, []), do: true

  defp match_pseudos?(context, pseudos) do
    Enum.all?(pseudos, fn
      %{kind: :pseudo_element} ->
        false

      %{kind: :pseudo_class, name: "first-of-type"} ->
        context.first_of_type?

      %{kind: :pseudo_class, name: unknown_pseudo_class} ->
        Logger.debug(fn ->
          "Pseudo-class #{unknown_pseudo_class} is not implemented. Ignoring."
        end)

        false
    end)
  end

  defp match_remaining_selector_steps?([], _context, _ancestors), do: true

  defp match_remaining_selector_steps?([step | _rest] = steps, context, ancestors) do
    case step.combinator do
      :descendant ->
        match_descendant_selector_steps?(steps, ancestors)

      :child ->
        match_child_selector_steps?(steps, ancestors)

      :adjacent ->
        match_adjacent_selector_steps?(steps, context, ancestors)

      :sibling ->
        match_sibling_selector_steps?(steps, context, ancestors)

      :column ->
        Logger.debug(fn -> "Column combinator (||) is not implemented. Ignoring." end)

        false
    end
  end

  defp match_descendant_selector_steps?(_steps, []), do: false

  defp match_descendant_selector_steps?(steps, [candidate | ancestors]) do
    do_match_selector_steps?(steps, candidate, ancestors) or
      match_descendant_selector_steps?(steps, ancestors)
  end

  defp match_child_selector_steps?(_steps, []), do: false

  defp match_child_selector_steps?(steps, [candidate | ancestors]) do
    do_match_selector_steps?(steps, candidate, ancestors)
  end

  defp match_adjacent_selector_steps?(_steps, %{previous_siblings: []}, _ancestors), do: false

  defp match_adjacent_selector_steps?(steps, %{previous_siblings: [candidate | _]}, ancestors) do
    do_match_selector_steps?(steps, candidate, ancestors)
  end

  defp match_sibling_selector_steps?(steps, %{previous_siblings: previous_siblings}, ancestors) do
    Enum.any?(previous_siblings, &do_match_selector_steps?(steps, &1, ancestors))
  end

  @impl true
  @doc false
  def filter(tree, selector) do
    traverse(tree, compile_selector_groups(selector), [], fn
      _node, true, _ -> []
      {tag, attrs, _}, false, children -> [{tag, attrs, collapse_whitespace(children)}]
      node, false, _ -> [node]
    end)
  end

  defp collapse_whitespace(children) do
    Enum.dedup_by(children, fn
      text when is_binary(text) ->
        (String.trim(text) == "" && :whitespace) || text

      other ->
        other
    end)
  end

  @impl true
  @doc false
  def to_string(tree) do
    tree
    |> List.wrap()
    |> Enum.map_join(&serialize_node/1)
  end

  defp serialize_node({:comment, text}), do: "<!--#{text}-->"

  defp serialize_node(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp serialize_node({tag, attrs, _children}) when tag in @void_tags do
    "<#{tag}#{serialize_attrs(attrs)}>"
  end

  defp serialize_node({tag, attrs, children}) do
    "<#{tag}#{serialize_attrs(attrs)}>#{Enum.map_join(children, &serialize_node/1)}</#{tag}>"
  end

  defp serialize_attrs(attrs) do
    Enum.map_join(attrs, fn {name, value} -> ~s( #{name}="#{escape_attr(value)}") end)
  end

  defp escape_attr(value) do
    value
    |> serialize_node()
    |> String.replace("\"", "&quot;")
  end

  @impl true
  @doc false
  def text(text) when is_binary(text), do: text
  def text(list) when is_list(list), do: Enum.map_join(list, &text/1)
  def text({:comment, _text}), do: ""
  def text({_element, _attrs, children}), do: text(children)
end
