# Phase 4: Persistent Save Continuity - Pattern Map

**Mapped:** 2026-09-03
**Files analyzed:** 27 (new/modified, both tiers)
**Analogs found:** 27 / 27 (all have at least a role-match; several are extensions of files that already exist and must be modified in place, not created)

This phase spans two runtimes (Elixir/Phoenix/Ecto server, Swift/macOS client) with zero new third-party dependencies (per RESEARCH.md). Nearly every "closest analog" below is an **in-repo seam to extend**, not a library to imitate — Phase 1/2/3 already built the CAS, idempotency, sync spine, export layout, readiness engine, and outbox this phase reuses. The planner should treat "extend this existing file" and "create this new file following that existing file's shape" as equally load-bearing entries in the table below.

## File Classification

### Server (Elixir/Phoenix/Ecto)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `playstead-server/lib/playstead/saves.ex` | service (bounded context) | CRUD + event-driven (journal) | `playstead-server/lib/playstead/curation.ex` | exact (context shape: `Ecto.Multi`, scope-first functions, journal entry inside the same transaction) |
| `playstead-server/lib/playstead/saves/save.ex` | model (Ecto schema, lineage root) | CRUD | `playstead-server/lib/playstead/curation/favorite.ex` (client-supplied UUIDv7 PK, user-scoped unique index) | role-match |
| `playstead-server/lib/playstead/saves/revision.ex` | model (Ecto schema, DAG node) | CRUD | `playstead-server/lib/playstead/curation/collection_member.ex` (FK to a parent-ish row + ordering field) plus `playstead-server/lib/playstead/curation/position.ex` (fractional/ordering discipline, for the branch-head derivation index) | role-match |
| `playstead-server/lib/playstead/saves/save_contract.ex` (if server-side contract validation needed) | model/validator | request-response | `playstead-server/lib/playstead/blobs/fingerprints.ex` (matches-a-declared-shape, catch-all `nil`) | role-match |
| `playstead-server/lib/playstead_web/controllers/api/v1/saves_controller.ex` | controller | streaming (upload) + request-response (commit) | **Two analogs, one per endpoint:** `imports_controller.ex` for `PUT /api/v1/saves/uploads/:command_id` (streamed body → `Blobs.put_stream`); `curation_controller.ex` for `POST /api/v1/saves/revisions` (parsed-body idempotent commit via `Idempotency.execute/4`) | exact (D-16 explicitly forces this exact two-endpoint split for the exact reason these two controllers already differ) |
| `playstead-server/lib/playstead_web/controllers/api/v1/save_history_controller.ex` (read-only history/branch-heads view) | controller | request-response (read) | the read-only curation-lists half of `curation_controller.ex` (list actions, `:device_auth` only, no `:idempotency` pipeline) | exact |
| `playstead-server/lib/playstead/sync/snapshot.ex` (extended: mandatory `save:` branch) | service (extension) | request-response (transactional read) | itself — `fetch_catalogue/2` / `fetch_curation/2` inside `read/1`'s `Repo.transaction/2` | exact — must literally add a `save:` key to the same map, same transaction |
| `playstead-server/lib/playstead/export/saves_plan.ex` | service (pure planner) | batch/transform | `playstead-server/lib/playstead/export/layout.ex` (`plan_set/2`, pure struct-in/struct-out planning) | exact |
| `playstead-server/lib/playstead/export/sidecar.ex` (extended: `saves` key gains `branches` + entries; new `saves.txt` writer) | utility (extension) | transform | itself — `root/1` and `set/1`'s existing `"saves" => %{"kind" => "reserved", "entries" => []}` literal | exact |
| `playstead-server/lib/playstead/export/layout.ex` (extended: saves-scope-aware `plan_set`) | service (extension) | batch/transform | itself — `plan_set/2` already computes `saves_path` | exact |
| `playstead-server/lib/playstead/readiness.ex` (extended: `open_write/2` with `reserve: :critical`, D-64) | service (extension) | request-response | itself — `required_bytes/2` / `fits_free_space?/3` | exact |
| `playstead-server/lib/playstead/blobs/store/local_disk.ex` (extended: `open_write/2` bypasses margin only) | service (extension) | file-I/O | itself — `open_write/1` → `space_available?/2` → `do_open_write/1` | exact |
| `playstead-server/lib/playstead/blobs/store.ex` (behaviour extended with `open_write/2`) | interface | — | itself | exact |
| Migration: `save_lines`, `save_revisions` tables | migration | schema | `priv/repo/migrations/*curation*` favorites/collections migrations (client-supplied binary_id PK, `user_id` FK, unique/partial indexes) | role-match |
| `playstead-server/test/playstead/saves_test.exs` | test | — | `playstead-server/test/playstead/curation_test.exs` | exact |
| `playstead-server/test/playstead_web/controllers/api/v1/saves_controller_test.exs` | test | — | `playstead-server/test/playstead_web/controllers/api/v1/imports_controller_test.exs` (upload half) + `curation_controller_test.exs` (commit half) | exact |

