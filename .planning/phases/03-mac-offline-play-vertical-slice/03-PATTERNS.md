# Phase 3: Mac Offline Play Vertical Slice - Pattern Map

**Mapped:** 2026-08-30
**Files analyzed:** 21 (10 server-side additive/modified, 11 Mac client greenfield surfaces)
**Analogs found:** 10 / 10 server-side (exact or role-match); 0 / 11 client-side (greenfield — mapped to conceptual seams, not code analogs)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `playstead-server/lib/playstead_web/controllers/api/v1/blobs_controller.ex` (harden) | controller | streaming, request-response | itself (existing, to be hardened) | exact — modify in place |
| `playstead-server/lib/playstead/blobs/store/local_disk.ex` (harden `build_stream/2`) | service (storage adapter impl) | streaming, file-I/O | itself (existing, to be hardened) | exact — modify in place |
| `playstead-server/lib/playstead/sync/entity_kind.ex` (add `curation` kind) | config/registry | CRUD (vocabulary) | itself | exact — additive one-line change |
| `playstead-server/lib/playstead/sync/snapshot.ex` (add `curation` branch) | service | CRUD, request-response | itself; branch pattern = `fetch_catalogue/2` / `fetch_jobs/2` | exact — additive function + call-site in `read/2` |
| `playstead-server/lib/playstead/curation.ex` (new context) | service (Phoenix context) | CRUD | `playstead-server/lib/playstead/catalogue.ex` | role-match — scoped context, `Scope`-first functions, changesets |
| `playstead-server/lib/playstead/curation/favorite.ex`, `collection.ex`, `collection_member.ex`, `queue_item.ex` (new schemas) | model | CRUD | `playstead-server/lib/playstead/catalogue/asset_set.ex` | role-match — `binary_id` PK, `user_id` FK, changeset pattern |
| `playstead-server/lib/playstead_web/controllers/api/v1/curation_controller.ex` (or per-noun controllers) (new) | controller | request-response, CRUD | `playstead-server/lib/playstead_web/controllers/api/v1/exports_controller.ex` + `attention_controller.ex` | exact — Idempotency-Key mutation + plain read pattern |
| `playstead-server/lib/playstead_web/controllers/api/v1/play_sessions_controller.ex` (new) | controller | request-response, event-driven | `playstead-server/lib/playstead_web/controllers/api/v1/exports_controller.ex` (`create/2`) | role-match — single POST, Idempotency-gated, minimal payload |
| `playstead-server/lib/playstead_web/router.ex` (add routes) | route | request-response | itself — existing `scope "/api/v1/exports"` / `"/attention"` blocks | exact — same pipe_through idiom |
| `playstead-server/lib/playstead_web/live/library_live.ex` (extend w/ curation shelves) | component (LiveView) | request-response, CRUD | itself (existing) | exact — extend in place, same `Catalogue`-style context calls |
| `playstead-server/lib/playstead/protocol/capabilities.ex` (advertise `range-resume` under `transfer`) | config | request-response | itself | exact — additive within existing namespace map |
| `playstead-mac/Playstead/Sync/SyncEngine.swift` (new) | service | event-driven, pub-sub (poll+apply) | server: `Playstead.Sync.ChangeJournal` / `Snapshot` (protocol shape only) | no analog — greenfield; protocol contract is the analog, not code |
| `playstead-mac/Playstead/Cache/DownloadEngine.swift` (new) | service | streaming, file-I/O | server: `Blobs.Store.LocalDisk.stream/2` (mirrors CAS + range contract) | no analog — greenfield |
| `playstead-mac/Playstead/Cache/CASManager.swift`, `QuotaManager.swift` (new) | service | file-I/O, CRUD | server: `Blobs.Store.LocalDisk` (CAS layout precedent, D-20 mirrors P2 D-11) | no analog — greenfield |
| `playstead-mac/Playstead/Adapter/AdapterHost.swift` (new) | service (process host) | event-driven | none server-side; Apple `Process` API | no analog — greenfield |
| `playstead-mac/Playstead/Curation/*ViewModel.swift` (new) | provider/store | CRUD, request-response | server: `Playstead.Curation` context (same REST intents/shapes) | no analog — greenfield, but must mirror server payload shapes exactly |
| `playstead-mac/Playstead/Library/*View.swift` (new) | component | request-response | server: `library_live.ex` (same IA/status vocabulary, D-17) | no analog — greenfield, shared spec not shared code |
| `playstead-mac/Playstead/Controller/ControllerHost.swift` (new) | service | event-driven | none | no analog — greenfield, GameController framework |
| `playstead-mac/Playstead/Persistence/*.swift` (new SQLite models) | model | CRUD | none | no analog — greenfield |
| `playstead-mac/PlaysteadTests/*` (new) | test | — | server: `test/playstead_web/controllers/api/v1/blobs_controller_test.exs` (contract shape to satisfy) | no analog — greenfield XCTest target |
| `03-SPIKE-REPORT.md` (new) | doc/artifact | — | none | no analog — new artifact type, format is Claude's Discretion |

