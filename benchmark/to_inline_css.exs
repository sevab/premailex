Mix.Task.run("app.start")
Code.require_file("benchmark.exs", __DIR__)

defmodule Benchmark.ToInlineCSS do
  @moduledoc """
  Benchmarks `Premailex.to_inline_css/1` across two scenarios.

    * `common` — Matrix spans four email categories:

        Type                        DOM nodes    CSS rules
        Plain transactional         80–250       20–80
        Rich transactional          250–800      80–250
        Standard marketing          600–2000     150–600
        Heavy marketing/ecommerce   2000–8000+   500–2500+

      `nodes` is the DOM element target count of the generated input; the body
      is filled with whole sections and then padded with single-node `<p>` chunks
      until the target is met.

    * `wildcard` — Worst case cascade where every rule matches every tag.

  Run with:

      HTML_PARSER=Floki mix run benchmark/to_inline_css.exs
  """

  def run do
    common_cases =
      for {nodes, rules} <- [{150, 50}, {500, 200}, {1500, 500}, {5000, 1500}] do
        html = generate_common_html(nodes, rules)

        {
          ["`to_inline_css/1` - common", nodes, rules],
          fn -> Premailex.to_inline_css(html) end
        }
      end

    wildcard_cases =
      for nodes <- [1_000, 5_000, 10_000], rules <- [1, 20] do
        html = generate_wildcard_html(nodes, rules)

        {
          ["`to_inline_css/1` - wildcard", nodes, rules],
          fn -> Premailex.to_inline_css(html) end
        }
      end

    Benchmark.run!(
      common_cases ++ wildcard_cases,
      extra_columns: [{"rules", 5, :right}]
    )
  end

  defp generate_common_html(target_nodes, target_rules) do
    # Note: If the nodes are added or removed in the below HTML the subtracted
    # number must be updated
    target_nodes = max(0, target_nodes - 5)

    # Note: If CSS rules are added or removed in the below HTML the subtracted
    # number must be updated
    target_rules = max(0, target_rules - 1)

    {body, css} = generate_common_css_html(target_nodes, target_rules, 1, "", "")

    """
    <!DOCTYPE html>
    <html>
      <head>
        <title>Common email</title>
        <style>
          body { font-family: Arial, sans-serif; font-size: 14px; line-height: 22px; color: #333; margin: 0; }
          #{css}
        </style>
      </head>
      <body>
        #{body}
      </body>
    </html>
    """
  end

  defp generate_common_css_html(target_nodes, target_rules, i, "", "")
       when target_nodes >= 15 and target_rules >= 14 do
    generate_common_css_html(
      target_nodes - 15,
      target_rules - 14,
      i + 1,
      common_html_section(i),
      """
      table { border-collapse: collapse; }
      table.outer { width: 600px; }
      td.cell { padding: 12px; vertical-align: top; }
      td.cell.header { background: #f4f4f4; }
      h1 { font-size: 24px; color: #2eac6d; margin: 0 0 8px; }
      h2 { font-size: 18px; color: #444; margin: 0 0 6px; }
      p { margin: 0 0 12px; }
      p.lead { font-size: 16px; font-weight: bold; }
      a { color: #e95757; text-decoration: underline; }
      a.button { display: inline-block; padding: 8px 16px; background: #e95757; color: #fff; text-decoration: none; border-radius: 4px; }
      .muted { color: #888; }
      .small { font-size: 12px; }
      ul li { margin-bottom: 4px; }
      img { display: block; max-width: 100%; }
      """
    )
  end

  defp generate_common_css_html(target_nodes, target_rules, i, body, css)
       when target_nodes >= 15 do
    rule_count = min(14, target_rules)

    css =
      Enum.reduce(1..rule_count//1, css, fn j, css ->
        "#{css}\n.u-#{i}-#{j} {#{common_html_css_declaration(j)}}"
      end)

    generate_common_css_html(
      target_nodes - 15,
      target_rules - rule_count,
      i + 1,
      body <> common_html_section(i),
      css
    )
  end

  defp generate_common_css_html(0, target_rules, i, body, css) when target_rules >= 1 do
    generate_common_css_html(
      0,
      target_rules - 1,
      i + 1,
      body,
      "#{css}\n.no-match-rule-#{i} { color: rgb(#{rem(i * 37, 256)}, #{rem(i * 79, 256)}, #{rem(i * 113, 256)}); }"
    )
  end

  defp generate_common_css_html(target_nodes, target_rules, i, body, css)
       when target_nodes >= 1 do
    {css, target_rules} =
      case target_rules > 0 do
        true -> {"#{css}\np.u-#{i} {#{common_html_css_declaration(i)}}", target_rules - 1}
        false -> {css, target_rules}
      end

    body = "#{body}<p class=\"u-#{i}\">Paragraph #{i}</p>\n"

    generate_common_css_html(
      target_nodes - 1,
      target_rules,
      i + 1,
      body,
      css
    )
  end

  defp generate_common_css_html(0, 0, _i, body, css), do: {body, css}

  defp common_html_section(i) do
    """
    <table class="outer u-#{i}-1">
      <tr class="u-#{i}-2">
        <td class="cell header u-#{i}-3">
          <h2 class="u-#{i}-4">Section #{i}</h2>
          <p class="lead u-#{i}-5">
            Lead paragraph <a href="#" class="u-#{i}-6">with a link</a> in it.
          </p>
          <p class="u-#{i}-7">
            Some <span class="muted u-#{i}-8">muted text</span> and regular content.
          </p>
          <ul class="u-#{i}-9">
            <li class="u-#{i}-10">Bullet one</li>
            <li class="u-#{i}-11">Bullet two</li>
            <li class="u-#{i}-12">Bullet three</li>
          </ul>
          <p class="small u-#{i}-13">Footnote about section #{i}.</p>
          <p>
            <a href="#" class="button u-#{i}-14">Call to action #{i}</a>
          </p>
        </td>
      </tr>
    </table>
    """
  end

  defp common_html_css_declaration(n) do
    case rem(n, 3) do
      0 -> "color: rgb(#{rem(n * 37, 256)}, #{rem(n * 79, 256)}, #{rem(n * 113, 256)});"
      1 -> "font-size: #{n}px;"
      2 -> "padding-bottom: #{n}px;"
    end
  end

  defp generate_wildcard_html(target_nodes, target_rules) do
    tags = max(0, target_nodes - 4)

    rules_css =
      Enum.map_join(1..target_rules//1, "\n", fn i ->
        "* { prop#{i}: value#{i}; }"
      end)

    body =
      Enum.map_join(1..tags//1, "\n", fn i ->
        ~s(<p data-i="#{i}">Paragraph #{i}</p>)
      end)

    """
    <html>
      <head><style>#{rules_css}</style></head>
      <body>
        #{body}
      </body>
    </html>
    """
  end
end

Benchmark.ToInlineCSS.run()
