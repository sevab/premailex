defmodule Premailex.HTTPAdapter.Httpc do
  @moduledoc """
  HTTP adapter module for making HTTP requests with `m::httpc`.

  SSL verification is enabled automatically when both
  [`:certifi`](https://hexdocs.pm/certifi/) and
  [`:ssl_verify_fun`](https://hex.pm/packages/ssl_verify_fun) are present at
  compile time. Add them to your dependencies in `mix.exs`:

      defp deps do
        [
          {:certifi, "~> 2.4"},
          {:ssl_verify_fun, "~> 1.1"}
        ]
      end

  If these dependencies are added after Premailex has been compiled,
  recompile Premailex to enable SSL verification support:

      mix deps.compile premailex --force
  """
  alias Premailex.HTTPAdapter

  @behaviour HTTPAdapter

  @impl HTTPAdapter
  def request(method, url, body, headers, httpc_opts \\ nil) do
    headers = headers ++ [HTTPAdapter.user_agent_header()]
    request = httpc_request(url, body, headers)

    method
    |> :httpc.request(request, parse_httpc_opts(httpc_opts, url), [])
    |> format_response()
  end

  defp httpc_request(url, body, headers) do
    url = to_charlist(url)
    headers = Enum.map(headers, fn {k, v} -> {to_charlist(k), to_charlist(v)} end)

    do_httpc_request(url, body, headers)
  end

  defp do_httpc_request(url, nil, headers), do: {url, headers}

  defp do_httpc_request(url, body, headers) do
    {content_type, headers} = split_content_type_headers(headers)
    body = to_charlist(body)

    {url, headers, content_type, body}
  end

  defp split_content_type_headers(headers) do
    case List.keytake(headers, ~c"content-type", 0) do
      nil -> {~c"text/plain", headers}
      {{_, ct}, headers} -> {ct, headers}
    end
  end

  defp format_response({:ok, {{_, status, _}, headers, body}}) do
    headers =
      Enum.map(headers, fn {key, value} ->
        {String.downcase(to_string(key)), to_string(value)}
      end)

    body = IO.iodata_to_binary(body)

    {:ok, %{status: status, headers: headers, body: body}}
  end

  defp format_response({:error, error}), do: {:error, error}

  defp parse_httpc_opts(nil, url), do: default_httpc_opts(url)
  defp parse_httpc_opts(opts, _url), do: opts

  if Code.ensure_loaded?(:certifi) and Code.ensure_loaded?(:ssl_verify_hostname) do
    defp default_httpc_opts(url) do
      uri = URI.parse(url)

      case uri.scheme do
        "https" -> [ssl: ssl_opts(uri)]
        _ -> []
      end
    end

    defp ssl_opts(uri) do
      [
        verify: :verify_peer,
        depth: 99,
        cacerts: :certifi.cacerts(),
        verify_fun: {&:ssl_verify_hostname.verify_fun/3, check_hostname: to_charlist(uri.host)},
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    end
  else
    defp default_httpc_opts(_url), do: []
  end
end
