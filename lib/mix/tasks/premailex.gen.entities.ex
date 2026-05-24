if Code.ensure_loaded?(JSON) do
  defmodule Mix.Tasks.Premailex.Gen.Entities do
    @shortdoc "Regenerates priv/entities.txt from the WHATWG HTML entities reference"

    @moduledoc """
    Downloads the canonical WHATWG HTML entities JSON and converts it to the
    flat text format used by `Premailex.HTMLParser.Xmerl`.

    This mix task is not included in releases and is only used by maintainers.

    ## Examples

        $ mix premailex.gen.entities

    ## Command line options

      * `--url` - URL to download the entities JSON from (defaults to the WHATWG reference)
      * `--output` - output file path (defaults to `priv/entities.txt`)
    """
    use Mix.Task

    alias Premailex.HTTPAdapter.Httpc

    @entities_url "https://html.spec.whatwg.org/entities.json"
    @output_path "priv/entities.txt"

    @impl true
    def run(args) do
      {opts, _, _} = OptionParser.parse(args, strict: [url: :string, output: :string])
      url = Keyword.get(opts, :url, @entities_url)
      output_path = Keyword.get(opts, :output, @output_path)

      {:ok, _} = Application.ensure_all_started(:inets)
      {:ok, _} = Application.ensure_all_started(:ssl)

      Mix.shell().info("Downloading #{url}...")

      entries =
        url
        |> fetch_json!()
        |> Enum.map(fn {name, %{"codepoints" => codepoints}} ->
          Enum.join([name | Enum.map(codepoints, &Integer.to_string/1)], " ")
        end)

      File.write!(output_path, Enum.join(entries, "\n") <> "\n")

      Mix.shell().info("Wrote #{length(entries)} entries to #{output_path}")
    end

    defp fetch_json!(url) do
      case Httpc.request(:get, url, nil, [], nil) do
        {:ok, %{status: 200, body: body}} ->
          body
          |> JSON.decode!()
          |> Enum.sort_by(&elem(&1, 0))

        {:ok, %{status: status}} ->
          Mix.raise("Unexpected HTTP status #{status} from #{url}")

        {:error, reason} ->
          Mix.raise("Request to #{url} failed: #{inspect(reason)}")
      end
    end
  end
end
