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
  alias Playstead.Pairing.{PairingRequest, DisplayCode, Device, DeviceCredential}
  alias Playstead.Sync.ChangeJournal

  # D-12: 10-minute expiry, re-checked server-side on every read.
  @request_ttl_seconds 600
  # D-12: small fixed pending-queue cap; the oldest pending request is
  # evicted (and audited) rather than silently dropping the new one.
  @pending_queue_cap 20
  # D-07: the Mac polls every 5s; polling faster returns `slow_down`.
  @poll_interval_seconds 5
  # D-10: 256-bit opaque device credential.
  @credential_bytes 32

  @doc "The poll interval (seconds) advertised to clients at request creation."
  def poll_interval_seconds, do: @poll_interval_seconds

  @doc "The fixed pending-queue cap (D-12) — exposed for the console's queue-full notice."
  def pending_queue_cap, do: @pending_queue_cap

  ## Pairing requests

  @doc """
  Pending pairing requests for the owner's approval queue (D-07), oldest
  first (the same order eviction uses). Filters only on the persisted
  `status` column, not on `expires_at` — a request that has timed out but
  hasn't been swept by `expire_stale_requests/0` yet still belongs in the
  queue so the console can render it inert with "Expired" (D-12), rather
  than having it silently vanish. Each returned request's `status` is
  eagerly re-derived via `PairingRequest.effective_status/1`, exactly as
  `get_request_status/1` does, so callers never see a stale "pending".
  """
  @spec list_pending_requests(Scope.t()) :: [PairingRequest.t()]
  def list_pending_requests(%Scope{}) do
    PairingRequest
    |> where([r], r.status == "pending")
    |> order_by([r], asc: r.inserted_at)
    |> Repo.all()
    |> Enum.map(&%{&1 | status: PairingRequest.effective_status(&1)})
  end

  @doc """
  Count of requests still in the persisted `pending` status — the same
  count `create_request/1`'s eviction check uses, so the console's
  queue-full notice always agrees with the actual enforcement point.
  """
  @spec pending_request_count() :: non_neg_integer()
  def pending_request_count do
    PairingRequest
    |> where([r], r.status == "pending")
    |> Repo.aggregate(:count)
  end

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

  # A pairing request has no owner until `approve/2`/`deny/2` assigns
  # one (`transition/4` below) — the change journal is per-owner
  # partitioned (T-01-45), so there is no correct owner to journal
  # against before that point. The pairing entity kind's first journal
  # entry is therefore always its approved-or-denied transition, not
  # its creation.

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
              {:ok, _} = ChangeJournal.append(user.id, :pairing, id, %{status: new_status})
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

  ## Redemption and credentials (D-08, D-10)

  @doc """
  Redeems an approved request with the client-generated `device_code`,
  issuing the device and its first credential exactly once. Runs in a
  single `Ecto.Multi`-equivalent transaction with a guarded update
  (`WHERE status = 'approved'`) so two concurrent redemptions of the
  same request can never both succeed — the loser gets
  `:pairing_request_already_redeemed`.

  A wrong `device_code` on an approved request returns the same error
  shape (`:pairing_request_not_approved`) as a request that genuinely
  isn't approved yet, so the response gives no oracle for guessing.
  """
  @spec redeem(binary(), String.t() | nil) ::
          {:ok,
           %{
             device: Device.t(),
             credential: DeviceCredential.t(),
             credential_plaintext: String.t()
           }}
          | {:error, term()}
  def redeem(id, device_code) do
    Repo.transaction(fn ->
      case Repo.get(PairingRequest, id) do
        nil -> Repo.rollback(:not_found)
        request -> do_redeem(request, device_code)
      end
    end)
  end

  defp do_redeem(request, device_code) do
    case PairingRequest.effective_status(request) do
      "expired" ->
        Repo.rollback(:pairing_request_expired)

      "redeemed" ->
        Repo.rollback(:pairing_request_already_redeemed)

      "approved" ->
        if valid_device_code?(request, device_code) do
          finalize_redemption(request)
        else
          Repo.rollback(:pairing_request_not_approved)
        end

      _pending_or_denied ->
        Repo.rollback(:pairing_request_not_approved)
    end
  end

  defp valid_device_code?(_request, device_code) when not is_binary(device_code), do: false

  defp valid_device_code?(request, device_code) do
    Plug.Crypto.secure_compare(hash_device_code(device_code), request.device_code_hash)
  end

  defp finalize_redemption(request) do
    {count, _} =
      from(r in PairingRequest, where: r.id == ^request.id and r.status == "approved")
      |> Repo.update_all(set: [status: "redeemed", redeemed_at: now_seconds()])

    if count == 1 do
      {:ok, device} = insert_device(request)
      {:ok, credential, plaintext} = insert_credential(device.id)

      {:ok, _} =
        AuditLog.record(request.approved_by_user_id, :pairing_redeemed, %{subject: request.id})

      {:ok, _} = ChangeJournal.append(device.user_id, :device, device.id, device_payload(device))

      {:ok, _} =
        ChangeJournal.append(device.user_id, :pairing, request.id, %{status: "redeemed"})

      %{device: device, credential: credential, credential_plaintext: plaintext}
    else
      Repo.rollback(:pairing_request_already_redeemed)
    end
  end

  defp insert_device(request) do
    %Device{}
    |> Device.create_changeset(%{
      user_id: request.approved_by_user_id,
      claimed_name: request.claimed_device_name,
      platform: request.claimed_platform,
      app_version: request.claimed_app_version,
      paired_at: now_seconds()
    })
    |> Repo.insert()
  end

  defp insert_credential(device_id, superseded_by \\ nil, command_id \\ nil) do
    plaintext = generate_credential_plaintext()
    hash = hash_credential(plaintext)

    changeset =
      %DeviceCredential{}
      |> DeviceCredential.create_changeset(%{
        device_id: device_id,
        token_hash: hash,
        fingerprint_prefix: fingerprint_prefix(hash),
        superseded_by_id: superseded_by,
        command_id: command_id
      })

    if command_id do
      # D-20b: on_conflict upsert keyed on the client-generated natural
      # key. A replay of the same command_id converges to the existing
      # row instead of minting a second credential — even after the
      # idempotency receipt (task 2) that would otherwise replay the
      # original plaintext has expired. When convergence happens, the
      # plaintext genuinely cannot be recovered (only its hash is ever
      # stored), so the caller only gets a plaintext back on the row's
      # actual first insertion.
      # `on_conflict: :nothing` returns zero rows from Postgres on a
      # real conflict, so Ecto can't distinguish "inserted" from
      # "converged" by inspecting the returned struct (its
      # client-generated binary_id primary key is always populated
      # either way). `{:replace, [:updated_at]}` forces Postgres's
      # `RETURNING` to always hand back the row that now genuinely
      # exists — the pre-existing row on conflict, our own row on a
      # fresh insert — so `credential.token_hash == hash` reliably
      # tells us which one it is.
      {:ok, credential} =
        Repo.insert(changeset,
          on_conflict: {:replace, [:updated_at]},
          conflict_target: [:command_id],
          returning: true
        )

      if credential.token_hash == hash do
        {:ok, credential, plaintext}
      else
        {:ok, credential, nil}
      end
    else
      {:ok, credential} = Repo.insert(changeset)
      {:ok, credential, plaintext}
    end
  end

  @doc """
  Authenticates a bearer credential (accepted only from the Authorization
  header by `PlaysteadWeb.Plugs.DeviceAuth` — this function itself never
  looks anywhere else). Touches `last_used_at`/`last_seen_at`, and on the
  first successful use of a newly-rotated credential, activates it and
  deletes the credential it superseded (D-10's use-activated handoff).
  """
  @spec authenticate(String.t()) ::
          {:ok, Device.t()} | {:error, :unauthorized} | {:error, :device_revoked}
  def authenticate(token) when is_binary(token) and byte_size(token) > 0 do
    hash = hash_credential(token)

    case Repo.get_by(DeviceCredential, token_hash: hash) do
      nil ->
        {:error, :unauthorized}

      credential ->
        device = Repo.get!(Device, credential.device_id)

        if device.revoked_at do
          {:error, :device_revoked}
        else
          activate_and_touch(credential, device)
          {:ok, device}
        end
    end
  end

  def authenticate(_), do: {:error, :unauthorized}

  defp activate_and_touch(credential, device) do
    now = now_seconds()

    Repo.transaction(fn ->
      if is_nil(credential.activated_at) do
        from(c in DeviceCredential, where: c.superseded_by_id == ^credential.id)
        |> Repo.delete_all()

        {:ok, _} = credential |> DeviceCredential.activate_changeset(now) |> Repo.update()
      end

      {:ok, _} = credential |> DeviceCredential.touch_last_used_changeset(now) |> Repo.update()
      {:ok, _} = device |> Device.touch_last_seen_changeset(now) |> Repo.update()
    end)
  end

  @doc """
  Use-activated credential rotation (D-10): issues a new credential,
  marks the caller's currently-active credential as superseded by it,
  and returns the new plaintext exactly once. The old credential keeps
  authenticating until the new one is first used, at which point
  `authenticate/1` deletes it. Never forced, never scheduled.

  `command_id`, when given, must be a valid UUIDv7 string
  (`Playstead.CommandId.valid_v7?/1`) — an invalid one is rejected
  before any effect runs. It is the client-generated natural key
  (D-20b) that makes a post-receipt-expiry outbox replay converge to
  the same credential row instead of duplicating, and is threaded onto
  a uniquely-enqueued `Playstead.Pairing.RotationAuditWorker` job.
  """
  @spec rotate_credential(Device.t(), String.t() | nil) ::
          {:ok, %{credential_plaintext: String.t() | nil, fingerprint_prefix: String.t()}}
          | {:error, term()}
  def rotate_credential(device, command_id \\ nil)

  def rotate_credential(%Device{} = device, command_id) when is_binary(command_id) do
    case Playstead.CommandId.cast(command_id) do
      {:ok, valid_command_id} -> do_rotate_credential(device, valid_command_id)
      :error -> {:error, {:invalid_command_id, "must be a valid UUIDv7 string"}}
    end
  end

  def rotate_credential(%Device{} = device, nil), do: do_rotate_credential(device, nil)

  defp do_rotate_credential(%Device{} = device, command_id) do
    result =
      Repo.transaction(fn ->
        current =
          DeviceCredential
          |> where([c], c.device_id == ^device.id and is_nil(c.superseded_by_id))
          |> Repo.one()

        {:ok, new_credential, plaintext} = insert_credential(device.id, nil, command_id)

        if current && current.id != new_credential.id do
          {:ok, _} =
            current |> DeviceCredential.supersede_changeset(new_credential.id) |> Repo.update()
        end

        %{credential_plaintext: plaintext, fingerprint_prefix: new_credential.fingerprint_prefix}
      end)

    case result do
      {:ok, %{} = ok} ->
        maybe_enqueue_rotation_audit(device.id, command_id)
        {:ok, ok}

      error ->
        error
    end
  end

  defp maybe_enqueue_rotation_audit(_device_id, nil), do: :ok

  defp maybe_enqueue_rotation_audit(device_id, command_id) do
    %{device_id: device_id, command_id: command_id}
    |> Playstead.Pairing.RotationAuditWorker.new()
    |> Oban.insert()
  end

  ## Device lifecycle (D-10, D-11)

  @doc """
  Revokes a device: sets `revoked_at` on the device (a permanent
  tombstone, never deleted) and records a `device_revoked` audit entry,
  all in one transaction. Takes effect on the device's next request;
  there is no push and no attempt to reach a device that may be offline
  for weeks (D-10's honest semantic).

  Credential rows are intentionally left in place rather than deleted:
  they hold only an irreversible SHA-256 hash (no recoverable secret),
  and `authenticate/1` already refuses any credential belonging to a
  revoked device via `device.revoked_at` — this is what lets a revoked
  device's next request come back as the distinct `device_revoked` code
  (T-01, the load-bearing PROT-02 isolation proof) instead of a generic,
  indistinguishable `unauthorized`.
  """
  @spec revoke_device(Scope.t(), binary()) :: {:ok, Device.t()} | {:error, term()}
  def revoke_device(%Scope{user: user}, device_id) do
    Repo.transaction(fn ->
      case owned_device(user.id, device_id) do
        nil ->
          Repo.rollback(:not_found)

        device ->
          {:ok, revoked} =
            device
            |> Device.revoke_changeset(now_seconds())
            |> Repo.update()

          {:ok, _} = AuditLog.record(user.id, :device_revoked, %{subject: device.id})
          # PROT-05, D-21, T-01-47: a tombstone, not an upsert — a
          # resuming client must remove this device from local state
          # entirely, and the entry carries no content about it beyond
          # its identity.
          {:ok, _} = ChangeJournal.tombstone(user.id, :device, revoked.id)
          revoked
      end
    end)
  end

  @doc "Lists every device (active and revoked) belonging to `scope`, never another scope's."
  @spec list_devices(Scope.t()) :: [Device.t()]
  def list_devices(%Scope{user: user}) do
    Device
    |> where([d], d.user_id == ^user.id)
    |> order_by([d], desc: d.inserted_at)
    |> Repo.all()
  end

  @doc """
  Renames a device's owner-editable `name`. Never touches `claimed_name`
  — the client's self-report is preserved separately (D-11).
  """
  @spec rename_device(Scope.t(), binary(), String.t()) :: {:ok, Device.t()} | {:error, term()}
  def rename_device(%Scope{user: user}, device_id, name) do
    case owned_device(user.id, device_id) do
      nil ->
        {:error, :not_found}

      device ->
        Repo.transaction(fn ->
          case device |> Device.rename_changeset(name) |> Repo.update() do
            {:ok, updated} ->
              {:ok, _} =
                ChangeJournal.append(user.id, :device, updated.id, device_payload(updated))

              updated

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)
    end
  end

  @doc """
  Device self-report refresh (D-20a): the device updates its own
  claimed name/app version, mirroring the initial pairing-time
  declaration. This is the effect wrapped by `Playstead.Idempotency.execute/4`
  behind `PATCH /api/v1/devices/me`.
  """
  @spec update_self_report(Device.t(), map()) :: {:ok, Device.t()} | {:error, term()}
  def update_self_report(%Device{} = device, attrs) do
    Repo.transaction(fn ->
      case device |> Device.self_report_changeset(attrs) |> Repo.update() do
        {:ok, updated} ->
          {:ok, _} =
            ChangeJournal.append(updated.user_id, :device, updated.id, device_payload(updated))

          updated

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  # Privacy-safe device snapshot for journal payloads (T-01-47's
  # discipline extends here too): never the credential, its hash, or
  # its fingerprint — only the fields a client's device list actually
  # renders.
  defp device_payload(%Device{} = device) do
    %{
      name: device.name,
      claimed_name: device.claimed_name,
      platform: device.platform,
      app_version: device.app_version,
      revoked_at: device.revoked_at
    }
  end

  defp owned_device(user_id, device_id) do
    Device
    |> where([d], d.id == ^device_id and d.user_id == ^user_id)
    |> Repo.one()
  end

  @doc """
  The fingerprint prefix of a device's currently active credential (the
  row with no `superseded_by_id`), for the console's device list. Never
  returns the credential itself — only what `insert_credential/2` already
  computed and stored as `fingerprint_prefix` (D-10). Returns `nil` if the
  device somehow has no active credential row.
  """
  @spec active_credential_fingerprint(binary()) :: String.t() | nil
  def active_credential_fingerprint(device_id) do
    DeviceCredential
    |> where([c], c.device_id == ^device_id and is_nil(c.superseded_by_id))
    |> select([c], c.fingerprint_prefix)
    |> Repo.one()
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

  defp now_seconds do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end

  defp generate_credential_plaintext do
    :crypto.strong_rand_bytes(@credential_bytes) |> Base.url_encode64(padding: false)
  end

  defp hash_credential(plaintext) do
    :crypto.hash(:sha256, plaintext) |> Base.encode16(case: :lower)
  end

  defp fingerprint_prefix(hash), do: String.slice(hash, 0, 8)
end
