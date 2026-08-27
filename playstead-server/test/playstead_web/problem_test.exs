defmodule PlaysteadWeb.ProblemTest do
  use PlaysteadWeb.ApiCase, async: true

  test "a deliberately-raising /api/v1 route returns problem+json with status 500", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/debug/boom")

    assert_problem(conn, 500, :internal_error)
  end

  test "an unmatched /api/v1 path returns problem+json with code not_found", %{conn: conn} do
    conn = get(conn, "/api/v1/this-route-does-not-exist")

    assert_problem(conn, 404, :not_found)
  end

  test "two successive error responses carry different correlation_id values", %{conn: conn} do
    body1 = get(conn, ~p"/api/v1/debug/boom") |> assert_problem(500, :internal_error)
    body2 = get(conn, ~p"/api/v1/debug/boom") |> assert_problem(500, :internal_error)

    refute body1["correlation_id"] == body2["correlation_id"]
  end

  test "x-correlation-id header matches the body correlation_id for a forced /api error", %{
    conn: conn
  } do
    conn = get(conn, ~p"/api/v1/debug/boom")

    assert_problem(conn, 500, :internal_error)
  end

  test "PlaysteadWeb.Problem.send_problem/5 renders the full problem+json envelope" do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("accept", "application/json")
      |> PlaysteadWeb.Problem.send_problem(422, :capability_incompatible, "The client version is too old.")

    assert conn.status == 422

    content_type = conn |> Plug.Conn.get_resp_header("content-type") |> List.first()
    assert String.starts_with?(content_type, "application/problem+json")

    body = Jason.decode!(conn.resp_body)
    assert body["type"] == "about:blank"
    assert body["title"] == "Capability Incompatible"
    assert body["status"] == 422
    assert body["detail"] == "The client version is too old."
    assert body["code"] == "capability_incompatible"
    assert is_binary(body["correlation_id"])
  end
end