## Pattern Assignments

### `playstead-server/lib/playstead_web/controllers/api/v1/blobs_controller.ex` (controller, streaming — D-19 hardening)

**Analog:** itself, current state (verified this session)

**Current code to replace** (lines 19-34):
```elixir
def show(conn, %{"sha256" => sha256}) do
  device = conn.assigns.current_device

  with true <- authorized?(device.user_id, sha256),
       true <- playable?(device.user_id, sha256),
       {:ok, stream} <- Playstead.Blobs.stream(sha256) do
    conn
    |> put_resp_header("etag", sha256)              # BUG: unquoted — must be `"\"#{sha256}\""`
    |> put_resp_content_type("application/octet-stream")
    |> send_chunked(200)                              # BUG: ignores Range entirely
    |> stream_chunks(stream)
  else
    false -> {:error, :not_found}
    {:error, :not_found} -> {:error, :not_found}
  end
end
```

**What must change (D-19):** parse `Range`/`If-Range` before calling `Playstead.Blobs.stream/2`, quote the ETag, emit `Accept-Ranges: bytes`, respond `206`+`Content-Range` for a valid single range, `416` for out-of-bounds, `200` for absent/multi-range, support `HEAD`. Keep `authorized?/2` and `playable?/2` gating **identical** for the Range/HEAD path — this is Security Domain V4 (no Range-based authz bypass).

**Auth pattern to preserve exactly** (lines 36-56) — do not weaken while adding Range logic:
```elixir
defp authorized?(user_id, sha256) do
  from(sf in SourceFile,
    join: b in assoc(sf, :blob),
    where: sf.user_id == ^user_id and b.sha256 == ^sha256
  )
  |> Repo.exists?()
end

defp playable?(user_id, sha256) do
  case Playstead.Blobs.get_by_sha256(sha256) do
    nil -> false
    blob ->
      not Playstead.Blobs.quarantined?(blob) or
        Playstead.Blobs.released_for_user?(user_id, blob.id)
  end
end
```

**Error handling pattern:** `action_fallback PlaysteadWeb.Api.V1.FallbackController` (line 17) plus `with`/`else` degrading to `{:error, :not_found}` — reuse unchanged; a new `416` path returns via `PlaysteadWeb.Problem.send_problem/4` (see Shared Patterns below), not a bare `send_resp`.

---

### `playstead-server/lib/playstead/blobs/store/local_disk.ex` (service, streaming/file-I/O — D-19 memory-hazard fix)

**Analog:** itself, current state (verified this session)

**Current bug to fix** (lines 325-341):
```elixir
def stream(sha256, range \\ nil) do
  path = object_path(blob_path(), sha256)
  if File.exists?(path) do
    {:ok, build_stream(path, range)}
  else
    {:error, :not_found}
  end
end

defp build_stream(path, nil), do: File.stream!(path, [], @chunk_size)

defp build_stream(path, first..last//_step) do
  data = File.read!(path)                     # loads ENTIRE file into memory
  last = min(last, byte_size(data) - 1)
  [binary_part(data, first, last - first + 1)]
end
```

**Required fix shape (target, not yet in repo):** replace `File.read!/1` + `binary_part` with `:file.pread/3` at the requested offset/length (or `File.stream!/3` with an initial byte offset via `IO.binstream`), so only the requested range is read. The `Store` behaviour's `stream/2` callback signature (`playstead-server/lib/playstead/blobs/store.ex` line 52) is unchanged — only this implementation's range branch changes.

**Sibling read-only pattern to copy the discipline from** (`read_leading/2`, referenced in `store.ex` lines 55-65): read-only, `{:error, :not_found}` on missing object, never deletes/renames/truncates — same guarantee the new range-pread implementation must uphold.

