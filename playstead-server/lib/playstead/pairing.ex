defmodule Playstead.Pairing do
  @moduledoc """
  The pairing ceremony and device credential domain (D-07 through D-12).

  All pairing state lives in Postgres and every transition writes an
  append-only audit entry (`Playstead.AuditLog`). Nothing here ever
  accepts the display code as an authorization input — redemption is
  gated entirely on the separate, single-use `device_code` the client
  generated at request time (D-08).
  """

  import Ecto.Query, warn: false

  alias Playstead.Repo
  alias Playstead.AuditLog
  alias Playstead.Accounts.Scope
  alias Playstead.Pairing.{PairingRequest, DisplayCode}

  # D-12: 10-minute expiry, re-checked server-side on every read.
  @request_ttl_seconds 600
  # D-12: small fixed pending-queue cap; the oldest pending request is
  # evicted (and audited) rather than silently dropping the new one.
  @pending_queue_cap 20
  # D-07: the Mac polls every 5s; polling faster returns `slow_down`.
  @poll_interval_seconds 5

  @doc "The poll interval (seconds) advertised to clients at request creation."
  def poll_interval_seconds, do: @poll_interval_seconds

  ## Pairing requests

  @doc """
  Creates a pairing request from the client's self-reported claims plus
  its client-generated `device_code`. Only the SHA-256 hash of the
  device code is ever stored. Evicts the oldest pending request when the
  pending queue is at its fixed cap (D-12), and records a
  `pairing_requested` audit entry.

  `attrs` accepts string or atom keys: `device_code`, `device_name`,
  `platform`, `app_version`, `capabilities`, `requesting_ip`.
  """
  @spec create_request(map()) :: {:ok, PairingRequest.t()} | {:error, term()}
  def create_request(attrs) do
    case fetch(attrs, :device_code) do
      device_code when is_binary(device_code) and byte_size(device_code) > 0 ->
        do_create_request(attrs, device_code)

      _ ->
        {:error,
         %PairingRequest{}
         |> PairingRequest.create_changeset(%{})
         |> Ecto.Changeset.add_error(:device_code, "can't be blank")}
    end
  end

  defp do_create_request(attrs, device_code) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:eviction, fn repo, _changes -> maybe_evict_oldest_pending(repo) end)
    |> Ecto.Multi.insert(:request, fn _changes -> new_request_changeset(attrs, device_code) end)
    |> Ecto.Multi.run(:audit, fn _repo, %{request: request} ->
      AuditLog.record(nil, :pairing_requested, %{subject: request.id})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{request: request}} -> {:ok, request}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp new_request_changeset(attrs, device_code) do
    request_attrs = %{
      device_code_hash: hash_device_code(device_code),
      display_code: DisplayCode.generate(),
      claimed_device_name: fetch(attrs, :device_name),
      claimed_platform: fetch(attrs, :platform),
      claimed_app_version: fetch(attrs, :app_version),
      claimed_capabilities: fetch(attrs, :capabilities) || %{},
      requesting_ip: fetch(attrs, :requesting_ip),
      expires_at: expires_at_from_now()
    }

    %PairingRequest{}
    |> PairingRequest.create_changeset(request_attrs)
  end

  defp maybe_evict_oldest_pending(repo) do
    pending_count =
      PairingRequest
      |> where([r], r.status == "pending")
      |> repo.aggregate(:count)

    if pending_count >= @pending_queue_cap do
      PairingRequest
      |> where([r], r.status == "pending")
      |> order_by([r], asc: r.inserted_at)
      |> limit(1)
      |> repo.one()
      |> case do
        nil ->
          {:ok, :no_eviction}

        oldest ->
          {:ok, evicted} =
            oldest
            |> PairingRequest.status_changeset("expired")
            |> repo.update()

          {:ok, _} = AuditLog.record(nil, :pairing_request_evicted, %{subject: evicted.id})
          {:ok, evicted}
      end
    else
      {:ok, :no_eviction}
    end
  end

  @doc """
  The request's current status, re-derived from `expires_at` on every
  call — a request past its 10-minute window reports `expired` without
  depending on `expire_stale_requests/0` having run (D-12).
  """
  @spec get_request_status(binary()) :: {:ok, PairingRequest.t()} | {:error, :not_found}
  def get_request_status(id) do
    case Repo.get(PairingRequest, id) do
      nil -> {:error, :not_found}
      request -> {:ok, %{request | status: PairingRequest.effective_status(request)}}
    end
  end

  @doc """
  Rate-limits polling for a single request to no more than one call per
  `poll_interval_seconds`. Returns `{:error, :slow_down}` when the caller
  polled too fast; the caller is expected to have already fetched the
  status via `get_request_status/1` if desired.
  """
  @spec check_poll_rate(binary()) :: :ok | {:error, :slow_down}
  def check_poll_rate(id) do
    case Playstead.RateLimiter.hit(
           "pairing:poll:#{id}",
           :timer.seconds(@poll_interval_seconds),
           1
         ) do
      {:allow, _} -> :ok
      {:deny, _} -> {:error, :slow_down}
    end
  end

  @doc """
  Approves a pending, unexpired request. Requires a `%Scope{}` — there is
  no code path that transitions a request to `approved` without an
  explicit owner action (D-07 forbids auto-approval outright, including
  the "sole pending request" case).
  """
  @spec approve(Scope.t(), binary()) :: {:ok, PairingRequest.t()} | {:error, term()}
  def approve(%Scope{} = scope, id), do: transition(scope, id, "approved", :pairing_approved)

  @doc "Denies a pending, unexpired request."
  @spec deny(Scope.t(), binary()) :: {:ok, PairingRequest.t()} | {:error, term()}
  def deny(%Scope{} = scope, id), do: transition(scope, id, "denied", :pairing_denied)

  defp transition(%Scope{user: user}, id, new_status, audit_event) do
    Repo.transaction(fn ->
      case Repo.get(PairingRequest, id) do
        nil ->
          Repo.rollback(:not_found)

        request ->
          if PairingRequest.effective_status(request) == "pending" do
            {count, _} =
              from(r in PairingRequest, where: r.id == ^id and r.status == "pending")
              |> Repo.update_all(set: [status: new_status, approved_by_user_id: user.id])

            if count == 1 do
              updated = Repo.get!(PairingRequest, id)
              {:ok, _} = AuditLog.record(user.id, audit_event, %{subject: id})
              updated
            else
              Repo.rollback(:already_transitioned)
            end
          else
            Repo.rollback({:invalid_transition, PairingRequest.effective_status(request)})
          end
      end
    end)
  end

  @doc """
  Housekeeping sweep transitioning stale pending requests to `expired`.
  Correctness never depends on this having run — `get_request_status/1`
  and `approve/2` re-derive expiry themselves. Invoked by
  `Playstead.Pairing.ExpireStaleRequestsWorker` on a schedule.
  """
  @spec expire_stale_requests() :: {:ok, non_neg_integer()}
  def expire_stale_requests do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      from(r in PairingRequest, where: r.status == "pending" and r.expires_at < ^now)
      |> Repo.update_all(set: [status: "expired"])

    {:ok, count}
  end

  ## Helpers

  defp fetch(attrs, key) when is_map(attrs) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp expires_at_from_now do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.add(@request_ttl_seconds, :second)
  end

  defp hash_device_code(device_code) do
    :crypto.hash(:sha256, device_code) |> Base.encode16(case: :lower)
  end
end
