defmodule PlaysteadWeb.Api.V1.ImportsController do
  @moduledoc """
  `PUT /api/v1/imports/uploads/:command_id` and
  `POST /api/v1/imports/precheck` (D-01c, D-02, D-10). The upload action
  reads the request body as a stream and feeds it directly through
  `Playstead.Blobs.put_stream/3` — never accumulating the whole body in
  memory and never buffering it to a second temporary location before
  the store's own temporary file.
  """

  use PlaysteadWeb, :controller

  alias Playstead.{CommandId, Idempotency, Import}

  action_fallback PlaysteadWeb.Api.V1.FallbackController

  @chunk_size 1_048_576

  @doc """
  Streams the request body through the store, verifies the declared
  digest, and writes the source file/asset set/receipt in one
  transaction (`Playstead.Import.import_single/3`).
  """
  def create(conn, %{"command_id" => command_id} = params) do
    device = conn.assigns.current_device

    with {:ok, _command_id} <- CommandId.cast(command_id) do
      run_upload(conn, device, params)
    else
      :error ->
        {:error, {:invalid_command_id, "The command_id must be a valid UUIDv7."}}
    end
  end

  defp run_upload(conn, device, params) do
    key = conn.assigns.idempotency_key
    fingerprint = conn.assigns.idempotency_fingerprint
    expected_sha256 = conn.assigns.expected_sha256
    declared_length = conn.assigns.declared_length
    original_name = Map.get(params, "filename", "upload")

    effect_fun = fn ->
      conn
      |> body_stream()
      |> Playstead.Blobs.put_stream(declared_length, expected_sha256: expected_sha256)
      |> handle_store_result(device, original_name)
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

  defp handle_store_result({:error, :digest_mismatch}, _device, _original_name) do
    {:error,
     {:import_digest_mismatch, "The uploaded bytes did not match the declared Repr-Digest."}}
  end

  defp handle_store_result({:error, reason}, _device, _original_name), do: {:error, reason}

  defp handle_store_result({:ok, status, meta}, device, original_name) do
    attrs = %{original_name: original_name, origin: "api_upload", size_bytes: meta.size_bytes}

    case Import.import_single(device.user_id, attrs, {status, meta}) do
      {:ok, receipt} -> {:ok, 201, receipt_json(receipt, meta)}
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

  defp receipt_json(receipt, meta) do
    %{
      receipt_id: receipt.id,
      outcome: receipt.outcome,
      sha256: meta.sha256,
      size_bytes: meta.size_bytes
    }
  end

  @doc """
  `POST /api/v1/imports/precheck` — whether the calling user already
  holds each supplied hash/size pair. Scoped strictly to the calling
  user (D-13).
  """
  def precheck(conn, %{"items" => items}) when is_list(items) do
    device = conn.assigns.current_device

    results =
      Enum.map(items, fn %{"sha256" => sha256, "size" => size} ->
        %{
          sha256: sha256,
          size: size,
          present: Import.present_for_user?(device.user_id, sha256, size)
        }
      end)

    json(conn, %{results: results})
  end

  def precheck(_conn, _params) do
    {:error, {:validation_failed, "The request body must include an \"items\" list."}}
  end
end
