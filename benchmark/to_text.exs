Mix.Task.run("app.start")
Code.require_file("benchmark.exs", __DIR__)

defmodule Benchmark.ToText do
  @moduledoc """
  Benchmarks `Premailex.to_text/1` across realistic email tree sizes.

  `nodes` is the DOM element target count of the generated input; the body is
  filled with whole sections and then padded with single-node `<p>` chunks
  until the target is met.

  Run with:

      HTML_PARSER=Xmerl mix run benchmark/to_text.exs
  """

  def run do
    cases =
      for n <- [50, 150, 500, 1_000] do
        html = generate_html(n)

        {
          ["`to_text/1`", n],
          fn -> Premailex.to_text(html) end
        }
      end

    Benchmark.run!(cases)
  end

  defp generate_html(target_nodes) do
    target_nodes = max(0, target_nodes - 4)

    """
    <!DOCTYPE html>
    <html>
      <head><title>Common email</title></head>
      <body>
        #{generate_section_html(target_nodes, 1, "")}
      </body>
    </html>
    """
  end

  defp generate_section_html(target_nodes, i, acc) when target_nodes >= 19 do
    generate_section_html(
      target_nodes - 19,
      i + 1,
      """
      #{acc}
      <table>
        <tr>
          <td>
            <h2>Section #{i}</h2>
            <p class="lead">Lead paragraph <a href="https://example.com/#{i}">with a link</a> in it.</p>
            <p>Some <span>inline</span> text and more regular content for section #{i}.</p>
            <ul><li>Bullet one</li><li>Bullet two</li><li>Bullet three</li></ul>
            <ol><li>First</li><li>Second</li></ol>
            <hr>
            <p class="small">Footnote about section #{i}.</p>
            <p><a href="#" class="button">Call to action #{i}</a></p>
          </td>
        </tr>
      </table>
      """
    )
  end

  defp generate_section_html(target_nodes, i, acc) when target_nodes >= 1 do
    generate_section_html(
      target_nodes - 1,
      i + 1,
      """
      #{acc}
      <p>Paragraph #{i}</p>
      """
    )
  end

  defp generate_section_html(_target_nodes, _i, acc), do: acc
end

Benchmark.ToText.run()
