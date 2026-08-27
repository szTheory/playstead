defmodule PlaysteadWeb.ApiCase do
  @moduledoc """
  A JSON-oriented `ConnCase` variant for `/api/v1` contract tests
  (Wave 0 test-infrastructure item, VALIDATION.md).

  Sets `accept: application/json`, carries no session cookie, and
  provides `assert_problem/3` for asserting a response is a
  well-formed problem+json document with an expected code.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use PlaysteadWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import PlaysteadWeb.ApiCase

      @endpoint PlaysteadWeb.Endpoint
    end
  end

  setup tags do
    Playstead.DataCase.setup_sandbox(tags)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("accept", "application/json")

    {:ok, conn: conn}
  end

  @doc """
  Asserts `conn` holds a well-formed `application/problem+json`
  response with the given `status` and `code`, and that the
  `x-correlation-id` header matches the body's `correlation_id`.

  Use this for requests that return a normal (non-raising) conn.
  """
  def assert_problem(conn, status, code) do
    assert conn.status == status

    content_type =
      conn
      |> Plug.Conn.get_resp_header("content-type")
      |> List.first()

    assert String.starts_with?(content_type, "application/problem+json")

    body = Phoenix.ConnTest.json_response(conn, status)
    assert_problem_body(body, status, code)

    header_correlation_id =
      conn
      |> Plug.Conn.get_resp_header("x-correlation-id")
      |> List.first()

    assert header_correlation_id == body["correlation_id"]

    body
  end

  defp assert_problem_body(body, status, code) do
    assert body["code"] == to_string(code)
    assert body["status"] == status
    assert is_binary(body["correlation_id"])
    body
  end
end
