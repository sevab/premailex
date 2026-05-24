defmodule Premailex.HTTPAdapter do
  @moduledoc """
  HTTP client adapter behaviour.

  ## Usage

      defmodule MyHTTPAdapter do
        @behaviour Premailex.HTTPAdapter

        @impl true
        def request(method, url, body, headers, opts) do
          # Implement your HTTP request logic here using your preferred HTTP client library.
          # Return {:ok, response} or {:error, reason}.
        end
      end

  Configure Premailex to use a custom adapter:

      config :premailex,
        http_adapter: MyHTTPAdapter
  """

  @type method :: :get | :post
  @type body :: binary() | nil
  @type headers :: [{binary(), binary()}]

  @typedoc """
  An HTTP response returned by an adapter's `c:request/5`
  callback.
  """
  @type response :: %{
          status: non_neg_integer(),
          headers: headers(),
          body: binary()
        }

  @doc """
  Makes an HTTP request.
  """
  @callback request(method(), binary(), body(), headers(), Keyword.t()) ::
              {:ok, response()} | {:error, any()}

  @doc """
  Returns a `User-Agent` header tuple for use in HTTP requests.
  """
  @spec user_agent_header() :: {binary(), binary()}
  def user_agent_header do
    version = Application.spec(:premailex, :vsn) || "0.0.0"

    {"User-Agent", "Premailex-#{version}"}
  end
end