---

### `playstead-server/lib/playstead/sync/entity_kind.ex` (config/registry, CRUD vocabulary — D-08)

**Analog:** itself

**Current code** (line 13):
```elixir
@kinds ~w(device pairing catalogue job transfer save)a
```

**Change:** append `curation` — additive only, per the module's own frozen-vocabulary discipline documented in its `@moduledoc` (lines 1-11). `Playstead.Sync.Entry`'s changeset already validates every write against `EntityKind.valid?/1`, so no other file needs to change for the registry itself.

---

### `playstead-server/lib/playstead/sync/snapshot.ex` (service, CRUD/request-response — D-08 curation branch)

**Analog:** itself — `fetch_catalogue/2` (lines 157-166) and `fetch_jobs/2` (lines 172-180) are the exact precedent for a new `fetch_curation/2` branch.

**Pattern to copy** (lines 154-180):
```elixir
# D-23: the catalogue branch, read from the same transaction as the
# device page above so a resuming client sees a catalogue snapshot
# and an as-of cursor with no gap and no overlap.
defp fetch_catalogue(user_id, as_of_time) do
  from(a in AssetSet,
    where: a.user_id == ^user_id,
    where: a.inserted_at <= ^as_of_time,
    order_by: [asc: a.id]
  )
  |> Repo.all()
  |> Repo.preload(asset_members: :blob)
  |> Enum.map(&CataloguePayload.build/1)
end

defp fetch_jobs(user_id, as_of_time) do
  from(s in Session,
    where: s.user_id == ^user_id,
    where: s.inserted_at <= ^as_of_time,
    order_by: [asc: s.id]
  )
  |> Repo.all()
  |> Enum.map(&job_view/1)
end
```

**Wiring point** — the `read/2` transaction's returned map (lines 100-109) already has the `catalogue:`/`job:` shape; add `curation: fetch_curation(user_id, as_of_time)` alongside them, inside the **same** `Repo.transaction/1` call — this is the load-bearing invariant the module's `@moduledoc` explains (same as-of position, no gap/overlap).

**Isolation-level discipline to preserve** (lines 20-27, 92-93, 127-131): the explicit `SET TRANSACTION ISOLATION LEVEL REPEATABLE READ` and the `set_isolation?/0` test escape hatch — do not add a curation branch that opens its own transaction or bypasses this.

---

### `playstead-server/lib/playstead/curation.ex` (new Phoenix context, CRUD)

**Analog:** `playstead-server/lib/playstead/catalogue.ex`

**Imports/aliases pattern** (catalogue.ex lines 1-19):
```elixir
import Ecto.Query, warn: false

alias Playstead.Accounts.Scope
alias Playstead.AuditLog
alias Playstead.Catalogue.AssetSet
alias Playstead.Repo
```
Mirror this shape: `alias Playstead.Accounts.Scope`, `alias Playstead.Curation.{Favorite, Collection, CollectionMember, QueueItem}`, `alias Playstead.Repo`, `alias Playstead.Sync.ChangeJournal`.

**Scope-first context function convention** (P1 D-01, verified via `Accounts.Scope` struct at `playstead-server/lib/playstead/accounts/scope.ex` lines 21-24 and its use throughout `catalogue.ex`/`library_live.ex`): every new curation context function takes `scope` (or `user_id`, matching the existing controller convention which reads `device.user_id` directly — see `exports_controller.ex`/`attention_controller.ex`) as the first argument and filters every query by it. No curation query may omit the `user_id`/scope filter (Security Domain: per-user scoping).

