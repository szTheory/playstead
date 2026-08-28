# Phase 2: Explainable Import and Exact Export - Pattern Map

**Mapped:** 2026-08-28
**Files analyzed:** 32 (new files/directories implied by CONTEXT.md D-01–D-40 and RESEARCH.md's Recommended Project Structure)
**Analogs found:** 27 / 32 (5 have no direct Phase 1 analog — new domain: binary format sniffing, BagIt writer)

This phase is greenfield for its own tables/contexts (no `blobs`/`source_file`/`import_sessions` exist yet — confirmed via `find test/playstead -maxdepth 2 -type d`, only `pairing/`, `protocol/`, `sync/` exist). Every analog below is a **Phase 1** module of the same role/data-flow shape, read directly this session (not paraphrased).

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `lib/playstead/blobs/store.ex` | service (behaviour) | file-I/O | `lib/playstead/rate_limiter.ex` (thin `use`-based seam) + D-12's own spec | partial (novel: behaviour+adapter pair; no Phase 1 storage-adapter analog exists) |
| `lib/playstead/blobs/store/local_disk.ex` | service (adapter) | file-I/O | none in Phase 1 | no analog — see "No Analog Found" |
| `lib/playstead/blobs.ex` | service (context) | CRUD + file-I/O | `lib/playstead/pairing.ex` (context wrapping a state-machine schema) | role-match |
| `lib/playstead/blobs/multi_hash.ex` | utility | transform (streaming) | none — pure `:crypto` stdlib usage, RESEARCH.md Pattern 1 is normative | no analog |
| `lib/playstead/import/session.ex` | model (schema, state machine) | CRUD | `lib/playstead/pairing/pairing_request.ex` | exact — same shape: `binary_id` PK, `@statuses` list, `create_changeset/2`, `status_changeset/2`, an `effective_status/1`-style re-derivation function |
| `lib/playstead/import/receipt.ex` | model (schema, immutable) | CRUD | `lib/playstead/idempotency/receipt.ex` | role-match — immutable, insert-then-complete lifecycle, `create_changeset`/`complete_changeset` split |
| `lib/playstead/import/session_worker.ex` | service (Oban worker, durable cursor) | batch + event-driven | `lib/playstead/sync/compaction_worker.ex` (queue/max_attempts) + `lib/playstead/pairing/expire_stale_requests_worker.ex` (idiom); no Phase 1 worker has a per-row cursor + cooperative pause | role-match, extend idiom per RESEARCH.md Pattern 3 |
| `lib/playstead/import/writer.ex` (`Phoenix.LiveView.UploadWriter` impl) | service | streaming | none in Phase 1 (no upload path exists yet) — RESEARCH.md Pattern 2 is normative | no analog |
| `lib/playstead/import/outcome.ex` | utility (frozen enum) | transform | `lib/playstead/sync/entity_kind.ex` | exact — identical shape: `@kinds`/`@statuses` module attribute list, `all/0`, `valid?/1` guard clauses accepting atom or string |
| `lib/playstead/recognition/provider.ex` | service (behaviour) | transform | `lib/playstead/rate_limiter.ex` (`use Hammer, backend: :ets` — thin behaviour delegation) | partial — no full behaviour+impl pair exists in Phase 1; treat as novel |
| `lib/playstead/recognition/header_evidence.ex` | service | transform | none — pure binary pattern match, no Phase 1 analog | no analog |
| `lib/playstead/recognition/dat_pack_importer.ex` (saxy) | service | file-I/O + transform | none — first XML-parsing code in the app | no analog |
| `lib/playstead/formats/validators/*.ex` (gba/gb/nes/snes/md/psx_cue) | utility (pure functions) | transform | none — closest idiom is `lib/playstead/command_id.ex`'s regex-based `valid?/1` + `cast/1` pair (pure validation, never raises) | role-match on validation idiom only |
| `lib/playstead/attention/item.ex` | model (schema) | CRUD | `lib/playstead/pairing/pairing_request.ex` | role-match — status-bearing schema needing a resolution state machine |
| `lib/playstead/attention/resolutions.ex` | service (5 audited commands) | event-driven | `lib/playstead/audit_log.ex` (`record/3` as the every-mutation-writes-an-entry pattern) + `lib/playstead_web/live/devices_live.ex`'s `handle_transition/3` (command dispatch + audit + reload) | exact for the audit-wrapping pattern |
| `lib/playstead/export/export.ex` | model (schema) | CRUD | `lib/playstead/pairing/pairing_request.ex` | role-match — durable row with `state`/status progression |
| `lib/playstead/export/worker.ex` | service (Oban worker) | batch + event-driven | same as `session_worker.ex` above | role-match, shares job/progress/control model per D-38 |
| `lib/playstead/export/bagit_writer.ex` | service | file-I/O | none — RESEARCH.md Pattern 4 (write-then-verify) is normative; closest idiom for "fsync then rename" is D-11's own spec, not existing code | no analog |
| `lib/playstead/export/sanitize.ex` | utility | transform | none — pure string function; closest idiom is `command_id.ex`'s regex-validate pattern | role-match on validation idiom only |
| `lib/playstead_web/plugs/upload_precheck.ex` or controller equivalent | controller/plug | request-response | `lib/playstead_web/plugs/idempotency.ex` | exact — pre-flight classify-then-halt-or-assign shape |
| `lib/playstead_web/controllers/api/v1/imports_controller.ex` | controller | request-response (streaming write) | `lib/playstead_web/controllers/api/v1/hello_controller.ex` | role-match — device-authenticated, domain-computed verdict rendered directly, `action_fallback` |
| `lib/playstead_web/controllers/api/v1/import_sessions_controller.ex` | controller | request-response (cursor-paginated) | `lib/playstead_web/controllers/api/v1/changes_controller.ex` (read this session's summary; cursor-paginated read pattern) + `snapshot_controller.ex` | role-match |
| `lib/playstead_web/controllers/api/v1/attention_controller.ex` | controller | request-response (CRUD + resolve) | `lib/playstead_web/controllers/api/v1/devices_controller.ex` (`update`/`rotate` mutating pattern under `:idempotency`) | exact |
| `lib/playstead_web/controllers/api/v1/exports_controller.ex` | controller | request-response | `lib/playstead_web/controllers/api/v1/devices_controller.ex` | role-match |
| `lib/playstead_web/controllers/api/v1/blobs_controller.ex` | controller | file-I/O (streaming GET, Range) | none in Phase 1 (no byte-serving endpoint exists yet) | no analog |
| `lib/playstead_web/live/import_live.ex` | LiveView | request-response + event-driven (PubSub) | `lib/playstead_web/live/devices_live.ex` | exact — mount reloads from context (never trusts assigns as source of truth), `handle_event` dispatches to context, generic error flash via `Problem.generate_correlation_id/0` |
| `lib/playstead_web/live/attention_live.ex` | LiveView | request-response + event-driven | `lib/playstead_web/live/devices_live.ex` | exact — same bulk-action/sudo-gate shape as revoke |
| `lib/playstead_web/live/import_sessions_live.ex` (jobs console) | LiveView | event-driven (PubSub ticks) | `lib/playstead_web/live/devices_live.ex` (`:timer.send_interval` + `handle_info(:tick, ...)` pattern) | role-match |
| `lib/playstead_web/live/exports_live.ex` | LiveView | request-response + event-driven | `lib/playstead_web/live/devices_live.ex` | exact |
| `lib/playstead/sync/change_journal.ex` (modified: producers for `catalogue`/`job`) | service (extend) | event-driven | itself — `lib/playstead/sync/change_journal.ex` `append/4`/`tombstone/3` | exact (reuse as-is per D-09/D-23) |
| `lib/playstead/readiness.ex` (modified: add inbox/export checks) | service (extend) | config/health | itself — `volumes_check/1` | exact (extend existing pattern) |
| `priv/repo/migrations/*_create_blobs.exs` etc. | migration | CRUD (DDL) | `priv/repo/migrations/20260827180001_create_devices_and_credentials.exs` (not read this session; naming/ordering convention confirmed via `ls`) | role-match |
| `test/playstead/import/*_test.exs`, `test/playstead/export/*_test.exs` | test | — | `test/playstead/pairing_test.exs`, `test/playstead/idempotency_test.exs` | role-match |

## Pattern Assignments

### `lib/playstead/import/session.ex` (model, CRUD)

**Analog:** `lib/playstead/pairing/pairing_request.ex` (full file read, 84 lines)

**Schema + statuses pattern:**
```elixir
@statuses ~w(pending approved denied expired redeemed)

@primary_key {:id, :binary_id, autogenerate: true}
@foreign_key_type :binary_id
schema "pairing_requests" do
  field :status, :string, default: "pending"
  # ...
  timestamps(type: :utc_datetime_usec)
end

def statuses, do: @statuses
```
Apply this shape to `import_sessions`: `@statuses ~w(staging active paused completed cancelled)` (Claude's discretion per D-05/D-06/D-07), `binary_id` PK (matches `Playstead.CommandId` UUIDv7 client-supplied session ids per D-01c), `usec` timestamps if ordering matters for the throttled-checkpoint logic (D-09).

**Changeset split pattern:**
```elixir
def create_changeset(request, attrs) do
  request
  |> cast(attrs, [...])
  |> validate_required([...])
  |> put_change(:status, "pending")
  |> unique_constraint(:device_code_hash)
end

def status_changeset(request, status) when status in @statuses do
  change(request, status: status)
end
```
Apply directly: `create_changeset/2` for session creation, `status_changeset/2` for `state` transitions driven by `SessionWorker`/pause-resume-cancel.

**Re-derivation-never-cached pattern:**
```elixir
def expired?(%__MODULE__{expires_at: expires_at}) do
  DateTime.compare(DateTime.utc_now(), expires_at) == :gt
end

def effective_status(%__MODULE__{status: "pending"} = request) do
  if expired?(request), do: "expired", else: "pending"
end
```
This is the exact idiom for D-06's "truth lives in `import_sessions.state` + `requested_control`, checked between files" — never trust a LiveView assign or worker-local variable for control state; re-read from the row on every check, same as `PairingRequest.effective_status/1` is re-derived on every read rather than trusted from a background sweep.

---

### `lib/playstead/import/receipt.ex` (model, immutable, CRUD)

**Analog:** `lib/playstead/idempotency/receipt.ex` (not fully read this session, but its consumer `lib/playstead/idempotency.ex` was, and quotes the exact two-phase changeset pattern to copy):

```elixir
# From Playstead.Idempotency.execute/4 (lines 93-110)
Ecto.Multi.new()
|> Ecto.Multi.insert(:receipt, fn _changes ->
  Receipt.create_changeset(%Receipt{}, %{...})
end)
|> Ecto.Multi.run(:effect, fn _repo, _changes -> ... end)
|> Ecto.Multi.update(:receipt_complete, fn %{receipt: receipt, effect: {status, body}} ->
  Receipt.complete_changeset(receipt, status, Jason.encode!(body))
end)
|> Repo.transaction()
```
Apply this exact `Ecto.Multi` shape for `import_receipts`: insert an in-flight/pending receipt row in the same transaction as the blob commit (D-11's "one DB transaction"), never write the receipt after commit. D-24 requires `import_receipts` be "immutable, indefinite retention" — so unlike `idempotency_receipts` (90-day prune), do **not** copy `Playstead.Idempotency.prune_expired/0` for this table.

---

### `lib/playstead/import/outcome.ex` (utility, frozen enum)

**Analog:** `lib/playstead/sync/entity_kind.ex` (full file read, 28 lines)

```elixir
@kinds ~w(device pairing catalogue job transfer save)a

def all, do: @kinds

def valid?(kind) when kind in @kinds, do: true

def valid?(kind) when is_binary(kind) do
  kind in Enum.map(@kinds, &to_string/1)
end

def valid?(_kind), do: false
```
Copy verbatim for D-25's nine frozen outcome codes:
```elixir
@codes ~w(new_asset exact_duplicate alias variant incomplete_set unrecognized patched quarantined failed_safely)a
def all, do: @codes
def valid?(code) when code in @codes, do: true
def valid?(code) when is_binary(code), do: code in Enum.map(@codes, &to_string/1)
def valid?(_code), do: false
```
The reason-attribute sub-enums (`unrecognized{...}`, `quarantined{...}`, `failed_safely{...}`) should each get their own small module of the same shape — D-25 says "reason attributes refine, never add codes," mirroring how `EntityKind`'s moduledoc explains kinds are frozen so a later phase attaches producers without a protocol change.

---

### `lib/playstead/import/session_worker.ex` and `lib/playstead/export/worker.ex` (Oban workers, durable cursor)

**Analog:** `lib/playstead/sync/compaction_worker.ex` (full file, 19 lines) for the `use Oban.Worker` idiom, extended per RESEARCH.md Pattern 3 for the cursor/pause shape:

```elixir
# lib/playstead/sync/compaction_worker.ex — idiom baseline
use Oban.Worker, queue: :default, max_attempts: 3

@impl Oban.Worker
def perform(%Oban.Job{}) do
  {:ok, _count} = Compaction.run()
  :ok
end
```

D-05 requires `queue: :import`, `unique: [fields: [:args], keys: [:session_id]]`, concurrency 1 (configured at the queue level in `config/runtime.exs`, not in the worker macro). The per-file cooperative-pause loop has no Phase 1 analog; RESEARCH.md's own skeleton is normative:

```elixir
use Oban.Worker, queue: :import, unique: [fields: [:args], keys: [:session_id]]

@impl true
def perform(%Oban.Job{args: %{"session_id" => session_id}}) do
  session = Playstead.Import.get_session!(session_id)

  session
  |> Playstead.Import.pending_source_files()
  |> Enum.reduce_while(:ok, fn source_file, :ok ->
    case Playstead.Import.control(session_id) do
      :pause_requested -> {:halt, :paused}
      :cancel_requested -> {:halt, :cancelled}
      :run -> {:cont, hash_and_commit_one(source_file)}
    end
  end)
  |> finalize(session_id)
end
```
`Export.Worker` reuses this identical shape per D-38, substituting `pending_source_files/1` with a member-checkpoint iterator.

**Anti-pattern to flag in review:** `Oban.pause_queue/2` — global/runtime-only, must never be used for D-06's per-session pause (RESEARCH.md Anti-Patterns, explicit).

---

### `lib/playstead/attention/resolutions.ex` (5 audited commands)

**Analog:** `lib/playstead/audit_log.ex` `record/3` (full file, 72 lines) + `lib/playstead_web/live/devices_live.ex`'s `handle_transition/3` (lines 199-230) for the command-dispatch-and-audit wiring:

```elixir
# audit_log.ex — the write call every resolution must make
@spec record(integer() | nil, atom(), map()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
def record(user_id, event, metadata \\ %{}) when is_atom(event) and is_map(metadata) do
  {subject, metadata} = Map.pop(metadata, :subject)

  %Entry{}
  |> Entry.changeset(%{
    user_id: user_id,
    event: Atom.to_string(event),
    subject: subject,
    metadata: stringify_keys(metadata)
  })
  |> Repo.insert()
end
```

```elixir
# devices_live.ex handle_transition/3 — dispatch-then-audit-then-reload shape
defp handle_transition(socket, id, action) do
  scope = socket.assigns.current_scope
  socket = assign(socket, :acting, {id, action})

  result =
    case action do
      :approve -> Pairing.approve(scope, id)
      :deny -> Pairing.deny(scope, id)
    end

  case result do
    {:ok, _request} -> {:noreply, socket |> assign(:acting, nil) |> load_requests()}
    {:error, _other} -> {:noreply, socket |> assign(:acting, nil) |> load_requests() |> put_flash(:error, generic_error_flash())}
  end
end
```
Apply directly for D-27's five resolutions (`correct_system`, `attach_companion`, `retain_as_custom`, `exclude`, `retry`): each resolution function in `Playstead.Attention.Resolutions` should itself call `AuditLog.record/3` inside the same `Ecto.Multi`/transaction as its effect (following `Idempotency.execute/4`'s "never write after commit" discipline), and `AttentionLive`'s event handlers should copy `handle_transition/3`'s dispatch-then-reload-from-context shape verbatim — never keep resolution results only in LiveView assigns.

---

### `lib/playstead_web/plugs/upload_precheck.ex` (or a controller action) (plug/controller, request-response)

**Analog:** `lib/playstead_web/plugs/idempotency.ex` (full file, 88 lines) — pre-flight classify-then-halt-or-continue shape:

```elixir
@impl true
def call(conn, _opts) do
  case get_req_header(conn, "idempotency-key") do
    [key] when key != "" -> classify(conn, key)
    _ -> missing(conn)
  end
end

defp classify(conn, key) do
  device = conn.assigns.current_device
  fp = Idempotency.fingerprint(%{method: conn.method, path: conn.request_path, body: conn.params})

  case Idempotency.fetch(device.id, key, fp) do
    {:ok, :fresh} -> conn |> assign(:idempotency_key, key) |> assign(:idempotency_fingerprint, fp)
    {:ok, :replay, receipt} -> conn |> put_resp_content_type(...) |> send_resp(...) |> halt()
    {:error, :mismatch} -> conn |> Problem.send_problem(422, :idempotency_key_mismatch, "...") |> halt()
    {:error, :in_flight} -> conn |> put_resp_header("retry-after", "1") |> Problem.send_problem(409, :idempotency_key_conflict, "...") |> halt()
  end
end
```
D-02's upload flow is a direct structural match: `Repr-Digest` classify → `422 import_digest_mismatch` (nothing stored) mirrors `:mismatch` → `422`; missing `Content-Length` → `411 upload_length_required` mirrors `missing/1`'s `422 idempotency_key_missing`. Every new mutating `/api/v1` endpoint (uploads, resolve, export create) still goes through the **existing** `PlaysteadWeb.Plugs.Idempotency` unchanged per D-02's own text ("the API upload fingerprint rule is a specialisation, not a new mechanism") — do not fork this plug; add the digest check as an additional plug/step in the same pipeline.

---

### `lib/playstead_web/controllers/api/v1/imports_controller.ex`, `attention_controller.ex`, `exports_controller.ex` (controllers, request-response)

**Analog:** `lib/playstead_web/controllers/api/v1/hello_controller.ex` (full file, 46 lines):

```elixir
use PlaysteadWeb, :controller
alias Playstead.Protocol.{Capabilities, Negotiation}
action_fallback PlaysteadWeb.Api.V1.FallbackController

def create(conn, params) do
  device = conn.assigns.current_device
  # ...
  case Negotiation.verdict(...) do
    %{verdict: :compatible} -> json(conn, %{...})
    %{verdict: :incompatible, remedy: remedy} ->
      PlaysteadWeb.Problem.send_problem(conn, 422, :capability_incompatible, "...", %{remedy: remedy})
  end
end
```
Copy this exact shape: `conn.assigns.current_device` (set by `:device_auth`), `action_fallback PlaysteadWeb.Api.V1.FallbackController` for the error path, domain module (`Playstead.Import`, `Playstead.Attention`, `Playstead.Export`) computes the verdict/result, controller only renders it — never inlines outcome-classification logic in the controller (mirrors "the controller never inlines a compatibility decision of its own").

---

### `lib/playstead_web/live/import_live.ex`, `attention_live.ex`, `exports_live.ex`, `import_sessions_live.ex` (LiveViews)

**Analog:** `lib/playstead_web/live/devices_live.ex` (full file, 330 lines) — three reusable sub-patterns:

**1. Never trust assigns as source of truth (moduledoc + `load_requests/1`/`load_devices/1`):**
```elixir
defp load_requests(socket) do
  scope = socket.assigns.current_scope
  assign(socket, requests: Pairing.list_pending_requests(scope), pending_count: Pairing.pending_request_count(), pending_cap: Pairing.pending_queue_cap())
end
```
Every mutation handler ends by calling `load_*` again rather than hand-patching the assign — apply this for `ImportLive`/`AttentionLive` reloading from `Playstead.Import`/`Playstead.Attention` after every event.

**2. Sudo-gate a specific action, not the whole route:**
```elixir
def handle_event("revoke", %{"id" => id}, socket) do
  user = socket.assigns.current_scope.user
  if Accounts.sudo_mode?(user) do
    ...
  else
    {:noreply, redirect(socket, to: ~p"/sudo?return_to=%2Fdevices")}
  end
end
```
Not directly named by any D-xx for Phase 2's resolutions, but the same per-action (not per-route) gating idiom applies if any Needs Attention resolution is judged sensitive enough to require it — check with the planner; D-27 doesn't mandate sudo, only `AuditLog`.

**3. PubSub tick pattern for progress (D-09's ≤4 Hz throttled ticks):**
```elixir
@tick_interval_ms 1_000
if connected?(socket), do: :timer.send_interval(@tick_interval_ms, self(), :tick)

@impl true
def handle_info(:tick, socket) do
  {:noreply, assign(socket, :now, DateTime.utc_now())}
end
```
`ImportSessionsLive`/`ExportsLive` should subscribe to a `Phoenix.PubSub` topic (per-session, naming at Claude's discretion) in `mount/3` when `connected?/1`, and treat every inbound tick as a hint only — re-fetch authoritative progress counts from `Playstead.Import`/`Playstead.Export` context functions on each tick, never accumulate progress in `handle_info` state (same "presentation-only tick, truth is server-derived" comment pattern as `@tick_interval_ms`'s moduledoc note).

**4. Generic error flash with correlation id:**
```elixir
defp generic_error_flash do
  "Something went wrong on the server. Your data is safe — nothing was changed. " <>
    "Correlation ID: #{Problem.generate_correlation_id()}"
end
```
Copy verbatim for every LiveView this phase adds — this is the microcopy idiom D-32's "failed_safely" vocabulary ("Couldn't finish — nothing was changed") already echoes at the protocol layer; reuse the same sentence shape in the console.

---

### `lib/playstead/formats/validators/*.ex`, `lib/playstead/export/sanitize.ex` (pure validation utilities)

**Analog:** `lib/playstead/command_id.ex` (full file, 34 lines):

```elixir
@v7_regex ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

@spec valid_v7?(term()) :: boolean()
def valid_v7?(value) when is_binary(value), do: Regex.match?(@v7_regex, value)
def valid_v7?(_value), do: false

@spec cast(term()) :: {:ok, String.t()} | :error
def cast(value) when is_binary(value) do
  if valid_v7?(value), do: {:ok, String.downcase(value)}, else: :error
end
def cast(_value), do: :error
```
The `valid?/1`-never-raises + `cast/1`-returns-tagged-tuple idiom is exactly D-14's requirement ("never raise") for Tier A/B format validators and D-15's CUE parser hard caps. Each validator module (`gba.ex`, `gb.ex`, `nes.ex`, `snes.ex`, `md.ex`, `psx_cue.ex`) should expose a `recognize/1 :: binary() -> {:ok, evidence_map} | :no_match` pure function following this same "binary in, tagged tuple out, no exceptions" contract; `Export.Sanitize` should follow the same `cast/1`-style contract for filename sanitization (Pitfall 5).

---

### `lib/playstead/readiness.ex` (extend, not new)

**Analog:** itself — `volumes_check/1` (lines 80-142, already read):

```elixir
@blob_path_env "PLAYSTEAD_BLOB_PATH"
@default_blob_path "/app/blobs"

defp volumes_check(env) do
  path = env[@blob_path_env] || @default_blob_path
  case writable_check(path) do
    :ok -> case anonymous_volume?(path) do ... end
    {:warning, message} -> %{id: :volumes, state: :warning, message: message}
  end
end
```
Add `PLAYSTEAD_INBOX_PATH` (readable-only check — reuse `File.read`/`File.ls` instead of `writable_check/1`'s `File.write` probe, since the mount is `:ro` per D-01) and `PLAYSTEAD_EXPORT_PATH` (same `writable_check/1` as blobs) as two more rows in `summary/1`'s list, following the exact `%{id:, state:, message:}` row shape. Also extend with Pitfall 2's same-volume assertion for `tmp/` vs `objects/` using the existing `/proc/self/mountinfo` technique in `anonymous_volume?/1`.

---

### `lib/playstead/sync/change_journal.ex` (extend, not new)

**Analog:** itself — `append/4`/`tombstone/3` (lines 43-63, already read):

```elixir
@spec append(pos_integer(), atom() | String.t(), String.t() | binary(), map()) ::
        {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
def append(user_id, entity_kind, entity_id, payload \\ %{}) do
  write(user_id, entity_kind, entity_id, "upsert", payload)
end
```
Every asset-set write and every session/export state transition calls this **unchanged** function with `entity_kind: :catalogue` or `:job` (already registered in `EntityKind.@kinds`, confirmed no code change needed there) — inside the same transaction as the mutation, per the moduledoc's explicit warning: "An entry written after commit can be lost in the gap." This is the load-bearing rule for D-09's job-entry-on-state-transition-only requirement and D-23's per-asset catalogue entry inside the per-file transaction.

## Shared Patterns

### Idempotency-Key handling
**Source:** `lib/playstead_web/plugs/idempotency.ex` + `lib/playstead/idempotency.ex`
**Apply to:** `imports_controller.ex` (PUT upload), `attention_controller.ex` (`resolve`), `exports_controller.ex` (`create`) — every mutating endpoint D-30 lists.
```elixir
# plug pre-flight (unchanged, reused as-is)
case Idempotency.fetch(device.id, key, fp) do
  {:ok, :fresh} -> ...
  {:ok, :replay, receipt} -> ... halt with stored response
  {:error, :mismatch} -> 422 idempotency_key_mismatch
  {:error, :in_flight} -> 409 idempotency_key_conflict
end
```

### Problem+json error rendering
**Source:** `lib/playstead_web/problem.ex` + `lib/playstead_web/error_codes.ex`
**Apply to:** every new controller/plug error path in D-10's code table.
```elixir
PlaysteadWeb.Problem.send_problem(conn, 422, :import_digest_mismatch, "...", %{})
```
Register each D-10 code (`import_file_too_large`, `storage_insufficient`, `import_digest_mismatch`, `upload_length_required`, `import_empty_file`, `too_many_uploads`, `import_session_too_large`) as a new entry in `PlaysteadWeb.ErrorCodes.@registry`, following the existing `{status, "Title Case"}` tuple shape — do not build a second registry.

### Audit logging on every resolution/mutation
**Source:** `lib/playstead/audit_log.ex`
**Apply to:** every Needs Attention resolution (D-27), DAT-pack import (D-18), export creation (D-38).
```elixir
AuditLog.record(user_id, :attention_item_excluded, %{subject: item_id, reason: "..."})
```

### Rate limiting
**Source:** `lib/playstead/rate_limiter.ex` (`use Hammer, backend: :ets`) via `lib/playstead_web/plugs/throttle.ex` (not read this session, but named as `RateLimiter`'s sole caller in its moduledoc)
**Apply to:** D-10's per-device upload concurrency (≤2) and per-IP staging-action limits — add new `action:` atoms to the existing `Throttle` plug's dispatch, do not build a second limiter.

### Context-owns-transaction, LiveView-and-API-share-context
**Source:** established pattern named in `02-CONTEXT.md <code_context>` and demonstrated by `Playstead.Pairing` being called identically from `devices_live.ex` and (implicitly) any future API controller.
**Apply to:** `Playstead.Import`, `Playstead.Attention`, `Playstead.Export`, `Playstead.Blobs`, `Playstead.Recognition` — each is the single seam its LiveView and its API controllers both call; no protocol logic in LiveView, no LiveView-only code path for a mutation an API client also needs.

## No Analog Found

Files with no close match in the codebase (planner should use RESEARCH.md's Code Examples / Architecture Patterns sections instead):

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `lib/playstead/blobs/store/local_disk.ex` | service (adapter) | file-I/O | First storage-adapter/behaviour pair in the app; RESEARCH.md's D-12 spec and Pattern 1 (`MultiHash`) are the normative reference, not existing code |
| `lib/playstead/import/writer.ex` (`UploadWriter`) | service | streaming | First LiveView upload path in the app; RESEARCH.md Pattern 2 (full code skeleton, hexdocs-sourced) is normative |
| `lib/playstead/recognition/header_evidence.ex`, `formats/validators/*.ex` | utility/service | transform | First binary-format-sniffing code in the app; only the *validation-contract idiom* (`command_id.ex`'s never-raise `valid?`/`cast`) transfers, not the parsing logic itself |
| `lib/playstead/recognition/dat_pack_importer.ex` | service | file-I/O + transform | First XML parsing in the app (`saxy`); no existing SAX/DOM parsing code anywhere in `lib/` |
| `lib/playstead/export/bagit_writer.ex` | service | file-I/O | First filesystem-tree-writing/export code in the app; RESEARCH.md Pattern 4 (write-then-verify) plus D-34/D-36's own text are the normative reference |
| `lib/playstead_web/controllers/api/v1/blobs_controller.ex` | controller | file-I/O (streaming GET, Range) | First byte-serving/Range-request endpoint in the app; no analog controller streams a file body today |

## Metadata

**Analog search scope:** `lib/playstead/`, `lib/playstead_web/`, `test/playstead/`, `test/playstead_web/` (full listing enumerated via `find`); `priv/repo/migrations/` (listed, not opened — naming/ordering convention only, per P1 D-17 forward-only rule already documented in CONTEXT.md)
**Files scanned:** 13 Phase 1 source files opened and read in full this session (`idempotency.ex`, `readiness.ex`, `sync/change_journal.ex`, `sync/entity_kind.ex`, `audit_log.ex`, `rate_limiter.ex`, `command_id.ex`, `pairing/expire_stale_requests_worker.ex`, `sync/compaction_worker.ex`, `plugs/idempotency.ex`, `error_codes.ex`, `problem.ex`, `live/devices_live.ex`, `router.ex`, `pairing/pairing_request.ex`, `controllers/api/v1/hello_controller.ex`) plus a full `lib/`/`test/` directory enumeration and line-count survey of all Phase 1 modules
**Pattern extraction date:** 2026-08-28
