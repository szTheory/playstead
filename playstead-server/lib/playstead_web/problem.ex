defmodule PlaysteadWeb.Problem do
  @moduledoc """
  RFC 9457 `application/problem+json` rendering (D-22).

  There is no shipped Plug/Phoenix library for RFC 9457 as of this
  phase's research — this module, `PlaysteadWeb.ErrorCodes`, and
  `PlaysteadWeb.Plugs.ApiProblemHandler` hand-build the layer.
  """

  import Plug.Conn

  @doc """
  Sends an `application/problem+json` response.

  `code` must be an atom key in `PlaysteadWeb.ErrorCodes.registry/0`
  (or any atom — unknown codes fall back to a generic title and
  status 500 via `ErrorCodes`). `status` is the HTTP status to send.
  `detail` is a privacy-safe, generic string — never a filesystem
  path, filename, hash, token, or credential. `extras` is merged into
  the body, e.g. a structured `remedy` object.

  The `correlation_id` is fresh, random, `:crypto.strong_rand_bytes/1`
  based — never derived from the request path, params, filenames, or
  any credential — and is set on both the body and the
  `x-correlation-id` response header.
  """
  @spec send_problem(Plug.Conn.t(), pos_integer(), atom(), String.t(), map()) :: Plug.Conn.t()
  def send_problem(conn, status, code, detail, extras \\ %{}) do
    correlation_id = generate_correlation_id()

    body =
      %{
        type: "about:blank",
        title: PlaysteadWeb.ErrorCodes.title_for(code),
        status: status,
        detail: detail,
        code: code,
        correlation_id: correlation_id
      }
      |> Map.merge(extras)

    conn
    |> put_resp_content_type("application/problem+json")
    |> put_resp_header("x-correlation-id", correlation_id)
    |> send_resp(status, Jason.encode!(body))
  end

  @doc "A fresh, random correlation ID. Never derived from request contents."
  @spec generate_correlation_id() :: String.t()
  def generate_correlation_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
