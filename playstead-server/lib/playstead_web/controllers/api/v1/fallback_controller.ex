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
    PlaysteadWeb.Problem.send_problem(conn, 404, :not_found, "The requested resource was not found.")
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
end
