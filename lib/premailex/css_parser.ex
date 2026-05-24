defmodule Premailex.CSSParser do
  @moduledoc """
  CSS parser.

  ## Parser limitations

    * At-rules (`@media`, `@font-face`, `@import`, etc.) and comments are
      stripped.

    * Specificity for `:not(...)`, `:is(...)`, and `:where(...)` is approximated
      as a single pseudo-class. In Selectors Level 4, specificity is derived from
      the argument (or is `0` for `:where`).
  """
  require Logger

  @typedoc "A CSS rule declaration."
  @type declaration :: %{property: String.t(), value: String.t(), important?: boolean()}

  @typedoc "A CSS rule with computed specificity."
  @type rule :: %{declarations: [declaration()], selector: String.t(), specificity: specificity()}

  @typedoc """
  A CSS pseudo-class or pseudo-element.

  Pseudo-classes in the `an+b` family (`:nth-child`, `:nth-of-type`,
  `:nth-last-child`, `:nth-last-of-type`) include an additional `:nth` field
  holding the parsed `{a, b}` coefficients, or `:invalid` if the expression is
  missing or cannot be parsed.
  """
  @type pseudo :: %{
          required(:name) => String.t(),
          required(:expression) => String.t() | nil,
          required(:kind) => :pseudo_class | :pseudo_element,
          optional(:nth) => {integer(), integer()} | :invalid
        }

  @typedoc """
  A single element step in a selector.
  """
  @type selector_group_step :: %{
          tag: String.t() | nil,
          id: String.t() | nil,
          classes: [String.t()],
          attrs: [String.t() | {String.t(), String.t()}],
          pseudos: [pseudo()],
          combinator: :descendant | :child | :adjacent | :sibling | :column | nil
        }

  @typedoc "A list of selector steps ordered from right to left."
  @type selector_group :: [selector_group_step()]

  @typedoc """
  CSS specificity, matching the Selectors Level 4 four-tuple model.

  Structured as `{inline?, ids, classes, elements}`:

    * `inline?` - `1` if the style is inline.
    * `ids` - number of ID selectors.
    * `classes` - number of class, attribute, and pseudo-class selectors.
    * `elements` - number of tag and pseudo-element selectors.
  """
  @type specificity :: {0..1, non_neg_integer(), non_neg_integer(), non_neg_integer()}

  @selector_whitespace [?\s, ?\t, ?\n, ?\r, ?\f]
  @step %{tag: nil, id: nil, classes: [], attrs: [], pseudos: [], combinator: nil}
  @nth_pseudo_classes ~w(nth-child nth-of-type nth-last-child nth-last-of-type)

  @initial_selector_state %{
    type: :tag,
    step: @step,
    buffer: "",
    pending_relation: nil,
    bracket_depth: 0,
    paren_depth: 0,
    quote_char: nil,
    steps: []
  }

  @doc """
  Parses a CSS string into a list of CSS rules.

  Ignores at-rules (e.g. `@media`, `@font-face`, etc.) and comments, as they
  are not relevant for inlining CSS.

  ## Examples

      iex> Premailex.CSSParser.parse("body { background-color: #fff !important; color: red; }")
      [
        %{
          declarations: [
            %{property: "background-color", value: "#fff !important", important?: true},
            %{property: "color", value: "red", important?: false}
          ],
          selector: "body",
          specificity: {0, 0, 0, 1}
        }
      ]
  """
  @spec parse(String.t()) :: [rule()]
  def parse(css), do: parse(css, "", "", 0, [])

  defp parse(<<>>, _selector, _declaration_block, _depth, acc), do: Enum.reverse(acc)

  defp parse(<<"/*", rest::binary>>, selector, declaration_block, depth, acc) do
    case :binary.split(rest, "*/") do
      [_comment, rest] -> parse(rest, selector, declaration_block, depth, acc)
      [_unterminated] -> Enum.reverse(acc)
    end
  end

  defp parse(<<"@", rest::binary>>, "", _declaration_block, 0, acc) do
    rest
    |> remove_at_rule(0)
    |> parse("", "", 0, acc)
  end

  defp parse(<<c, rest::binary>>, "", _declaration_block, 0, acc) when c in @selector_whitespace,
    do: parse(rest, "", "", 0, acc)

  defp parse(<<"{", rest::binary>>, selector, _declaration_block, 0, acc),
    do: parse(rest, selector, "", 1, acc)

  defp parse(<<"{", rest::binary>>, selector, declaration_block, depth, acc),
    do: parse(rest, selector, <<declaration_block::binary, "{">>, depth + 1, acc)

  defp parse(<<"}", rest::binary>>, selector, declaration_block, 1, acc) do
    parsed_declarations = parse_declaration_block(declaration_block)

    selector
    |> split_selector_groups()
    |> Enum.reduce(acc, fn group, acc ->
      [build_rule(group, parsed_declarations) | acc]
    end)
    |> then(&parse(rest, "", "", 0, &1))
  end

  defp parse(<<"}", rest::binary>>, selector, declaration_block, depth, acc),
    do: parse(rest, selector, <<declaration_block::binary, "}">>, depth - 1, acc)

  defp parse(<<char, rest::binary>>, selector, _declaration_block, 0, acc),
    do: parse(rest, <<selector::binary, char>>, "", 0, acc)

  defp parse(<<char, rest::binary>>, selector, declaration_block, depth, acc),
    do: parse(rest, selector, <<declaration_block::binary, char>>, depth, acc)

  defp remove_at_rule(input, depth), do: remove_at_rule(input, depth, nil)

  defp remove_at_rule(<<>>, _depth, _quote_char), do: ""

  defp remove_at_rule(<<quote_char, rest::binary>>, depth, nil) when quote_char in [?", ?'],
    do: remove_at_rule(rest, depth, quote_char)

  defp remove_at_rule(<<"\\", quote_char, rest::binary>>, depth, quote_char)
       when quote_char in [?", ?'],
       do: remove_at_rule(rest, depth, quote_char)

  defp remove_at_rule(<<quote_char, rest::binary>>, depth, quote_char),
    do: remove_at_rule(rest, depth, nil)

  defp remove_at_rule(<<";", rest::binary>>, 0, nil), do: rest
  defp remove_at_rule(<<"{", rest::binary>>, depth, nil), do: remove_at_rule(rest, depth + 1, nil)
  defp remove_at_rule(<<"}", rest::binary>>, depth, nil) when depth <= 1, do: rest
  defp remove_at_rule(<<"}", rest::binary>>, depth, nil), do: remove_at_rule(rest, depth - 1, nil)
  defp remove_at_rule(<<_, rest::binary>>, depth, nil), do: remove_at_rule(rest, depth, nil)

  defp remove_at_rule(<<_, rest::binary>>, depth, quote_char),
    do: remove_at_rule(rest, depth, quote_char)

  defp build_rule(group, declarations) do
    specificity =
      group
      |> parse_selector_group()
      |> Enum.reduce({0, 0, 0, 0}, fn step, {0 = _inline?, ids, classes, elements} ->
        step_ids = (step.id && 1) || 0
        pseudo_classes = Enum.count(step.pseudos, &(&1.kind == :pseudo_class))
        step_classes = length(step.classes) + length(step.attrs) + pseudo_classes
        pseudo_elements = Enum.count(step.pseudos, &(&1.kind == :pseudo_element))
        step_elements = ((step.tag && step.tag != "*" && 1) || 0) + pseudo_elements

        {0, ids + step_ids, classes + step_classes, elements + step_elements}
      end)

    %{selector: group, declarations: declarations, specificity: specificity}
  end

  @doc """
  Splits a comma-separated selector string into individual selectors.

  ## Examples

      iex> Premailex.CSSParser.split_selector_groups("div, .foo")
      ["div", ".foo"]

      iex> Premailex.CSSParser.split_selector_groups("div > p, a[href]")
      ["div > p", "a[href]"]
  """
  @spec split_selector_groups(String.t()) :: [String.t()]
  def split_selector_groups(selector) do
    selector
    |> split_selector_groups("", 0, 0, nil, [])
    |> Enum.reverse()
  end

  defp split_selector_groups(<<>>, buffer, _bracket_depth, _paren_depth, _quote_char, groups) do
    flush_selector_group_buffer(buffer, groups)
  end

  defp split_selector_groups(
         <<quote_char, rest::binary>>,
         buffer,
         bracket_depth,
         paren_depth,
         nil,
         groups
       )
       when quote_char in [?\", ?'] do
    split_selector_groups(
      rest,
      <<buffer::binary, quote_char>>,
      bracket_depth,
      paren_depth,
      quote_char,
      groups
    )
  end

  defp split_selector_groups(
         <<"\\", quote_char, rest::binary>>,
         buffer,
         bracket_depth,
         paren_depth,
         quote_char,
         groups
       ) do
    split_selector_groups(
      rest,
      <<buffer::binary, "\\", quote_char>>,
      bracket_depth,
      paren_depth,
      quote_char,
      groups
    )
  end

  defp split_selector_groups(
         <<quote_char, rest::binary>>,
         buffer,
         bracket_depth,
         paren_depth,
         quote_char,
         groups
       ) do
    split_selector_groups(
      rest,
      <<buffer::binary, quote_char>>,
      bracket_depth,
      paren_depth,
      nil,
      groups
    )
  end

  defp split_selector_groups(
         <<char, rest::binary>>,
         buffer,
         bracket_depth,
         paren_depth,
         quote_char,
         groups
       )
       when quote_char != nil do
    split_selector_groups(
      rest,
      <<buffer::binary, char>>,
      bracket_depth,
      paren_depth,
      quote_char,
      groups
    )
  end

  defp split_selector_groups(
         <<"\\,", rest::binary>>,
         buffer,
         bracket_depth,
         paren_depth,
         nil,
         groups
       ) do
    split_selector_groups(
      rest,
      <<buffer::binary, "\\,">>,
      bracket_depth,
      paren_depth,
      nil,
      groups
    )
  end

  defp split_selector_groups(
         <<"[", rest::binary>>,
         buffer,
         bracket_depth,
         paren_depth,
         nil,
         groups
       ) do
    split_selector_groups(
      rest,
      <<buffer::binary, "[">>,
      bracket_depth + 1,
      paren_depth,
      nil,
      groups
    )
  end

  defp split_selector_groups(
         <<"]", rest::binary>>,
         buffer,
         bracket_depth,
         paren_depth,
         nil,
         groups
       )
       when bracket_depth > 0 do
    split_selector_groups(
      rest,
      <<buffer::binary, "]">>,
      bracket_depth - 1,
      paren_depth,
      nil,
      groups
    )
  end

  defp split_selector_groups(
         <<"(", rest::binary>>,
         buffer,
         bracket_depth,
         paren_depth,
         nil,
         groups
       ) do
    split_selector_groups(
      rest,
      <<buffer::binary, "(">>,
      bracket_depth,
      paren_depth + 1,
      nil,
      groups
    )
  end

  defp split_selector_groups(
         <<")", rest::binary>>,
         buffer,
         bracket_depth,
         paren_depth,
         nil,
         groups
       )
       when paren_depth > 0 do
    split_selector_groups(
      rest,
      <<buffer::binary, ")">>,
      bracket_depth,
      paren_depth - 1,
      nil,
      groups
    )
  end

  defp split_selector_groups(<<",", rest::binary>>, buffer, 0, 0, nil, groups) do
    split_selector_groups(rest, "", 0, 0, nil, flush_selector_group_buffer(buffer, groups))
  end

  defp split_selector_groups(
         <<char, rest::binary>>,
         buffer,
         bracket_depth,
         paren_depth,
         quote_char,
         groups
       ) do
    split_selector_groups(
      rest,
      <<buffer::binary, char>>,
      bracket_depth,
      paren_depth,
      quote_char,
      groups
    )
  end

  defp flush_selector_group_buffer(buffer, groups) do
    case String.trim(buffer) do
      "" -> groups
      trimmed -> [trimmed | groups]
    end
  end

  @doc """
  Parses a selector string into a list of selector groups.

  Each selector group is a list of steps, where each step is a map containing
  the tag, id, classes, attributes, pseudo-classes/elements, and combinator.
  Steps are ordered right to left.

  Selectors that fail to parse are dropped and a debug log is emitted.

  ## Examples

      iex> Premailex.CSSParser.parse_selector_groups("div.foo")
      [[%{tag: "div", id: nil, classes: ["foo"], attrs: [], pseudos: [], combinator: nil}]]

      iex> Premailex.CSSParser.parse_selector_groups("body > p")
      [
        [
          %{tag: "p", id: nil, classes: [], attrs: [], pseudos: [], combinator: nil},
          %{tag: "body", id: nil, classes: [], attrs: [], pseudos: [], combinator: :child}
        ]
      ]
  """
  @spec parse_selector_groups(String.t()) :: [selector_group()]
  def parse_selector_groups(selector) do
    selector
    |> split_selector_groups()
    |> Enum.map(&parse_selector_group/1)
  end

  defp parse_selector_group(selector_group) do
    case parse_selector_steps(selector_group, @initial_selector_state) do
      {:ok, steps, nil} ->
        steps

      _invalid ->
        Logger.debug(fn -> "Invalid selector group \"#{selector_group}\". Ignoring." end)

        []
    end
  end

  defp parse_selector_steps(<<>>, %{bracket_depth: bd, paren_depth: pd}) when bd > 0 or pd > 0,
    do: :error

  defp parse_selector_steps(<<>>, %{bracket_depth: 0, paren_depth: 0} = state) do
    case update_selector_step(state.type, state.step, state.buffer) do
      {:ok, step} -> flush_selector_step(step, state.pending_relation, state.steps)
      :error -> :error
    end
  end

  defp parse_selector_steps(
         <<"#", rest::binary>>,
         %{bracket_depth: 0, paren_depth: 0, quote_char: nil} = state
       ),
       do: update_step_and_set_type(rest, state, :id)

  defp parse_selector_steps(
         <<".", rest::binary>>,
         %{bracket_depth: 0, paren_depth: 0, quote_char: nil} = state
       ),
       do: update_step_and_set_type(rest, state, :class)

  defp parse_selector_steps(
         <<":", rest::binary>>,
         %{type: :pseudo_class, buffer: "", bracket_depth: 0, paren_depth: 0, quote_char: nil} =
           state
       ),
       do: parse_selector_steps(rest, %{state | type: :pseudo_element})

  defp parse_selector_steps(
         <<":", rest::binary>>,
         %{type: _any, bracket_depth: 0, paren_depth: 0, quote_char: nil} = state
       ),
       do: update_step_and_set_type(rest, state, :pseudo_class)

  defp parse_selector_steps(<<quote_char, rest::binary>>, %{quote_char: nil} = state)
       when quote_char in [?", ?'] do
    parse_selector_steps(rest, %{
      state
      | buffer: <<state.buffer::binary, quote_char>>,
        quote_char: quote_char
    })
  end

  defp parse_selector_steps(
         <<"\\", quote_char, rest::binary>>,
         %{quote_char: quote_char} = state
       )
       when quote_char in [?", ?'] do
    parse_selector_steps(rest, %{state | buffer: <<state.buffer::binary, "\\", quote_char>>})
  end

  defp parse_selector_steps(<<quote_char, rest::binary>>, %{quote_char: quote_char} = state)
       when quote_char in [?", ?'] do
    parse_selector_steps(rest, %{
      state
      | buffer: <<state.buffer::binary, quote_char>>,
        quote_char: nil
    })
  end

  defp parse_selector_steps(
         <<char, rest::binary>>,
         %{bracket_depth: 0, paren_depth: 0, quote_char: nil} = state
       )
       when char in @selector_whitespace do
    case update_selector_step(state.type, state.step, state.buffer) do
      {:ok, step} ->
        {:ok, next_steps, next_pending} =
          flush_selector_step(step, state.pending_relation, state.steps)

        parse_selector_steps(rest, %{
          @initial_selector_state
          | pending_relation: next_pending,
            steps: next_steps
        })

      :error ->
        :error
    end
  end

  defp parse_selector_steps(
         <<"||", rest::binary>>,
         %{bracket_depth: 0, paren_depth: 0, quote_char: nil} = state
       ) do
    flush_step_and_set_relation(rest, state, :column)
  end

  defp parse_selector_steps(
         <<">", rest::binary>>,
         %{bracket_depth: 0, paren_depth: 0, quote_char: nil} = state
       ) do
    flush_step_and_set_relation(rest, state, :child)
  end

  defp parse_selector_steps(
         <<"+", rest::binary>>,
         %{bracket_depth: 0, paren_depth: 0, quote_char: nil} = state
       ) do
    flush_step_and_set_relation(rest, state, :adjacent)
  end

  defp parse_selector_steps(
         <<"~", rest::binary>>,
         %{bracket_depth: 0, paren_depth: 0, quote_char: nil} = state
       ) do
    flush_step_and_set_relation(rest, state, :sibling)
  end

  defp parse_selector_steps(
         <<"[", rest::binary>>,
         %{bracket_depth: 0, paren_depth: 0, quote_char: nil} = state
       ) do
    case update_selector_step(state.type, state.step, state.buffer) do
      {:ok, step} ->
        parse_selector_steps(rest, %{
          state
          | type: :attribute,
            step: step,
            buffer: "",
            bracket_depth: 1
        })

      :error ->
        :error
    end
  end

  defp parse_selector_steps(
         <<"]", rest::binary>>,
         %{type: :attribute, bracket_depth: 1, quote_char: nil} = state
       ) do
    case update_selector_step(:attribute, state.step, state.buffer) do
      {:ok, step} ->
        parse_selector_steps(rest, %{
          state
          | type: :tag,
            step: step,
            buffer: "",
            bracket_depth: 0
        })

      :error ->
        :error
    end
  end

  defp parse_selector_steps(<<"[", _rest::binary>>, %{paren_depth: 0, quote_char: nil}),
    do: :error

  defp parse_selector_steps(<<"]", _rest::binary>>, %{paren_depth: 0, quote_char: nil}),
    do: :error

  defp parse_selector_steps(<<"(", _rest::binary>>, %{
         type: kind,
         buffer: "",
         bracket_depth: 0,
         paren_depth: 0,
         quote_char: nil
       })
       when kind in [:pseudo_class, :pseudo_element],
       do: :error

  defp parse_selector_steps(
         <<"(", rest::binary>>,
         %{type: kind, bracket_depth: 0, paren_depth: 0, quote_char: nil} = state
       )
       when kind in [:pseudo_class, :pseudo_element] do
    parse_selector_steps(rest, %{
      state
      | type: {kind, state.buffer},
        buffer: "",
        paren_depth: 1
    })
  end

  defp parse_selector_steps(
         <<")", rest::binary>>,
         %{type: {kind, name}, bracket_depth: 0, paren_depth: 1, quote_char: nil} = state
       )
       when kind in [:pseudo_class, :pseudo_element] do
    pseudo = build_pseudo(name, state.buffer, kind)
    step = %{state.step | pseudos: [pseudo | state.step.pseudos]}

    parse_selector_steps(rest, %{state | type: :tag, step: step, buffer: "", paren_depth: 0})
  end

  defp parse_selector_steps(<<"(", rest::binary>>, %{paren_depth: pd, quote_char: nil} = state)
       when pd > 0 do
    parse_selector_steps(rest, %{
      state
      | buffer: <<state.buffer::binary, "(">>,
        paren_depth: pd + 1
    })
  end

  defp parse_selector_steps(<<")", rest::binary>>, %{paren_depth: pd, quote_char: nil} = state)
       when pd > 0 do
    parse_selector_steps(rest, %{
      state
      | buffer: <<state.buffer::binary, ")">>,
        paren_depth: pd - 1
    })
  end

  defp parse_selector_steps(<<"(", _rest::binary>>, %{quote_char: nil}), do: :error
  defp parse_selector_steps(<<")", _rest::binary>>, %{quote_char: nil}), do: :error

  defp parse_selector_steps(<<char, rest::binary>>, state) do
    parse_selector_steps(rest, %{state | buffer: <<state.buffer::binary, char>>})
  end

  defp update_selector_step(:tag, step, ""), do: {:ok, step}
  defp update_selector_step(:tag, step, buffer), do: {:ok, %{step | tag: buffer}}

  defp update_selector_step(:id, _step, ""), do: :error
  defp update_selector_step(:id, step, buffer), do: {:ok, %{step | id: buffer}}

  defp update_selector_step(:class, _step, ""), do: :error

  defp update_selector_step(:class, step, buffer),
    do: {:ok, %{step | classes: [buffer | step.classes]}}

  defp update_selector_step(:attribute, step, buffer) do
    case parse_attribute_selector(buffer, "") do
      {:ok, attr} -> {:ok, %{step | attrs: [attr | step.attrs]}}
      :error -> :error
    end
  end

  defp update_selector_step(:pseudo_class, _step, ""), do: :error

  defp update_selector_step(:pseudo_class, step, name),
    do: {:ok, %{step | pseudos: [build_pseudo(name, nil, :pseudo_class) | step.pseudos]}}

  defp update_selector_step(:pseudo_element, _step, ""), do: :error

  defp update_selector_step(:pseudo_element, step, name),
    do: {:ok, %{step | pseudos: [build_pseudo(name, nil, :pseudo_element) | step.pseudos]}}

  defp flush_selector_step(@step, pending_relation, steps), do: {:ok, steps, pending_relation}

  defp flush_selector_step(step, pending_relation, steps) do
    step = %{
      step
      | classes: Enum.reverse(step.classes),
        attrs: Enum.reverse(step.attrs),
        pseudos: Enum.reverse(step.pseudos)
    }

    do_flush_selector_step(step, steps, pending_relation)
  end

  defp do_flush_selector_step(step, [], nil), do: {:ok, [step], nil}

  defp do_flush_selector_step(step, [previous_step | previous_steps], pending_relation) do
    previous_step = %{previous_step | combinator: pending_relation || :descendant}

    {:ok, [step, previous_step | previous_steps], nil}
  end

  defp flush_step_and_set_relation(rest, state, relation) do
    case update_selector_step(state.type, state.step, state.buffer) do
      {:ok, step} ->
        case flush_selector_step(step, state.pending_relation, state.steps) do
          {:ok, [], _} ->
            :error

          {:ok, final_steps, nil} ->
            parse_selector_steps(rest, %{
              @initial_selector_state
              | pending_relation: relation,
                steps: final_steps
            })

          {:ok, _, _} ->
            :error
        end

      :error ->
        :error
    end
  end

  defp update_step_and_set_type(rest, state, type) do
    case update_selector_step(state.type, state.step, state.buffer) do
      {:ok, step} ->
        parse_selector_steps(rest, %{state | type: type, step: step, buffer: ""})

      :error ->
        :error
    end
  end

  defp parse_attribute_selector(<<>>, ""), do: :error
  defp parse_attribute_selector(<<>>, name), do: {:ok, name}

  defp parse_attribute_selector(<<char, rest::binary>>, "") when char in @selector_whitespace,
    do: parse_attribute_selector(rest, "")

  defp parse_attribute_selector(<<char, rest::binary>>, name) when char in @selector_whitespace do
    case String.trim_leading(rest) do
      "" -> {:ok, name}
      <<"=", rest::binary>> -> parse_attribute_selector(rest, name, "")
      _other_key -> :error
    end
  end

  defp parse_attribute_selector(<<"=", rest::binary>>, name),
    do: parse_attribute_selector(rest, name, "")

  defp parse_attribute_selector(<<char, rest::binary>>, name),
    do: parse_attribute_selector(rest, <<name::binary, char>>)

  defp parse_attribute_selector(<<>>, name, value), do: {:ok, {name, value}}

  defp parse_attribute_selector(<<char, rest::binary>>, name, "")
       when char in @selector_whitespace,
       do: parse_attribute_selector(rest, name, "")

  defp parse_attribute_selector(<<quote_char, rest::binary>>, name, "")
       when quote_char in [?", ?'],
       do: parse_attribute_selector(rest, name, "", quote_char)

  defp parse_attribute_selector(<<char, _::binary>>, _name, _value) when char in [?", ?'],
    do: :error

  defp parse_attribute_selector(<<char, rest::binary>>, name, value)
       when char in @selector_whitespace do
    case String.trim_leading(rest) do
      "" -> {:ok, {name, value}}
      _other_value -> :error
    end
  end

  defp parse_attribute_selector(<<char, rest::binary>>, name, value),
    do: parse_attribute_selector(rest, name, <<value::binary, char>>)

  defp parse_attribute_selector(<<"\\", quote_char, rest::binary>>, name, value, quote_char),
    do: parse_attribute_selector(rest, name, <<value::binary, quote_char>>, quote_char)

  defp parse_attribute_selector(<<quote_char, rest::binary>>, name, value, quote_char) do
    case String.trim_leading(rest) do
      "" -> {:ok, {name, value}}
      _other_value -> :error
    end
  end

  defp parse_attribute_selector(<<char, rest::binary>>, name, value, quote_char),
    do: parse_attribute_selector(rest, name, <<value::binary, char>>, quote_char)

  defp build_pseudo(name, expression, :pseudo_class) when name in @nth_pseudo_classes do
    %{name: name, expression: expression, kind: :pseudo_class, nth: parse_an_plus_b(expression)}
  end

  defp build_pseudo(name, expression, kind),
    do: %{name: name, expression: expression, kind: kind}

  defp parse_an_plus_b(nil), do: :invalid
  defp parse_an_plus_b(expr) when is_binary(expr), do: parse_anb(String.downcase(expr))

  defp parse_anb(<<c, rest::binary>>) when c in @selector_whitespace, do: parse_anb(rest)
  defp parse_anb(<<>>), do: :invalid

  defp parse_anb("odd" <> rest), do: parse_anb_eof(rest, {2, 1})
  defp parse_anb("even" <> rest), do: parse_anb_eof(rest, {2, 0})

  defp parse_anb(<<"+", rest::binary>>), do: parse_anb_after_sign(rest, 1)
  defp parse_anb(<<"-", rest::binary>>), do: parse_anb_after_sign(rest, -1)
  defp parse_anb(rest), do: parse_anb_after_sign(rest, 1)

  defp parse_anb_after_sign(<<"n", rest::binary>>, sign),
    do: parse_anb_after_n(rest, sign)

  defp parse_anb_after_sign(<<d, _::binary>> = rest, sign) when d in ?0..?9,
    do: parse_anb_a_digits(rest, sign, 0)

  defp parse_anb_after_sign(_, _), do: :invalid

  defp parse_anb_a_digits(<<d, rest::binary>>, sign, acc) when d in ?0..?9,
    do: parse_anb_a_digits(rest, sign, acc * 10 + (d - ?0))

  defp parse_anb_a_digits(<<"n", rest::binary>>, sign, acc),
    do: parse_anb_after_n(rest, sign * acc)

  defp parse_anb_a_digits(<<>>, sign, acc), do: {0, sign * acc}
  defp parse_anb_a_digits(_, _, _), do: :invalid

  defp parse_anb_after_n(<<c, rest::binary>>, a) when c in @selector_whitespace,
    do: parse_anb_after_n(rest, a)

  defp parse_anb_after_n(<<"+", rest::binary>>, a), do: parse_anb_before_b(rest, a, 1)
  defp parse_anb_after_n(<<"-", rest::binary>>, a), do: parse_anb_before_b(rest, a, -1)
  defp parse_anb_after_n(<<>>, a), do: {a, 0}
  defp parse_anb_after_n(_, _), do: :invalid

  defp parse_anb_before_b(<<c, rest::binary>>, a, sign) when c in @selector_whitespace,
    do: parse_anb_before_b(rest, a, sign)

  defp parse_anb_before_b(<<d, rest::binary>>, a, sign) when d in ?0..?9,
    do: parse_anb_b_digits(rest, a, sign, d - ?0)

  defp parse_anb_before_b(_, _, _), do: :invalid

  defp parse_anb_b_digits(<<d, rest::binary>>, a, sign, acc) when d in ?0..?9,
    do: parse_anb_b_digits(rest, a, sign, acc * 10 + (d - ?0))

  defp parse_anb_b_digits(<<c, rest::binary>>, a, sign, acc) when c in @selector_whitespace,
    do: parse_anb_eof(rest, {a, sign * acc})

  defp parse_anb_b_digits(<<>>, a, sign, acc), do: {a, sign * acc}
  defp parse_anb_b_digits(_, _, _, _), do: :invalid

  defp parse_anb_eof(<<c, rest::binary>>, result) when c in @selector_whitespace,
    do: parse_anb_eof(rest, result)

  defp parse_anb_eof(<<>>, result), do: result
  defp parse_anb_eof(_, _), do: :invalid

  @doc """
  Parses a CSS declaration block string into a list of declarations.

  Each declaration is a map containing the property, value, and a `!important`
  flag.

  ## Examples

      iex> Premailex.CSSParser.parse_declaration_block("background-color: #fff; color: red;")
      [
        %{property: "background-color", value: "#fff", important?: false},
        %{property: "color", value: "red", important?: false}
      ]
  """
  @spec parse_declaration_block(String.t()) :: [declaration()]
  def parse_declaration_block(declaration_block),
    do: parse_declaration_block(declaration_block, "", nil, 0, nil, [])

  defp parse_declaration_block(<<>>, _buffer, nil, _parens_depth, _quote_char, acc),
    do: Enum.reverse(acc)

  defp parse_declaration_block(<<>>, value, property, _parens_depth, _quote_char, acc),
    do: Enum.reverse(add_declaration(acc, property, value))

  defp parse_declaration_block(<<":", rest::binary>>, property, nil, 0, nil, acc),
    do: parse_declaration_block(rest, "", property, 0, nil, acc)

  defp parse_declaration_block(<<";", rest::binary>>, _buffer, nil, 0, nil, acc),
    do: parse_declaration_block(rest, "", nil, 0, nil, acc)

  defp parse_declaration_block(<<";", rest::binary>>, value, property, 0, nil, acc),
    do: parse_declaration_block(rest, "", nil, 0, nil, add_declaration(acc, property, value))

  defp parse_declaration_block(
         <<quote_char, rest::binary>>,
         buffer,
         property,
         parens_depth,
         nil,
         acc
       )
       when quote_char in [?", ?'] do
    parse_declaration_block(
      rest,
      <<buffer::binary, quote_char>>,
      property,
      parens_depth,
      quote_char,
      acc
    )
  end

  defp parse_declaration_block(
         <<"\\", quote_char, rest::binary>>,
         buffer,
         property,
         parens_depth,
         quote_char,
         acc
       )
       when quote_char in [?", ?'] do
    parse_declaration_block(
      rest,
      <<buffer::binary, "\\", quote_char>>,
      property,
      parens_depth,
      quote_char,
      acc
    )
  end

  defp parse_declaration_block(
         <<quote_char, rest::binary>>,
         buffer,
         property,
         parens_depth,
         quote_char,
         acc
       )
       when quote_char in [?", ?'],
       do:
         parse_declaration_block(
           rest,
           <<buffer::binary, quote_char>>,
           property,
           parens_depth,
           nil,
           acc
         )

  defp parse_declaration_block(<<"(", rest::binary>>, buffer, property, parens_depth, nil, acc),
    do:
      parse_declaration_block(rest, <<buffer::binary, "(">>, property, parens_depth + 1, nil, acc)

  defp parse_declaration_block(<<")", rest::binary>>, buffer, property, parens_depth, nil, acc)
       when parens_depth > 0,
       do:
         parse_declaration_block(
           rest,
           <<buffer::binary, ")">>,
           property,
           parens_depth - 1,
           nil,
           acc
         )

  defp parse_declaration_block(
         <<char, rest::binary>>,
         buffer,
         property,
         parens_depth,
         quote_char,
         acc
       ),
       do:
         parse_declaration_block(
           rest,
           <<buffer::binary, char>>,
           property,
           parens_depth,
           quote_char,
           acc
         )

  defp add_declaration(acc, property, value) do
    case {String.trim(property), String.trim(value)} do
      {"", _} ->
        acc

      {_, ""} ->
        acc

      {property, value} ->
        declaration =
          %{
            property: property,
            value: value,
            important?: value |> String.downcase() |> String.ends_with?("!important")
          }

        [declaration | acc]
    end
  end

  @doc """
  Combines CSS rules into a final list of declarations using the CSS Cascade
  Level 4 algorithm.

  Conflicts between declarations for the same property are resolved by
  `!important` and then by specificity.

  See https://www.w3.org/TR/css-cascade-4/#cascading for details.

  ## Examples

      iex> rules = Premailex.CSSParser.parse("p {background-color: #fff !important; color: #000;} p {background-color: #000;}")
      iex> Premailex.CSSParser.cascade(rules)
      [
        %{property: "background-color", value: "#fff !important", important?: true},
        %{property: "color", value: "#000", important?: false}
      ]
  """
  @spec cascade([rule()]) :: [declaration()]
  def cascade(rules) do
    rules
    |> Enum.reduce(%{}, fn %{declarations: declarations, specificity: specificity}, acc ->
      Enum.reduce(declarations, acc, &cascade_declaration(&2, &1, specificity))
    end)
    |> Enum.reduce([], fn {_property, {declaration, _specificity}}, acc ->
      [declaration | acc]
    end)
    |> Enum.reverse()
  end

  defp cascade_declaration(acc, declaration, specificity) do
    Map.update(acc, declaration.property, {declaration, specificity}, fn {current_declaration,
                                                                          current_specificity} ->
      case {current_declaration.important?, declaration.important?} do
        {true, false} ->
          {current_declaration, current_specificity}

        {false, true} ->
          {declaration, specificity}

        {important, important} ->
          (specificity >= current_specificity && {declaration, specificity}) ||
            {current_declaration, current_specificity}
      end
    end)
  end

  @doc """
  Converts a rule declaration or list of declarations into a string.

  ## Examples

      iex> declarations = Premailex.CSSParser.parse_declaration_block("background-color: #fff !important; color: red;")
      iex> Premailex.CSSParser.to_string(declarations)
      "background-color: #fff !important; color: red;"

      iex> declarations = Premailex.CSSParser.parse_declaration_block("background-color: #fff")
      iex> Premailex.CSSParser.to_string(declarations)
      "background-color: #fff;"
  """
  @spec to_string([declaration()] | declaration()) :: String.t()
  def to_string(declarations) when is_list(declarations) do
    Enum.map_join(declarations, " ", &__MODULE__.to_string/1)
  end

  def to_string(%{property: property, value: value}), do: "#{property}: #{value};"
end
