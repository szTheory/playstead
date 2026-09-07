defmodule PlaysteadWeb.Api.V1.SavesController do
  @moduledoc """
  `PUT /api/v1/saves/uploads/:command_id` and
  `POST /api/v1/saves/revisions` (D-16). The split is forced, not
  stylistic: `Playstead.Idempotency.fingerprint/1` canonicalizes a
  parsed body and cannot fingerprint a stream. The upload action
  copies `ImportsController.create/2`'s streamed-body shape verbatim
  (`body_stream/1`, `@chunk_size`) and commits directly into the CAS
  with `reserve: :critical`, producing a TTL'd pending-upload pointer
  keyed by `command_id`. The revision action copies
  `CurationController`'s idempotent-commit shape (`run_idempotent/5`)
  verbatim and calls `Playstead.Saves.commit_revision/3`.
  """

  use PlaysteadWeb, :controller

  alias Playstead.{Blobs, CommandId, Idempotency, RateLimiter, Saves}

  action_fallback PlaysteadWeb.Api.V1.FallbackController

  @chunk_size 1_048_576

  @doc """
  Streams the request body directly into the CAS (`reserve: :critical`,
  D-64), verifies the declared `Repr-Digest`, enforces the 8 MiB
  save-revision cap, and records the resulting digest under
  `command_id` for the metadata commit to consume.
  """
  def create_upload(conn, %{"command_id" => command_id}) do
    device = conn.assigns.current_device

    with {:ok, _command_id} <- CommandId.cast(command_id),
         {:ok, body} <- run_upload(conn, device, command_id) do
      conn |> put_status(200) |> json(body)
    else
      :error ->
        {:error, {:invalid_command_id, "The command_id must be a valid UUIDv7."}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_upload(conn, device, command_id) do
    expected_sha256 = conn.assigns.expected_sha256
    declared_length = conn.assigns.declared_length

    if declared_length > Blobs.max_save_revision_bytes() do
      {:error, {:save_revision_too_large, "The save revision exceeds the maximum accepted size."}}
    else
      conn
      |> body_stream()
      |> Blobs.put_stream(declared_length, expected_sha256: expected_sha256, reserve: :critical)
      |> handle_upload_result(device, command_id)
    end
  end

  defp handle_upload_result({:error, :digest_mismatch}, _device, _command_id) do
    {:error,
     {:save_revision_digest_mismatch,
      "The uploaded bytes did not match the declared Repr-Digest."}}
  end

  defp handle_upload_result({:error, reason}, _device, _command_id), do: {:error, reason}

  defp handle_upload_result({:ok, _status, meta}, device, command_id) do
    case Saves.record_pending_upload(
           device.user_id,
           device.id,
           command_id,
           meta.sha256,
           meta.size_bytes
         ) do
      {:ok, _pending} -> {:ok, %{sha256: meta.sha256, size_bytes: meta.size_bytes}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp body_stream(conn) do
    Stream.resource(
      fn -> {conn, :more} end,
      fn
        {_conn, :done} ->
          {:halt, nil}

        {conn, :more} ->
          case Plug.Conn.read_body(conn, length: @chunk_size) do
            {:ok, chunk, conn} -> {[chunk], {conn, :done}}
            {:more, chunk, conn} -> {[chunk], {conn, :more}}
          end
      end,
      fn _ -> :ok end
    )
  end

  @doc """
  Commits the metadata half: resolves-or-creates the save line, links
  the pending blob named by `command_id`, inserts the revision, and
  appends the `save` journal entry, all inside `Saves.commit_revision/3`'s
  one `Ecto.Multi`.
  """
  def create_revision(conn, params) do
    device = conn.assigns.current_device
    key = conn.assigns.idempotency_key
    fingerprint = conn.assigns.idempotency_fingerprint
    id = params["id"] || Ecto.UUID.generate()

    with :ok <- check_revision_rate_limit(device) do
      effect_fun = fn ->
        case Saves.commit_revision(device.user_id, device, Map.put(params, "id", id)) do
          {:ok, revision} -> {:ok, 201, revision_json(revision)}
          {:error, reason} -> {:error, reason}
        end
      end

      run_idempotent(conn, device, key, fingerprint, effect_fun)
    end
  end

  # D-33/CR-02: 120 save-revision commits/hour/device (`blobs.ex`
  # defines the constants; this is the first production call site).
  # Checked before `Idempotency.execute/4` so a device already over
  # budget is refused without ever touching the idempotency-receipt
  # table -- a replay of an ALREADY-recorded request still short-
  # circuits inside `Idempotency` itself the next time it's tried,
  # since that path never re-runs `effect_fun`.
  defp check_revision_rate_limit(device) do
    case RateLimiter.hit(
           Blobs.save_revision_rate_limit_key(device.id),
           :timer.hours(1),
           Blobs.save_revision_rate_limit_per_hour()
         ) do
      {:allow, _count} ->
        :ok

      {:deny, _retry_after} ->
        {:error, {:rate_limited, "Too many save revisions committed this hour."}}
    end
  end

  @doc """
  `POST /api/v1/saves/lines/:id/resolve` (D-48). Idempotent, following
  `create_revision/2`'s shape: chooses `chosen_head_id` among the
  line's current heads and appends one resolution revision.
  """
  def resolve_divergence(conn, %{"id" => save_line_id, "chosen_head_id" => chosen_head_id}) do
    device = conn.assigns.current_device
    key = conn.assigns.idempotency_key
    fingerprint = conn.assigns.idempotency_fingerprint

    effect_fun = fn ->
      case Saves.resolve_divergence(device.user_id, device, save_line_id, chosen_head_id) do
        {:ok, revision} -> {:ok, 201, revision_json(revision)}
        {:error, reason} -> {:error, reason}
      end
    end

    run_idempotent(conn, device, key, fingerprint, effect_fun)
  end

  def resolve_divergence(_conn, %{"id" => _save_line_id}) do
    {:error, {:validation_failed, "chosen_head_id is required."}}
  end

  @doc """
  `POST /api/v1/saves/lines/:id/acknowledge` (D-52) -- "Keep both".
  Idempotent, never mutates a head or deletes anything.
  """
  def acknowledge_divergence(conn, %{"id" => save_line_id}) do
    device = conn.assigns.current_device
    key = conn.assigns.idempotency_key
    fingerprint = conn.assigns.idempotency_fingerprint

    effect_fun = fn ->
      case Saves.acknowledge_divergence(device.user_id, device, save_line_id) do
        {:ok, ack} -> {:ok, 200, ack}
        {:error, reason} -> {:error, reason}
      end
    end

    run_idempotent(conn, device, key, fingerprint, effect_fun)
  end

  defp run_idempotent(conn, device, key, fingerprint, effect_fun) do
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

  defp revision_json(revision) do
    %{
      id: revision.id,
      save_line_id: revision.save_line_id,
      parent_revision_id: revision.parent_revision_id,
      blob_sha256: revision.blob_sha256,
      size_bytes: revision.size_bytes,
      recorded_at: revision.recorded_at
    }
  end
end
