defmodule PlaysteadWeb.Api.V1.ExportsController do
  @moduledoc """
  `POST /api/v1/exports`, `GET /api/v1/exports/:id`, and
  `GET /api/v1/exports/:id/manifest` (D-33). The manifest endpoint
  plus `GET /api/v1/blobs/:sha256` make the API a complete alternative
  writer: a client can reconstruct a byte-identical tree using only
  these two endpoints.
  """

  use PlaysteadWeb, :controller

  alias Playstead.{Export, Idempotency}

  action_fallback PlaysteadWeb.Api.V1.FallbackController

  @doc """
  POST /api/v1/exports — creates a durable export record and enqueues
  the write-then-verify worker. Idempotency-Key gated, so a retried
  create request never starts a second export.
  """
  def create(conn, params) do
    device = conn.assigns.current_device
    key = conn.assigns.idempotency_key
    fingerprint = conn.assigns.idempotency_fingerprint

    scope = if params["asset_set_id"], do: :set, else: :library
    target_name = params["target_name"] || Ecto.UUID.generate()

    effect_fun = fn ->
      opts = [target_name: target_name, asset_set_id: params["asset_set_id"]]

      case Export.create_export(device.user_id, scope, opts) do
        {:ok, export} -> {:ok, 201, export_json(export)}
        {:error, :invalid_target} -> {:error, {:invalid_target, "The target name is not safe."}}
        {:error, changeset} -> {:error, changeset}
      end
    end

    case Idempotency.execute(device.id, key, fingerprint, effect_fun) do
      {:ok, status, body} ->
        conn |> put_status(status) |> json(body)

      {:error, :conflict} ->
        conn
        |> put_resp_header("retry-after", "1")
        |> PlaysteadWeb.Problem.send_problem(
          409,
          :idempotency_key_conflict,
          "A request with this Idempotency-Key is already being processed."
        )

      {:error, reason} ->
        PlaysteadWeb.Api.V1.FallbackController.call(conn, {:error, reason})
    end
  end

  @doc "GET /api/v1/exports/:id"
  def show(conn, %{"id" => id}) do
    device = conn.assigns.current_device

    case Export.get_export(device.user_id, id) do
      nil -> {:error, :not_found}
      export -> json(conn, export_json(export))
    end
  end

  @doc """
  GET /api/v1/exports/:id/manifest — the manifest resource, returned
  byte-identical to the file written on disk.
  """
  def manifest(conn, %{"id" => id}) do
    device = conn.assigns.current_device

    with export when not is_nil(export) <- Export.get_export(device.user_id, id),
         {:ok, content} <- Export.manifest_content(export) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, content)
    else
      nil -> {:error, :not_found}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp export_json(export) do
    %{
      id: export.id,
      scope: export.scope,
      target_name: export.target_name,
      status: export.status,
      set_count: export.set_count,
      file_count: export.file_count,
      total_bytes: export.total_bytes,
      sidecar_schema_id: export.sidecar_schema_id,
      generator_version: export.generator_version,
      mismatched_files: export.mismatched_files,
      started_at: export.started_at,
      finished_at: export.finished_at,
      last_verified_at: export.last_verified_at
    }
  end
end