**Mutation + journal-in-transaction pattern to copy** (from RESEARCH.md Pattern 3, matching `ChangeJournal.append/4`'s documented in-transaction discipline at `change_journal.ex` lines 1-31):
```elixir
Ecto.Multi.new()
|> Ecto.Multi.insert(:favorite, Favorite.create_changeset(...))
|> Ecto.Multi.run(:journal, fn _repo, %{favorite: favorite} ->
  ChangeJournal.append(user_id, :curation, favorite.id, %{
    type: "favorite",
    asset_set_id: favorite.asset_set_id,
    created_at: favorite.inserted_at
  })
end)
|> Repo.transaction()
```
Never open a second transaction for the journal write — `ChangeJournal`'s own `@moduledoc` (lines 1-31) states this is load-bearing.

---

### `playstead-server/lib/playstead/curation/favorite.ex` etc. (new schemas, CRUD)

**Analog:** `playstead-server/lib/playstead/catalogue/asset_set.ex`

**Pattern to copy** (asset_set.ex lines 1-30):
```elixir
use Ecto.Schema
import Ecto.Changeset

@primary_key {:id, :binary_id, autogenerate: true}
@foreign_key_type :binary_id
schema "asset_sets" do
  field :user_id, :id
  field :status, :string, default: "active"
  # ...
  timestamps(type: :utc_datetime)
end

@doc false
def create_changeset(asset_set, attrs) do
  asset_set
  |> cast(attrs, [...])
  # ...
end
```
Mirror `binary_id` PK + `user_id, :id` FK + `timestamps(type: :utc_datetime)`. Per D-09, `favorite`/`collection_member`/`queue_item` additionally carry the client's UUIDv7 natural key (idempotency mechanics, P1 D-20 — see `Idempotency.fingerprint/1` pattern below) and a fractional-index `position` string field for `queue_item`/`collection_member` ordering (D-09/D-10).

---

### `playstead-server/lib/playstead_web/controllers/api/v1/curation_controller.ex` (new, request-response/CRUD)

**Analog:** `playstead-server/lib/playstead_web/controllers/api/v1/exports_controller.ex` (mutation shape) + `attention_controller.ex` (list + resolve/idempotent-action shape)

**Imports pattern** (exports_controller.ex lines 1-14):
```elixir
use PlaysteadWeb, :controller

alias Playstead.{Export, Idempotency}

action_fallback PlaysteadWeb.Api.V1.FallbackController
```

**Idempotency-gated mutation pattern to copy verbatim** (exports_controller.ex lines 21-55, also attention_controller.ex lines 28-65):
```elixir
def create(conn, params) do
  device = conn.assigns.current_device
  key = conn.assigns.idempotency_key
  fingerprint = conn.assigns.idempotency_fingerprint

  effect_fun = fn ->
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
```
Every curation POST/PATCH/DELETE (favorite toggle, collection create, queue reorder settle) follows this exact shape — D-09's "per-row REST intent with Idempotency-Key + client UUIDv7 natural key" requirement maps 1:1 onto this existing pattern; nothing new to invent.

**Read-only list pattern** (attention_controller.ex lines 18-26):
```elixir
def index(conn, params) do
  device = conn.assigns.current_device
  page = Attention.list_items_page(device.user_id, after_cursor: params["cursor"])

  json(conn, %{
    items: Enum.map(page.entries, &item_json/1),
    next_cursor: page.next_cursor
  })
end
```
Use for shelf/list reads if a REST read surface is needed beyond the sync snapshot (LIBR-05 console parity primarily reads via `Curation` context functions directly from LiveView, per D-11).

---

### `playstead-server/lib/playstead_web/controllers/api/v1/play_sessions_controller.ex` (new, request-response/event-driven)

**Analog:** `exports_controller.ex` `create/2` (single-POST, Idempotency-gated, minimal payload) — same pattern as above, but the effect function is a plain insert (UUIDv7 id, game, start/end) with no worker enqueue. D-07: never a launch-path dependency, so no `with`-chain gating on adapter/preflight state — this endpoint only records.

---

### `playstead-server/lib/playstead_web/router.ex` (routes — new curation/play-session/hardened-blobs scopes)

**Analog:** itself — existing scope blocks are the exact template.

**Read-only scope pattern** (lines 190-194, blobs):
```elixir
scope "/api/v1/blobs", PlaysteadWeb.Api.V1 do
  pipe_through [:api, :device_auth]

  get "/:sha256", BlobsController, :show
end
```
No pipeline change needed for the hardened Range/HEAD support — `:device_auth` alone still governs; add a `head "/:sha256", BlobsController, :head_show` (or reuse `show/2` for `HEAD` via Plug's method match) in the same scope block.

**Idempotency-gated mutation scope pattern** (lines 196-202, exports; lines 238-244, attention resolve):
```elixir
scope "/api/v1/exports", PlaysteadWeb.Api.V1 do
  pipe_through [:api, :device_auth, :idempotency]

  post "/", ExportsController, :create
end
```
Copy this exact `pipe_through [:api, :device_auth, :idempotency]` shape for every curation mutation scope (favorites, collections, collection_members, queue_items) and for `POST /api/v1/play-sessions`.

**Read-only scope pattern** (lines 204-209, 222-229): plain `pipe_through [:api, :device_auth]` for curation list/read endpoints if added beyond the sync snapshot.

---

### `playstead-server/lib/playstead_web/live/library_live.ex` (extend — curation shelves, D-11 console parity)

**Analog:** itself, current state

**Load-fresh-every-time convention to preserve** (lines 21-51, module doc lines 1-12): "every load reads fresh from `Playstead.Catalogue`, never from a cached assign" — new curation shelves (Favorites/Collections/Continue/Recent/Queue) must call `Playstead.Curation.*` context functions the same way in `apply_action/3`/`load_assets/1`, not maintain their own LiveView-local state that can drift from the canonical read.

**Event-handling pattern to copy** (lines 53-56):
```elixir
@impl true
def handle_event("dismiss-hint", _params, socket) do
  {:noreply, assign(socket, :hint_dismissed, true)}
end
```
Curation mutations from the console (favorite toggle, queue reorder) follow this `handle_event` → context-function-call → `{:noreply, assign(...)}` shape, calling the **same** `Playstead.Curation` functions the API controllers call (D-11: "same context functions as the API").

---

### `playstead-server/lib/playstead/protocol/capabilities.ex` (advertise `range-resume`)

**Analog:** itself

**Pattern** (lines 18-20, 61-66): `@capability_namespaces` already includes `:transfer`; `supported_client_ranges/0` returns a uniform `%{min:, max:}` per namespace. D-19's `range-resume` advertisement is a documented sub-capability *within* the existing `transfer` namespace's declared version range — no new top-level namespace, no change to `envelope/0`'s frozen shape (moduledoc lines 6-9 explicitly forbid adding/removing/renaming top-level keys). Confirm the exact sub-capability encoding convention against `Playstead.Protocol.Negotiation`/`CapabilityDeclaration` before adding — not fully read this session; treat as a targeted follow-up read during planning if the encoding isn't obvious from `capability_declaration.ex`.

---

### Mac client files (greenfield — no code analog)

All `playstead-mac/Playstead/**` files have **no existing-code analog** since `playstead-mac/` contains only a README. Per the phase-mapper brief, these are mapped to conceptual seams on the server side (the protocol contract, CAS layout precedent, capability namespaces) rather than invented code analogs:

| Client file/module | Conceptual seam it must honor | Source |
|---|---|---|
| `Sync/SyncEngine.swift` | Journal/snapshot/cursor wire shape — entity kinds, `seq`-based cursor, as-of consistency | `Playstead.Sync.ChangeJournal`, `Playstead.Sync.Snapshot` (read for contract, not copied for code) |
| `Cache/DownloadEngine.swift` | Range/If-Range/206/416/quoted-ETag contract (D-19, frozen this phase) | Hardened `BlobsController` (above) — this is the wire contract the Swift actor implements against |
| `Cache/CASManager.swift` | sha256 CAS path layout mirrors P2 D-11/server `object_path/2` | `playstead-server/lib/playstead/blobs/store/local_disk.ex` `object_path/2` (line 421) — same content-addressed layout, D-20 explicit mirror |
| `Curation/*ViewModel.swift` | REST intent shapes (favorite/collection/queue payloads) and Idempotency-Key + UUIDv7 discipline | Curation controller (above) — client payload shape must match server changeset fields exactly |
| `Library/*View.swift` | Status-glyph priority ladder, IA noun order (D-13/D-14/D-17 shared spec, not code) | `library_live.ex` — same *behavioral* parity target, UI-SPEC pass governs exact glyphs |
| `Adapter/AdapterHost.swift` | None — pure Apple `Process` API, spike-gated (D-01) | RESEARCH.md Pattern 4 (unverified until spike) |

No further server-side pattern search is useful for these — the planner should cite RESEARCH.md's Standard Stack / Architecture Patterns sections (Apple API shapes) for these files, not this document.

## Shared Patterns

### Idempotency-Key mutation wrapper
**Source:** `playstead-server/lib/playstead/idempotency.ex` (`execute/4`, lines 76-118) + call-site convention in `exports_controller.ex` lines 21-55 and `attention_controller.ex` lines 28-65
**Apply to:** every new curation mutation controller action, `play_sessions_controller.ex` `create/2`
```elixir
case Idempotency.execute(device.id, key, fingerprint, effect_fun) do
  {:ok, status, body} -> conn |> put_status(status) |> json(body)
  {:error, :conflict} ->
    conn
    |> put_resp_header("retry-after", "1")
    |> PlaysteadWeb.Problem.send_problem(409, :idempotency_key_conflict, "...")
  {:error, reason} -> PlaysteadWeb.Api.V1.FallbackController.call(conn, {:error, reason})
end
```

### Error handling / problem+json
**Source:** `playstead-server/lib/playstead_web/problem.ex` (`send_problem/5`, lines 24-42)
**Apply to:** all new controllers — never hand-build an error JSON body; always go through `PlaysteadWeb.Problem.send_problem/4-5` with a registered code from `PlaysteadWeb.ErrorCodes`. A new `:range_not_satisfiable` (416) code will need registering in `error_codes.ex` for the hardened `BlobsController` (not yet read this session — read `error_codes.ex`'s registry shape during planning before adding the code).

### Journal-in-transaction discipline
**Source:** `playstead-server/lib/playstead/sync/change_journal.ex` (moduledoc lines 1-31, `append/4` lines 43-51)
**Apply to:** every curation mutation context function — `ChangeJournal.append/4` (or `tombstone/3`) must be called inside the same `Ecto.Multi`/transaction as the row mutation it records, never after commit.

### Scope-first, user-filtered context functions
**Source:** `playstead-server/lib/playstead/accounts/scope.ex` (struct, lines 21-24) + usage convention throughout `catalogue.ex`/`library_live.ex`
**Apply to:** every new `Playstead.Curation` context function — first argument is the scope/user_id, every query filters by it (Security Domain: curation endpoints missing per-user scoping is an explicitly named threat in RESEARCH.md's Known Threat Patterns table).

### Route pipeline conventions
**Source:** `playstead-server/lib/playstead_web/router.ex` (scope blocks, lines 148-244)
**Apply to:** all new routes — `[:api, :device_auth]` for reads, `[:api, :device_auth, :idempotency]` for mutations; one `scope` block per pipeline combination, with a one-line `# D-xx:` comment explaining why that combination applies (existing convention throughout the file).

## No Analog Found

Files with no close in-repo match — planner should cite RESEARCH.md's Standard Stack / Architecture Patterns / Code Examples sections instead:

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `playstead-mac/Playstead/**/*.swift` (all ~11 modules) | various | various | `playstead-mac/` is greenfield (README only, verified this session); no Swift code exists anywhere in the repo to pattern-match against. RESEARCH.md's Pattern 1/2/4 code examples and Standard Stack table are the authoritative reference instead. |
| `playstead-mac/PlaysteadTests/**` | test | — | No XCTest target exists yet; RESEARCH.md's Validation Architecture section defines the target test map. |
| `03-SPIKE-REPORT.md` | doc/artifact | — | New artifact type (Claude's Discretion per CONTEXT.md on exact format); no precedent document exists in this repo to copy structure from. |
| `playstead-server/lib/playstead_web/error_codes.ex` (new `:range_not_satisfiable` entry) | config | — | Not read this session in full; planner must read its registry shape (likely a `%{atom => {status, title}}` map similar to `Capabilities.supported_client_ranges/0`'s shape) before adding the new code — flagged here rather than guessed. |
| `playstead-server/lib/playstead/protocol/capability_declaration.ex` / `negotiation.ex` (sub-capability encoding for `range-resume`) | service | — | Not read this session; `capabilities.ex` confirms the `transfer` namespace exists, but the exact sub-capability-within-namespace encoding convention needs a targeted read during planning. |

## Metadata

**Analog search scope:** `playstead-server/lib/playstead/**`, `playstead-server/lib/playstead_web/**`, `playstead-mac/` (confirmed greenfield)
**Files scanned (read in full or targeted):** `blobs_controller.ex`, `local_disk.ex` (targeted), `store.ex`, `entity_kind.ex`, `change_journal.ex`, `snapshot.ex`, `idempotency.ex`, `capabilities.ex`, `hello_controller.ex`, `library_live.ex`, `router.ex` (targeted), `catalogue.ex` (partial), `accounts/scope.ex`, `exports_controller.ex`, `attention_controller.ex`, `catalogue/asset_set.ex` (partial), `problem.ex` (partial)
**Pattern extraction date:** 2026-08-30
