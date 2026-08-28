defmodule PlaysteadWeb.Api.V1.FallbackController do
  @moduledoc """
  Handles the expected application error tuples returned by `/api/v1`
  controller actions, delegating to `PlaysteadWeb.Problem.send_problem/5`
  so every expected error path also carries a stable code and a
  correlation ID (D-22). Set as `action_fallback` on `/api/v1`
  controllers that return `{:error, _}` tuples.
  """

  use PlaysteadWeb, :controller

  def call(conn, {:error, :not_found}) do
    PlaysteadWeb.Problem.send_problem(
      conn,
      404,
      :not_found,
      "The requested resource was not found."
    )
  end

  def call(conn, {:error, :unauthorized}) do
    PlaysteadWeb.Problem.send_problem(conn, 401, :unauthorized, "Authentication is required.")
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    detail =
      changeset
      |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
      |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)

    PlaysteadWeb.Problem.send_problem(conn, 422, :validation_failed, detail)
  end

  def call(conn, {:error, {code, detail}}) when is_atom(code) and is_binary(detail) do
    status = PlaysteadWeb.ErrorCodes.status_for(code)
    PlaysteadWeb.Problem.send_problem(conn, status, code, detail)
  end

  # WR-03 (01-REVIEW.md): `Idempotency.execute/4` passes through whatever
  # reason an effect function's `Repo.rollback/1` carries verbatim. Any
  # shape not matched by a clause above (e.g. a bare atom outside the
  # `{atom, binary}` convention) previously fell through with no matching
  # clause, raising a FunctionClauseError that `ApiProblemHandler` caught
  # and turned into a generic 500 — losing the specific error code/status
  # the caller intended. This renders a generic :internal_error 500
  # directly instead of relying on that exception path.
  def call(conn, {:error, _reason}) do
    PlaysteadWeb.Problem.send_problem(
      conn,
      500,
      :internal_error,
      "An unexpected error occurred."
    )
  end
end