### Mac Client (Swift)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `playstead-mac/Playstead/Saves/SaveCapturePoller.swift` | service (actor) | event-driven (1 Hz poll) | `playstead-mac/Playstead/Cache/StreamingSHA256.swift` (hashing discipline) + `playstead-mac/Playstead/Sync/OutboxWorker.swift` (actor-serialized periodic work shape) | role-match (no existing pure poller actor; closest are the actor-serialization pattern and the hashing primitive it composes) |
| `playstead-mac/Playstead/Saves/SaveSessionRecovery.swift` | service | event-driven (idempotent replay) | `playstead-mac/Playstead/Sync/JournalApplier.swift` (idempotent-by-key replay: "replaying a page ... is always safe") | role-match |
| `playstead-mac/Playstead/Saves/LaunchSavePlanner.swift` | service (pure planner) | transform | `playstead-mac/Playstead/Readiness/ReadinessEngine.swift` (pure struct-in/struct-out evaluator, zero network, zero side effects except one documented exception) | role-match — ReadinessEngine's "pure with respect to disk, one documented exception" doc comment is the exact shape D-44 asks for |
| `playstead-mac/Playstead/Saves/SaveCompatibilityGate.swift` | service (pure evaluator) | transform | `playstead-mac/Playstead/Readiness/ReadinessEngine.swift`'s `evaluateSaveDirectory()` (local-only, zero-network, returns an outcome + remedy) | role-match |
| `playstead-mac/Playstead/Saves/SaveConflictResolver.swift` | service | CRUD (local mutation) + event-driven (outbox entry) | `playstead-mac/Playstead/Sync/Outbox.swift`'s `enqueue` (optimistic local write + durable outbox row in one transaction) | exact |
| `playstead-mac/Playstead/Saves/SaveUploadLane.swift` (or a priority band inside `Outbox`/`OutboxWorker` — Claude's Discretion) | service (actor) | streaming (upload) | `playstead-mac/Playstead/Sync/OutboxWorker.swift` (`drainOnce`, in-order send, backoff, quarantine) | exact |
| `playstead-mac/Playstead/Sync/JournalApplier.swift` (extended: new `save` case in `applyOne`) | service (extension) | event-driven | itself — the existing `"catalogue"` / `"curation"` `switch` cases | exact |
| `playstead-mac/Playstead/Adapter/AdapterHost.swift` (extended: per-`assetSetID` launch mutex, D-65) | service (extension) | event-driven | itself — `AdapterProcessRegistry`'s existing `NSLock`-guarded dictionary keyed by `ObjectIdentifier(process)` | exact — same locking discipline, new key shape |
| `playstead-mac/Playstead/App/AppPaths.swift` (extended: per-directory backup exclusion, D-63) | config/utility (extension) | file-I/O | itself — `excludeRootFromBackup(fileManager:)` | exact |
| `playstead-mac/Playstead/Readiness/ReadinessEngine.swift` (extended: widen `evaluateSaveDirectory`, D-42) | service (extension) | transform | itself — `evaluateSaveDirectory()` | exact |
| `playstead-mac/Playstead/Persistence/Migrations.swift` (extended: save tables) | migration | schema | itself — existing curation/catalogue migration blocks | exact |
| `playstead-mac/Playstead/Persistence/SaveStore.swift` | model/store | CRUD | `playstead-mac/Playstead/Persistence/CurationStore.swift` | exact |
| `playstead-mac/Playstead/Saves/SaveStateSurfacing.swift` (or view-model) | component/view-model | transform (render-only, "durability read from SQLite, never hashed at render" per D-39) | `playstead-mac/Playstead/Design/StatusToken.swift` (the existing status-rank vocabulary the card's rank-1 rung must union into) | role-match |
| `playstead-mac/Playstead/Saves/SaveHistorySheet.swift` (per-game timeline, SwiftUI) | component | request-response (local read) | closest existing per-game sheet in `Library/` (P3's game detail sheet) — **verify exact file name with Glob before planning**; not read this session | role-match (unverified path — flag for planner) |
| `playstead-mac/Playstead/Saves/ConflictComparisonSheet.swift` | component | request-response (local read + local mutation) | same P3 sheet pattern as above | role-match (unverified path) |
| `playstead-mac/PlaysteadTests/SavesTests/*.swift` | test | — | `playstead-mac/PlaysteadTests/*CurationTests*` / `*OutboxTests*` (per `TestPlans/Unit.xctestplan` registration pattern) | exact |

### LiveView console (partial vocabulary, D-67)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `playstead-server/lib/playstead_web/live/saves_live.ex` (or similar — inspect/choose/export, no playhead) | controller (LiveView) | request-response | Existing curation/attention LiveView console page (not read this session — **planner must Glob `lib/playstead_web/live/` for the closest existing inbox/console LiveView to confirm the module name before planning**) | role-match (unverified path — flag for planner) |

## Pattern Assignments

### `playstead-server/lib/playstead/saves.ex` (service, CRUD + event-driven)

**Analog:** `playstead-server/lib/playstead/curation.ex`

**Core commit pattern** (curation.ex lines 55-101, `add_favorite/3`):
```elixir
def add_favorite(user_id, id, asset_set_id) do
  changeset = Favorite.create_changeset(%Favorite{}, %{id: id, user_id: user_id, asset_set_id: asset_set_id})

  multi =
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:favorite, changeset,
      on_conflict: :nothing, conflict_target: [:user_id, :asset_set_id]
    )
    |> Ecto.Multi.run(:journal, fn _repo, %{favorite: favorite} ->
      # ChangeJournal.append/tombstone happens inside this SAME Ecto.Multi —
      # never a separate transaction (this is the moduledoc's load-bearing rule)
      ...
    end)

  Repo.transaction(multi)
end
```
Apply directly to `Saves.commit_revision/N`: `Ecto.Multi.new() |> Ecto.Multi.run(:blob, ...) |> Ecto.Multi.insert(:revision, ...) |> Ecto.Multi.run(:journal, ...) |> Ecto.Multi.run(:idempotency_receipt, ...) |> Repo.transaction()` — D-26's exact four-step commit order (blob → revision → journal → receipt).

**Moduledoc discipline to copy verbatim** (curation.ex lines 8-14):
```elixir
# and `Playstead.Sync.ChangeJournal`'s moduledocs require: the row
# ...
# `tombstone/3`) happen inside one `Ecto.Multi`, never a separate
```

---

### `playstead-server/lib/playstead_web/controllers/api/v1/saves_controller.ex` (controller, streaming + request-response)

**Analog A (streamed upload half):** `playstead-server/lib/playstead_web/controllers/api/v1/imports_controller.ex`

**Imports pattern** (lines 1-13):
```elixir
defmodule PlaysteadWeb.Api.V1.ImportsController do
  @moduledoc """
  `PUT /api/v1/imports/uploads/:command_id` ... reads the request body
  as a stream and feeds it directly through `Playstead.Blobs.put_stream/3`
  — never accumulating the whole body in memory ...
  """
  use PlaysteadWeb, :controller
  alias Playstead.{CommandId, Idempotency, Import}
  action_fallback PlaysteadWeb.Api.V1.FallbackController
  @chunk_size 1_048_576
```

**Streaming body pattern** (lines 82-98):
```elixir
defp run_upload(conn, device, params) do
  key = conn.assigns.idempotency_key
  fingerprint = conn.assigns.idempotency_fingerprint
  expected_sha256 = conn.assigns.expected_sha256
  declared_length = conn.assigns.declared_length

  effect_fun = fn ->
    conn
    |> body_stream()
    |> Playstead.Blobs.put_stream(declared_length, expected_sha256: expected_sha256)
    |> handle_store_result(device, original_name)
  end

  case Idempotency.execute(device.id, key, fingerprint, effect_fun) do
    {:ok, status, body} -> conn |> put_status(status) |> json(body)
    {:error, :conflict} -> conn |> put_resp_header("retry-after", "1") |> PlaysteadWeb.Problem.send_problem(409, :idempotency_key_conflict, "...")
    {:error, reason} -> PlaysteadWeb.Api.V1.FallbackController.call(conn, {:error, reason})
  end
end
```

**`Stream.resource` chunked body reader** (lines 83-99, verbatim reusable):
```elixir
defp body_stream(conn) do
  Stream.resource(
    fn -> {conn, :more} end,
    fn
      {_conn, :done} -> {:halt, nil}
      {conn, :more} ->
        case Plug.Conn.read_body(conn, length: @chunk_size) do
          {:ok, chunk, conn} -> {[chunk], {conn, :done}}
          {:more, chunk, conn} -> {[chunk], {conn, :more}}
        end
    end,
    fn _ -> :ok end
  )
end
```
For `PUT /api/v1/saves/uploads/:command_id`, swap `Import.import_single/3` for a save-specific TTL'd pending-blob commit (D-16); `@chunk_size` and `body_stream/1` copy verbatim.

**Analog B (idempotent metadata-commit half):** `playstead-server/lib/playstead_web/controllers/api/v1/curation_controller.ex`

**Idempotent commit pattern** (lines 21-36, `create_favorite/2`):
```elixir
def create_favorite(conn, %{"asset_set_id" => asset_set_id} = params) do
  device = conn.assigns.current_device
  key = conn.assigns.idempotency_key
  fingerprint = conn.assigns.idempotency_fingerprint
  id = params["id"] || Ecto.UUID.generate()

  effect_fun = fn ->
    case Curation.add_favorite(device.user_id, id, asset_set_id) do
      {:ok, favorite} -> {:ok, 200, favorite_json(favorite)}
      {:error, reason} -> {:error, reason}
    end
  end

  run_idempotent(conn, device, key, fingerprint, effect_fun)
end
```
For `POST /api/v1/saves/revisions`, `effect_fun` calls `Saves.commit_revision/N` instead of `Curation.add_favorite/3`; the moduledoc at lines 1-9 explicitly names this shape as the one to follow "verbatim."

**Error handling pattern:** Both controllers delegate every non-2xx branch to `action_fallback PlaysteadWeb.Api.V1.FallbackController` — new problem codes (`save_binding_incompatible` 422, `save_revision_digest_mismatch` 422, `save_revision_too_large` 413, `save_parent_unknown` 409, `save_branch_limit_exceeded`, `save_revision_immutable`) register in `PlaysteadWeb.Problem`/`error_codes.ex` exactly like every existing code, then flow through this same fallback controller unmodified.

---

### `playstead-server/lib/playstead/sync/snapshot.ex` (extended, request-response/transactional read)

**Analog:** itself

**Transactional multi-domain read pattern** (lines 95-120):
```elixir
def read(user_id, opts \\ []) do
  ...
  Repo.transaction(fn ->
    ...
    %{
      catalogue: fetch_catalogue(user_id, as_of_time),
      ...
      curation: fetch_curation(user_id, as_of_time)
    }
  end)
end
```
D-17 mandates a mandatory `save:` branch added to this exact map, inside the exact same `Repo.transaction/2`/`SET TRANSACTION` isolation-level discipline documented in the moduledoc (lines 1-45) — add `save: fetch_saves(user_id, as_of_time)` following `fetch_curation/2`'s shape (a private function reading a bounded, user-scoped set of rows as-of the snapshot cursor).

---

### `playstead-server/lib/playstead/export/sidecar.ex` (extended)

**Analog:** itself — the already-reserved key

**Reserved-key-to-fill pattern** (lines 27-34, `root/1`):
```elixir
def root(opts \\ []) do
  %{
    "kind" => "root",
    "schema" => @schema_id,
    "saves" => %{"kind" => "reserved", "entries" => []},
    "generator" => Keyword.get(opts, :generator, "playstead")
  }
end
```
D-60: change `"saves"` to always populate a `branches` key (even when linear — a single-element list, never a bare flat list that implies one history), fed from `Export.SavesPlan`'s pure output. `set/1` (lines 36-58) needs the identical change to its own `"saves"` entry.

**Reserved-name collision guard to reuse, not reinvent** (`playstead-server/lib/playstead/export/sanitize.ex` lines 66-79):
```elixir
def safe?(name) when is_binary(name) do
  case component(name) do
    {^name, false} -> true
    _ -> false
  end
end

@spec collision_key(String.t()) :: String.t()
def collision_key(name) when is_binary(name) do
  name |> String.normalize(:nfc) |> String.downcase()
end

@spec reserved_saves_name?(String.t()) :: boolean()
def reserved_saves_name?(name) when is_binary(name) do
  collision_key(name) == @reserved_saves_name
end
```
Already guards against a member literally named `saves` colliding with the reserved folder — no new sanitize code needed, only a caller in `Export.SavesPlan`.

---

### `playstead-server/lib/playstead/readiness.ex` + `blobs/store/local_disk.ex` (extended, D-64)

**Analog:** themselves

**Existing margin formula to leave untouched** (`readiness.ex` lines 366-373):
```elixir
def required_bytes(requested_bytes, capacity_bytes)
    when is_integer(requested_bytes) and requested_bytes >= 0 and
           is_integer(capacity_bytes) and capacity_bytes >= 0 do
  margin = max(@min_free_margin_bytes, div(capacity_bytes * 5, 100))
  requested_bytes + margin
end
```

**Existing single-arity call site to extend, not replace** (`blobs/store/local_disk.ex` lines 35-50):
```elixir
@impl true
def open_write(byte_size_hint) do
  path = blob_path()
  if space_available?(path, byte_size_hint) do
    do_open_write(path)
  else
    {:error, :insufficient_space}
  end
end

defp space_available?(path, byte_size_hint) do
  available = Playstead.Readiness.free_bytes(path)
  capacity = capacity_bytes(path)
  case {available, capacity} do
    {avail, cap} when is_integer(avail) and is_integer(cap) ->
      Playstead.Readiness.fits_free_space?(byte_size_hint, avail, cap)
    _unknown -> true
  end
end
```
D-64's fix is additive: `open_write(byte_size_hint, opts \\ [])` with `opts[:reserve] == :critical` routing to a variant of `space_available?/2` that checks only the **physical** available-bytes floor (a new 64 MiB hard floor constant) and skips the `required_bytes/2` margin call entirely — never modify `required_bytes/2` itself, since large-download callers must keep using the full margin.

---

### `playstead-mac/Playstead/Readiness/ReadinessEngine.swift` (extended, D-42)

**Analog:** itself

**Pure, zero-network evaluator pattern to extend** (lines 248-262):
```swift
private func evaluateSaveDirectory() -> ReadinessCheck {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    let exists = fm.fileExists(atPath: saveDirectoryURL.path, isDirectory: &isDir)
    let writable = exists && isDir.boolValue && fm.isWritableFile(atPath: saveDirectoryURL.path)
    guard writable else {
        return ReadinessCheck(
            kind: .saveDirectory,
            outcome: .blocked("Save directory not writable."),
            finding: "Playstead can't currently write saves to its save directory.",
            remedy: Remedy(title: "Repair save directory", action: .repairSaveDirectory)
        )
    }
    return ReadinessCheck(kind: .saveDirectory, outcome: .ready, finding: "Save directory is writable.", remedy: nil)
}
```
D-42 widens the body to attempt an actual atomic temp-file place-and-remove inside `saveDirectoryURL` rather than only checking `isWritableFile` — same `ReadinessCheckKind.saveDirectory`, same `.repairSaveDirectory` remedy identifier (only its **visible label** changes, per D-42/locked copy, from "Repair save directory" to "Repair save folder" — update the `Remedy(title:)` string only, not the `RemedyAction` case name).

**Struct-level "pure with one documented exception" doc comment to mirror for `LaunchSavePlanner`** (lines 1-21 moduledoc): copy this exact rhetorical shape (zero network, pure w.r.t. disk except one named exception) for `LaunchSavePlanner`'s own header comment, substituting D-44's single governing invariant sentence.

---

### `playstead-mac/Playstead/Sync/Outbox.swift` + `OutboxWorker.swift` (analog for save upload lane and conflict resolution mutation)

**Analog:** themselves

**Optimistic-write-plus-durable-row-in-one-transaction pattern** (`Outbox.swift` lines 48-56 moduledoc, to mirror in `SaveConflictResolver`):
```
/// `enqueue` applies the intent's optimistic local write and durably
/// records the entry inside one transaction, so a crash between the
/// local write and the network send can never lose the entry
```

**In-order, backoff, quarantine drain pattern** (`OutboxWorker.swift` lines 60-77):
```swift
actor OutboxWorker {
    ...
    func drainOnce(at now: Date = Date()) async -> OutboxDrainResult {
        var result = OutboxDrainResult()
        for entry in outbox.listPending(at: now) {
            guard let intent = entry.intent else { continue }
            do {
                try outbox.markInFlight(entry.id)
            } catch {
                // A local persistence failure marking this entry
```
D-32's save-only upload lane, whether a distinct actor or a priority band (Claude's Discretion), must preserve this exact ordering/backoff/quarantine discipline — `Outbox.maxAttempts = 8`, `retryDelay(forAttempt:)` exponential backoff capped at `maxRetryDelaySeconds`, and `OutboxEntryState.quarantined`'s explicit "**no quarantine-to-silence terminal state**" constraint (D-32) means the save lane's quarantine equivalent must still surface as an attention state after 24h, unlike curation's silent quarantine.

---

### `playstead-mac/Playstead/App/AppPaths.swift` (extended, D-63)

**Analog:** itself

**Single-flag-on-root pattern to replace with per-directory application** (lines 39-58):
```swift
init(root: URL, fileManager: FileManager = .default) {
    ...
    createDirectoriesIfNeeded(fileManager: fileManager)
    excludeRootFromBackup(fileManager: fileManager)
}

private func createDirectoriesIfNeeded(fileManager: FileManager) {
    for dir in [root, objects, partials, launch, emulators, bios] {
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}

private func excludeRootFromBackup(fileManager: FileManager) {
    var mutableRoot = root
    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    try? mutableRoot.setResourceValues(resourceValues)
}
```
D-63: change `excludeRootFromBackup` to iterate `[objects, partials, launch, emulators, bios]` individually (never `root`, never `saves` — `saves` is deliberately **outside** this managed list already, so it is never excluded and therefore already Time-Machine-eligible by omission), plus an idempotent launch-time clear of the stale root flag for existing installs (a new one-time migration-style function, not shown in any existing file — flag as build-fresh in Discretion section).

---

### `playstead-mac/Playstead/Adapter/AdapterHost.swift` (extended, D-65)

**Analog:** itself

**Existing NSLock-guarded registry to extend with a keyed mutex** (lines 29-50):
```swift
final class AdapterProcessRegistry: @unchecked Sendable {
    static let shared = AdapterProcessRegistry()
    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]
    func register(_ process: Process) {
        lock.lock()
        processes[ObjectIdentifier(process)] = process
        ensureObservingLocked()
        lock.unlock()
    }
}
```
D-65's per-`assetSetID` launch mutex is a sibling structure (a second `NSLock`-guarded dictionary, keyed by `assetSetID: String` rather than `ObjectIdentifier(process)`) spanning prepare → spawn → exit — same locking discipline, new key domain, added alongside (not replacing) this registry.

---

### `playstead-mac/Playstead/Adapter/AdapterExit.swift` (read-only reference for D-05's anti-pattern)

**Analog:** itself, as the thing capture code must NOT branch on

**Signal classification, not a durability guarantee** (lines 1-30):
```swift
enum AdapterExit: Equatable {
    case clean
    case crashed
    case killed
    case unknown(status: Int32, reason: String)
    static func classify(status: Int32, reason: Process.TerminationReason, against detection: AdapterExitDetection) -> AdapterExit { ... }
}
```
`SaveCapturePoller`/`SaveSessionRecovery`'s post-exit settle pass must call the unconditional settle regardless of which `AdapterExit` case this classifier returns (D-05) — this file is read to confirm there are exactly four cases and none should ever gate the settle pass, not extended.

---

### `playstead-mac/Playstead/Cache/StreamingSHA256.swift` (reference for D-06's single-buffer digest)

**Analog:** itself (as a *counter-example* to mirror carefully)

**Existing incremental hasher** (lines 9-35): this file exists for large-file resumable hashing. D-06 is explicit that a 32 KB save artifact gets **one buffer, one digest, one stored object** — do not reuse `StreamingSHA256`'s incremental/resumable API for save capture; a plain `SHA256.hash(data:)` one-shot call over the full in-memory buffer is correct here, and `StreamingSHA256` is "reserved for a future large or multi-file artifact" per D-06 verbatim.

---

### `playstead-mac/Playstead/Cache/LaunchMaterializer.swift` (reference for D-47's stage/fsync/rename discipline)

**Analog:** itself

**Never-write-in-place / rebuild-fresh discipline** (lines 20-27, moduledoc):
```
/// Per D-20 this must never create a hard link: an emulator writing
/// through a hard link would write through into the verified cache
/// object and destroy the custody guarantee. `copyItem` never produces
/// a hard link on APFS — it clones (copy-on-write) or fully copies
```
D-47's save-restore write path (stage → `fsync` → `rename` → `fsync`(dir)) is the save-specific analog of this file's copy-into-launch-dir discipline; `LaunchMaterializer.materialize`'s existing `removeItem`-then-rebuild pattern for `launch/` is also the reason saves must live at a **sibling** path (`saves/<assetSetID>/`, confirmed already correct by `PlaysteadApp.saveDirectoryURL`) rather than inside `launch/`.

## Shared Patterns

### Idempotent commit via `Idempotency.execute/4`
**Source:** `playstead-server/lib/playstead/idempotency.ex:33-47,91` (`fingerprint/1`, `execute/4`)
**Apply to:** `SavesController.create_revision/2`, `SavesController` upload half via the same `assigns.idempotency_key`/`idempotency_fingerprint` pattern already wired by the `:idempotency` router pipeline; every LiveView-console mutating action.
```elixir
def fingerprint(%{method: method, path: path, body: body}) do
  canonical = {method, path, canonicalize(body)}
  :crypto.hash(:sha256, :erlang.term_to_binary(canonical)) |> Base.encode16(case: :lower)
end
```
This operates on a **parsed body only** — the documented reason D-16 forces the two-endpoint split; do not attempt to fingerprint the streamed upload body with this function.

### `Ecto.Multi` transaction discipline (row + `ChangeJournal` entry, never separate transactions)
**Source:** `playstead-server/lib/playstead/curation.ex` (every mutating function, e.g. lines 70-90)
**Apply to:** `Saves.commit_revision/N`, `Saves.resolve_divergence/N` (D-48's append-only resolution) — both must insert their row and their `ChangeJournal` entry inside the same `Ecto.Multi`.

### Reserved export slot fill (never redesign the tree)
**Source:** `playstead-server/lib/playstead/export/{layout,sidecar,sanitize}.ex`
**Apply to:** `Export.SavesPlan`, `Sidecar.root/1`, `Sidecar.set/1` — the `saves_path`/`"saves"` reservation already exists; this phase only populates it.

### Local, zero-network evaluation (no server join at decision time)
**Source:** `playstead-mac/Playstead/Readiness/ReadinessEngine.swift` (entire file's moduledoc + `evaluateSaveDirectory()`)
**Apply to:** `LaunchSavePlanner`, `SaveCompatibilityGate` — both must be pure functions over already-denormalized local inputs, exactly like `ReadinessEngine.evaluate` is pure over `CASManager`/`DownloadQueue`/`FileManager` state with zero network calls.

### Actor-serialized, in-order, backoff-then-quarantine drain
**Source:** `playstead-mac/Playstead/Sync/OutboxWorker.swift` (`drainOnce`, `Outbox.maxAttempts`, `retryDelay(forAttempt:)`)
**Apply to:** the save-only upload lane (D-32) — reuse this exact actor-serialization/backoff/quarantine shape; the only behavioral delta is D-32's "no quarantine-to-silence" requirement (surface an attention state after 24h instead of going silent).

### Never write in place; stage → fsync → rename → fsync(dir)
**Source:** `playstead-mac/Playstead/Cache/LaunchMaterializer.swift` (moduledoc, D-20's hard-link prohibition) and `playstead-server/lib/playstead/blobs/store/local_disk.ex` (moduledoc, "temp-then-fsync-then-verify-then-atomic-rename")
**Apply to:** every save-blob write on both tiers (D-06 client-side, D-47 launch-path restore, D-25 server-side CAS reuse) — this is the single durability discipline already proven twice in the shipped codebase; save capture is a third application of the identical pattern, never a new one.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| A saves-owned attention source (D-66's "not `Attention.Reason`") | service | event-driven | `playstead-server/lib/playstead/attention.ex`/`Item`/`Derive`/`Reason` is explicitly the pattern to study **and then deliberately not extend** — `Attention.Reason` is frozen per D-66. The closest shape to copy is `Item`'s upsert-by-grouping-key pattern (`attention.ex` lines 53-63: `Repo.insert(changeset, on_conflict: [inc: [count: 1]], conflict_target: [:user_id, :grouping_key, :reason])`), but the new saves-owned source must be its own table/module unioned into the inbox view at read time, never a member of `Attention.Reason` itself. Planner should design this as new, following the `Item` upsert shape but with its own reason vocabulary. |
| `playstead-mac/Playstead/Saves/SaveHistorySheet.swift`, `ConflictComparisonSheet.swift` | component | request-response | No per-game SwiftUI detail sheet was read this session (out of budget) — CONTEXT.md D-37/D-53 name the target (reached from a Save row in the existing Ready-to-Play surface; three entry points including the LiveView console) but the exact existing sheet file to mirror was not confirmed by path. **Planner action: Glob `playstead-mac/Playstead/Library/*.swift` for the existing game-detail/Ready-to-Play sheet before writing this plan's action section.** |
| `playstead-server/lib/playstead_web/live/*.ex` console page for saves inspect/choose/export | controller (LiveView) | request-response | No existing LiveView console page was read this session. **Planner action: Glob `playstead-server/lib/playstead_web/live/` for the closest existing inbox/attention console LiveView (D-67's "full vocabulary parity with partial verbs" target) before writing this plan's action section.** |
| Probe SAVE-P1 harness | test/instrumentation | file-I/O | Explicitly Claude's Discretion in CONTEXT.md — no existing probe harness in this codebase to copy from; the closest prior-art shape is Phase 3's spike script (`watch-save.sh`, gitignored/gone per D-01/D-02) — describe as build-fresh, following `03-SPIKE-REPORT.md`/`03-ADAPTER-PIN.json`'s report-artifact convention referenced in RESEARCH.md's Open Questions §1. |

## Metadata

**Analog search scope:** `playstead-server/lib/playstead/{curation,curation/*,attention,attention/*,sync,export,blobs,blobs/store,readiness.ex}`, `playstead-server/lib/playstead_web/controllers/api/v1/*`, `playstead-mac/Playstead/{Cache,Sync,Adapter,App,Persistence,Readiness,Design}/*`
**Files scanned:** ~35 read directly this session (line-ranged where large), plus directory listings across both trees
**Pattern extraction date:** 2026-09-03
