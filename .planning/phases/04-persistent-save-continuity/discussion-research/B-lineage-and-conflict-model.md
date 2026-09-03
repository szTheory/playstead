# Area B — Revision lineage and conflict detection model (SAVE-04 mechanism)

Scope: how save divergence is **represented, detected, and stored** — the data
model and the wire protocol. Not the UX (area G), not when a capture fires
(area A), not what may be pruned (area D), not the compatibility gate (area C).

Everything asserted about existing code below was grepped, not remembered.
Inference is marked as inference.

---

## 0. What I verified in the repo first

| Claim | Verified at |
|---|---|
| `save` is already a frozen change-journal entity kind | `playstead-server/lib/playstead/sync/entity_kind.ex` — `~w(device pairing catalogue job transfer save curation)a` |
| One kind may carry several inner shapes via a `type` discriminator (D-08's precedent) | `lib/playstead/sync/curation_payload.ex` — `type: "favorite" \| "collection" \| ... \| "recent"` |
| A published payload is built through one function with a `@frozen_keys` list | `lib/playstead/catalogue/payload.ex` |
| Journal entries are `entity_kind`/`entity_id`/`operation`/`payload :map`, seq-fenced by `pg_advisory_xact_lock`, written **inside the caller's transaction** | `lib/playstead/sync/{entry,change_journal}.ex` |
| Journal entries are **deleted** past a 90-day horizon | `lib/playstead/sync/compaction.ex` — `run/0` does `delete_all` on `inserted_at < cutoff` |
| Snapshot materializes per-domain branches inside one REPEATABLE READ transaction, filtered `inserted_at <= as_of_time`, and returns `catalogue:`, `job:`, `curation:` alongside the device page | `lib/playstead/sync/snapshot.ex` |
| Every mutation goes through `Idempotency.execute/4` in one `Ecto.Multi`; the fingerprint is over `{method, path, canonicalized body}` | `lib/playstead/idempotency.ex` |
| Streaming upload precedent: `PUT /api/v1/imports/uploads/:command_id` streams the body straight through `Blobs.put_stream/3`, never buffering | `lib/playstead_web/controllers/api/v1/imports_controller.ex` |
| Play sessions exist and are exactly `{id, user_id, asset_set_id, started_at, ended_at}` | `lib/playstead/curation/play_session.ex`, route `post "/api/v1/play-sessions"` |
| Error codes are a flat atom registry with `{status, title}` | `lib/playstead_web/error_codes.ex` |
| The Mac client already tolerates an unknown `entity_kind`/inner `type` as a valid-but-ignored entry | `playstead-mac/Playstead/Sync/ChangesClient.swift:75`, `JournalApplier.swift:86` |
| **No save code exists on either side** | `grep -ri save playstead-server/lib/playstead/` returns only the `entity_kind` registration and capability namespace |

Two consequences that shape everything below:

1. **Journal compaction deletes `save` entries after 90 days.** A save DAG that
   exists *only* as journal entries evaporates. The `save` kind therefore
   **must** get a snapshot materialization branch — this is not optional
   polish, it is the difference between a durable lineage and one with a
   90-day event horizon.
2. **`Idempotency.fingerprint/1` canonicalizes a parsed body.** It cannot
   fingerprint a streamed 32 KB body. The import controller works around this
   by fingerprinting over the declared digest + length headers. That fact
   forces the two-step protocol in §4 rather than being a stylistic choice.

---

## 1. JTBD framing

**Who / when / where:** a person who plays the same GBA game on their Mac,
sometimes offline, sometimes after a clean reinstall, occasionally on a second
Mac later. The moment that matters is *after* the divergence has already
happened: they open Playstead and something is not what they expect.

**What they are hiring this for:** "When my progress exists in two versions,
don't make me guess and don't decide for me. Show me enough to recognise which
one is mine, and keep the other one anyway."

**What they get back:** both versions, each labelled with a place (which Mac),
a time they can sanity-check, and what they were doing (which game session) —
and the guarantee that choosing one does not destroy the other.

**Domain nouns:** *save line* (the continuous save for one game on one slot),
*revision* (one immutable captured version of the bytes), *branch head* (a
revision nothing was played forward from), *diverged* (a line with more than
one branch head), *resolution* (a revision that supersedes the sides it did not
take).

**Domain verbs / events:** *captured*, *restored*, *diverged*, *resolved*,
*exported*.

**Consumer-shaped, not provider-shaped.** The user never sees the words
"parent", "digest", "DAG", "head", "fast-forward", "cursor", or "journal".
They see "this Mac, Tuesday evening, during your 40-minute session" versus
"your other Mac, last week". The one place backend guts *must* cross the wire
is the journal payload itself — the client has to reconstruct the DAG to render
"both of these came from the same point", and that cannot be derived from
anything less than an explicit parent pointer. That is a fundamental
constraint, and it stops at the API boundary: the payload carries parent
pointers, the UI never does.

---

## 2. Role lenses applied

- **Domain modeller.** `Playstead.Saves` is a new bounded context. It depends
  on `Blobs` (bytes), `Sync` (journal), `Idempotency` (receipts) — one-way, and
  never the reverse. `Blobs` stays format-free (P2 D-12): nothing in the store
  learns what SRAM is. `Saves` never reaches into `Curation`; it holds a
  nullable `play_session_id` and joins.
- **Offline-sync engineer.** Causality is expressed structurally (a parent
  pointer), not numerically (a counter). Idempotency is the client UUIDv7 +
  receipt already mandated by P1 D-20. Partition behaviour: an offline Mac
  accumulates a linear chain locally and uploads it in order; a partition
  cannot produce a wrong answer, only a delayed one. Convergence: after
  resolution the line has one leaf again, and every replica computes the same
  leaf set from the same edges with no tie-breaking rule at all.
- **Elixir/OTP/Ecto.** `Playstead.Saves.record_revision/3` runs inside
  `Idempotency.execute/4`'s `Ecto.Multi`; `ChangeJournal.append/4` is called in
  that same transaction (the module's own docstring requires it). Forward-only
  migrations. Published payload additive-only via a `@frozen_keys` list, tested.
  No GenServer holds lineage state — supervision is not durability.
- **Swift/macOS client.** The Mac keeps the same DAG in SQLite
  (`Persistence/LocalStore.swift` + `Migrations.swift`), writes revisions
  locally *first*, and posts through `Sync/Outbox.swift`. Local-first is
  load-bearing: a revision that only exists after a successful POST is a
  revision that a network outage loses.
- **Filesystem/durability.** Covered by area A. B's only requirement of A: the
  bytes handed to a revision are a consistent snapshot (copy-then-hash, and
  re-hash after copy), because the mmap-backed `.sav` can be written under us
  mid-read. A revision whose digest doesn't describe its own bytes poisons the
  whole model.
- **Security.** The payload carries no filesystem paths, no ROM title, no
  credentials. `blob_sha256` of a save is user content and must not appear in
  logs or CI evidence. Blob size is hard-capped per upload. Revision ids are
  client-generated UUIDv7 — which embeds a **device wall-clock millisecond**;
  see §6, it is another thing that must never be sorted on.
- **SRE.** One new signal worth an operator's attention: `diverged` lines
  outstanding. Not an alert; a count.
- **Performance.** 32 KB. A revision row is a few hundred bytes. Ten years of
  hourly captures is ~87k rows, ~35 MB of metadata. There is no scale problem
  here and no justification for building a distributed database.
- **Accessibility / microcopy / creative direction.** Area G's surface, not
  mine. B's only constraint on G: `status` is a *word* (`"diverged"`), never a
  colour, so WCAG 1.4.1 is satisfiable downstream.
- **Test engineer / red team.** §11 and §10.

---

## 3. Prior art (researched, with the footgun for each)

| System | What to copy | The documented footgun to avoid |
|---|---|---|
| **git** | The object model: immutable objects, an explicit parent pointer per commit, branch = a leaf, and *provenance is free* because history is structure, not annotation. Merge is a **separate** concern layered on top — the DAG is valid and useful with no merge at all. | Its UX. Rebase/force-push/detached HEAD are how git loses data, and every one of them is an operation that *rewrites* history. Nothing in Phase 4 may rewrite a recorded revision. |
| **Fossil** | Append-only by design — nothing is ever removed, and "shunning" is a deliberate, loud, rare exception. Matches PROJECT.md priority #1 exactly. | Its all-in-one scope. We want the storage discipline, not the ecosystem. |
| **Datomic** | Facts are immutable and time is a first-class attribute; you never destroy, you assert a new fact. This is precisely "resolution supersedes, never deletes". | Excision is painful and rare by design. Our area D pruning must therefore prune *bytes*, not *facts*. |
| **CouchDB / PouchDB revision trees + `_conflicts`** — the closest analogue to this exact problem. Docs: <https://docs.couchdb.org/en/stable/replication/conflicts.html>, <https://pouchdb.com/guides/conflicts.html> | The core shape is right and we should copy it: every document is a tree of revisions, both sides of a conflict are **retained**, and `_conflicts` enumerates the losing leaves. Conflict is a normal state, not an error. | **The deterministic winner rule.** CouchDB picks a winner by longest revision history, tie-broken by ASCII sort of `_rev`. The docs are explicit that this "does not mean the winner is the latest or the best edit" and that applications "must always resolve conflicts". Practitioners also note there is no convenient HTTP API to fetch all conflicting revisions or supersede N of them, so everyone hand-rolls it. **We copy the tree and reject the automatic winner** — a silently-chosen winner is exactly the silent last-write-wins SAVE-04 forbids. And we ship the "fetch all sides / supersede N" operation as a first-class endpoint, because that is the part CouchDB left to userland and everyone got wrong. |
| **Riak siblings + dotted version vectors** | Sibling *retention* is right; DVVs solve false-concurrency in the sibling-explosion case honestly. | Sibling explosion is a real operational failure mode, and DVV bookkeeping cost scales with actor count. We have 1–3 actors and an explicit parent pointer, which gives exact causality for free. Vector clocks buy us nothing a parent pointer doesn't already give, and cost per-device state that must be garbage-collected when a device is revoked. |
| **CRDTs** | Honest assessment: they do not help. A 32 KB opaque SRAM blob has no exploitable algebra. The only CRDTs that apply to an opaque register are (a) the **LWW-register**, which is literally the last-write-wins SAVE-04 prohibits, and (b) the **MV-register**, whose semantics are "keep all concurrent values" — i.e. exactly the sibling set we already get, but purchased with version-vector machinery and with the property that reading-then-writing *collapses* the siblings, discarding provenance. A CRDT here would be strictly more machinery for strictly less history. |
| **syncthing conflict copies** (`file.sync-conflict-DATE-DEVICE.ext`) | Never destroy the other side; encode device + time into the surviving artifact so it is self-describing offline. | The user is left with two files and no tool. Conflict resolution is "figure it out in Finder". Also: the filename encodes a **device-local timestamp** nobody validated. |
| **Dropbox "conflicted copy"** | Same virtue: silent loss is never acceptable. | Same vice: the artifact is the whole UX, and users routinely end up with `file (Jon's conflicted copy) (2)`. Naming is not resolution. |
| **iCloud `NSFileVersion`** | Per-file version list with an originator identity, and a proper API (`unresolvedConflictVersionsOfItem`, `isResolved`) — the closest first-party model to what we want. | Versions are opaque, storage-managed, and can be reclaimed under pressure. Ours must be ours. |
| **Steam Cloud sync conflict dialog** — the canonical example of both good and bad | The good: it *does* stop and ask, showing two columns with timestamp and file size, and Valve keeps a 30-day rolling backup you can recover through support. | The bad, and it is severe: the dialog's two buttons are "upload local" / "download cloud", and **choosing wrong overwrites the other side irrecoverably from the user's point of view**. Community write-ups call the wrong click "the single most common way players permanently lose progress", and the recommended remedy is *file a support ticket with a screenshot*. Both of Valve's decision aids — modified time and file size — are worthless for our case: the clock may be wrong, and every GBA SRAM file is exactly 32768 bytes, so the size column is a constant. **Design consequence: our resolution must be non-destructive by construction, and must not lean on time or size as the discriminator.** <https://savegamelocation.com/blog/steam-cloud-not-syncing-fix-save-conflicts/> |
| **Nintendo Switch Online Save Data Cloud** | Honest exclusion: NSO publishes a list of titles it *won't* cloud-sync rather than pretending universality — the same "explicit matrices, never aspirational universality" constraint PROJECT.md states. | Only one backup per title per account, download **overwrites and cannot be undone**, and the support page's own guidance is "take care not to unintentionally download to the wrong console". No history, no conflict concept at all. This is the anti-model. <https://en-americas-support.nintendo.com/app/answers/detail/a_id/41267/> |
| **RetroArch Cloud Sync** — the nearest-neighbour product | Its detection rule is exactly right and worth copying wholesale: it keeps `manifest.local` (what was last synced) and compares against both the server file and the current local file. A conflict is *server ≠ last-synced* **and** *local ≠ last-synced*. On conflict it changes **nothing** — local unchanged, server unchanged, file excluded from sync, conflict logged. That is a base-pointer comparison in all but name, and it fails safe. | Two footguns. (1) **Resolution is by hand-editing `manifest.local` to forge a hash**, or deleting/renaming the local file. That is not a user-facing resolution; it is a workaround. (2) The surrounding machinery has a track record of eating saves anyway — see libretro/RetroArch#16663 ("tvOS iOS cloud sync breaking n64 saves") and #17731/#17474 (crashes during sync). **Detecting the conflict correctly and then offering no humane way out is a failure, not a success.** Docs: <https://docs.libretro.com/guides/retroarch-cloud-sync/> |
| **Ludusavi** | Backups are explicit, versioned, and manifest-described; the tool never silently reconciles. Its "what would this do" preview is a good model for area G. | It is a backup tool, not a continuity tool — it has no concept of two devices diverging live, so it teaches us nothing about detection. |
| **1Password item history / Time Machine local snapshots / borg / restic / Litestream** | All share one shape: an append-only chain of immutable versions where restore is *additive* (restoring makes a new current version, it does not rewind). We adopt that literally: **restore-then-play produces a child of the restored revision.** | borg/restic prune by *policy*, which is where a naive prune would break lineage. See §9. |

Revalidation notes: the RetroArch and CouchDB conflict semantics are the two
mutable ones — RetroArch's cloud sync is young and its behaviour has changed
across releases, and CouchDB's winner algorithm is documented as an
implementation detail applications must not depend on. Neither is load-bearing
for us in a way a change would break: we copy the *shape* and reject the
automatic winner.

---

## 4. The options table

| # | Option | Concrete sketch | Pros | Cons | Failure modes | Reversibility | Effort |
|---|---|---|---|---|---|---|---|
| **B-1** | **Parent-pointer immutable revision DAG per save line** (recommended) | `save_revisions(id uuidv7 PK, save_line_id, parent_revision_id NULL, blob_sha256, ...)`. Branch head = a revision with no children. Diverged = >1 branch head. | Exact causality with zero bookkeeping; provenance is structural and free; survives a device the server never saw; restore-then-play is expressible; resolution is a normal revision with `supersedes`; no tie-break rule to get wrong. | One extra nullable column and a head check. "Isn't this git?" optics. | A parent pointing at a revision the server hasn't ingested yet (ordering, retryable). Branch accumulation from a buggy client. | **Cheap to extend** (fields are additive), **costly to abandon** — the parent column is in a published payload. | Small: 2 tables, 1 payload module, 2 endpoints, 1 snapshot branch. |
| **B-2** | Per-device Lamport / vector clocks | `save_revisions(..., version_vector jsonb)`; concurrency = neither vector dominates. | Detects concurrency without needing the parent to be known. Textbook. | Requires per-device counter state that must be GC'd on device revoke; **cannot express "this Mac restored R and played forward"** — the device never observed R's ancestors, so its vector is a lie or must be seeded from R, at which point R's identity is the real primitive anyway. Answers "were these concurrent?" but not "what did this come from?", and SAVE-04 needs the second. | Vector skew after a device is revoked and re-paired; false concurrency without dotted vectors. | Costly — vectors would be in the payload. | Medium-high. |
| **B-3** | Server fast-forward-only, **409 on non-FF**, client materializes a branch locally | `POST` carries `expected_head`; mismatch → `409 save_not_fast_forward`; the client is then responsible for representing the branch. | Server state is always a clean linear chain. Classic optimistic concurrency, easy to reason about. | **The divergent bytes' only durable home becomes the client.** If the client is buggy, quits, or the user reinstalls before resolving, the losing side is gone — a data-safety regression against priority #1. Also makes the client's correctness load-bearing for not losing data, which is the thing we control least. | Client crashes holding the only copy of one side. Capability skew: an older client that doesn't understand the 409 retries forever or gives up. | Costly to reverse. | Small, but the cost lands in the wrong place. |
| **B-4** | Accept everything, mark the slot conflicted, **no parent pointer** ("upload my current save") | `POST /saves/{line}` with bytes + device + time; server compares against its current and flags. | Trivially simple client. | This is the P3 D-09 footgun in save clothing: a request that states no base is a whole-truth claim, and the server cannot distinguish "played forward from what you have" from "overwrote it blindly". It also cannot tell a genuine conflict from a slow retry. Detection degenerates to timestamps — the Steam column that is a lie and the file-size column that is a constant. | Silent LWW. Exactly the failure SAVE-04 names. | — | Small. **Rejected.** |
| **B-5** | Digest chain (`parent_sha256` instead of `parent_revision_id`) | Base identified by the bytes it came from. | Self-verifying; works even if the parent revision row is unknown. | Two revisions with identical bytes (very common — GBA SRAM is mostly zeros plus a small delta, and an idle session produces byte-identical output) become **indistinguishable parents**. Ambiguous lineage. | Mis-parenting on byte collision. | — | Small. **Rejected as the primitive** — but kept as a *secondary* field (`base_sha256`) because it catches out-of-band edits. |
| **B-6** | Hybrid: parent pointer (B-1) + optional `expected_head` optimistic hint | B-1, plus the client may assert `expected_head`; server 409s only if the client *asked* to be strict. | Lets a future stricter client opt in without a protocol change. | An unused knob today. | — | Cheap — additive. | Trivial on top of B-1. |

**Chosen: B-1 + B-6, with acceptance semantics rather than rejection (see §5).**

### Is a DAG overkill for an unmergeable blob?

The honest answer: a DAG is *exactly right*, and it is right for the opposite
of the usual reason. Because the payload is unmergeable, the DAG can never be
asked to do the hard thing (three-way merge), so we pay none of git's cost. What
remains is the cheap thing — a pointer — and the cheap thing is the entire
mechanism SAVE-04 needs: "these two came from the same place" is one equality
check on one column. Unmergeability makes the DAG *cheaper*, not less
justified. What we decline to build, explicitly: merge, rebase, cherry-pick,
named branches, remotes, and any automatic winner.

---

## 5. The recommendation, in detail

### 5.1 Identity: the save line

```elixir
# save_lines
id                :binary_id   # UUIDv7, client-generated (P1 D-20 natural key)
user_id           :id
asset_set_id      :binary_id   # current binding to the game
content_key       :string      # sha256 of the primary ROM member AT LINE CREATION
system            :string      # "gba"
save_kind         :string      # "battery"   <- SEED-019 discriminator, day one
slot              :string      # "0"         <- multi-slot door, day one
save_format       :string      # "raw_sram"
status            :string      # "linear" | "diverged"
head_revision_id  :binary_id   # meaningful ONLY when status == "linear"
```

Identity tuple: **`(user_id, content_key, save_kind, slot)`**, unique.

- `save_kind` from day one is the SEED-019 seam. Phase 4 accepts `"battery"` and
  nothing else (`save_line_kind_unsupported` otherwise). `"state"`,
  `"memory_card"`, `"sram_directory"` are reserved vocabulary, not implemented.
  Adding a value later is an additive capability bump (P1 D-19), not a schema
  change. Collapsing system saves and save states into one undiscriminated
  "save" is the mistake SEED-019 exists to prevent, and it would be
  unrecoverable once published.
- `slot` from day one, default `"0"`. GBA has one; memory cards have many.
  Adding a slot dimension *later* is a one-way payload break; adding it now
  costs one always-`"0"` string.
- **`content_key`, not `asset_set_id`, is the identity component.** Re-importing
  the same ROM produces a new asset set row; keying the line on `asset_set_id`
  would orphan every save on re-import. `asset_set_id` is retained as the
  current binding (and re-bound on re-import), but identity follows the bytes.
  *This overlaps area C* — flagged in §12.

### 5.2 The revision

```elixir
# save_revisions  -- IMMUTABLE. No UPDATE path exists except blob_pruned_at.
id                      :binary_id     # UUIDv7, CLIENT-generated (P1 D-20)
save_line_id            :binary_id
user_id                 :id

# --- lineage ---
parent_revision_id      :binary_id     # NULL only for a root
supersedes_revision_ids {:array, :binary_id}  # default []; resolution only
base_sha256             :string        # digest of the bytes present when play began
base_matched            :boolean       # base_sha256 == parent's blob_sha256

# --- content ---
blob_sha256             :string        # the CAS key; content fingerprint (SEED-001)
size_bytes              :integer
blob_pruned_at          :utc_datetime  # NULL; area D releases bytes, never the row

# --- provenance (SEED-001) ---
origin_device_id        :binary_id     # known
capture_method          :string        # "periodic_flush"|"exit_scan"|"import"|"restore"|"resolution"
adapter_id              :string        # "mgba-standalone"
adapter_version         :string        # "0.10.5"
save_format             :string        # "raw_sram"
format_confidence       :string        # "known" | "inferred"     <- SEED-001 known-vs-inferred

# --- time (see §6) ---
recorded_at             :utc_datetime_usec  # SERVER stamped. The only orderable time.
device_captured_at      :utc_datetime_usec  # device wall clock. Display only.
device_reported_now     :utc_datetime_usec  # device's clock at POST time
device_clock_offset_ms  :integer            # server_received_at - device_reported_now
device_monotonic_ms     :bigint             # device uptime clock at capture; cannot go backwards

# --- play context ---
play_session_id         :binary_id     # nullable FK -> curation_play_sessions
```

Everything else is joined at read time. `play_session_id` is the **only**
denormalization of play context — the game, start, and end are already on
`curation_play_sessions` (verified) and duplicating them would create two
truths. Nullable because a revision may come from an import, a restore, or a
session whose POST hasn't drained from the outbox yet; area G must render "no
recorded session" as a first-class state, not an error.

### 5.3 What "same base" means, concretely

**The base is `parent_revision_id` — an explicit pointer to a revision id.**
Not a per-slot sequence (a sequence assumes a single assigner, which is the
thing that doesn't exist offline) and not a digest chain (byte-identical saves
are common and would make the parent ambiguous — B-5).

Three cases the brief asks about, answered:

1. **First revision for a game.** `parent_revision_id = NULL`. Base is "the
   empty state". A root is only a *fast-forward* if the line has no revisions
   at all. A second root arriving at a line that already has a head is a
   genuine divergence and is recorded as one — two devices that each started
   the game fresh really do have two incomparable saves, and pretending
   otherwise is exactly the silent loss we're avoiding. (Area G should present
   this gently; it's the least alarming kind of divergence. Flagged in §12.)
2. **Clean Mac restores revision R and plays.** The new revision's parent is
   **R**, even though this device never saw R's ancestors. This is correct and
   it is the single strongest argument for a parent pointer over any counter
   scheme: lineage is a property of *where the bytes came from*, not of what
   the device happened to observe. A Lamport or vector clock would have to
   either invent history the device never had or seed itself from R — at which
   point R's identity is doing the work anyway. Record
   `capture_method: "restore"` on the materialization and
   `base_matched: true` on the child.
3. **Bytes that don't match the claimed parent** (a save editor, a manual file
   copy, a torn read). `base_sha256 != parent.blob_sha256` →
   `base_matched: false`. This is **recorded, not rejected**: the user may
   legitimately have edited their save, and refusing it would push them back to
   a filesystem workaround, which is the RetroArch footgun. It is a fact area G
   can surface ("these bytes didn't come from the version we recorded").

### 5.4 Detection: where, and what happens

**Server-side detection, client-side branch materialization is *not* needed
because nothing is rejected.** The rule:

| Condition | Result | Head | Line status |
|---|---|---|---|
| `parent == line.head_revision_id` and line is `linear` | `201`, revision recorded | advances | `linear` |
| `parent == NULL` and line has no revisions | `201`, revision recorded | set | `linear` |
| Child bytes are byte-identical to the parent's, and parent is head | `200`, **no revision created**, body points at the existing head | unchanged | unchanged |
| `parent` is a known revision that is not the head (incl. a second root) | **`201` with `"branch": true`**, revision recorded, `conflicts_with: [<other branch heads>]` | **does not move** | `diverged` |
| line is already `diverged` | `201`, revision recorded, extends whichever branch it names | n/a | `diverged` |
| `parent` is a revision id the server has never seen | **`409 save_parent_unknown` + `Retry-After: 1`** | unchanged | unchanged |
| more than 32 open branch heads on one line | **`422 save_branch_limit_exceeded`** | unchanged | `diverged` |
| revision id already exists with different content | **`409 save_revision_immutable`** | unchanged | unchanged |

**Why accept-and-branch, not 409-and-let-the-client-branch (B-3).**

The brief asks which keeps the client honest offline. The honest-making
mechanism is **the parent pointer, not the rejection.** A revision that names
its base is structurally incapable of the P3 D-09 failure — the server can
always tell that two revisions share a parent, so nothing can be silently
dropped. Once the pointer exists, rejecting adds no safety and subtracts a
lot: under B-3 the losing side's only durable copy lives on a client, and
PROJECT.md's #1 priority is data safety on the server. A 409 that means "your
work is not welcome here yet" is precisely the wrong answer to "I have work you
don't have".

Capability skew also breaks B-3's way. Under B-3, an older client that doesn't
understand `save_not_fast_forward` either retries forever or gives up holding
the only copy. Under accept-and-branch, an older client that ignores
`"branch": true` still got a `201`, still has its bytes durably stored, and the
worst case is a stale local view — degrade with an explained remedy, never a
hard break (P1 D-19).

The one rejection I keep, `save_parent_unknown`, is deliberately **not** a
data-safety decision: it is a pure ordering error, always caused by the client's
own outbox draining out of order (a device can only know a revision id the
server has, or one it made itself and has queued ahead). It is retryable and
self-heals. Cross-device it is unreachable by construction — device B can only
learn A's revision id via the server, which already has it.

`expected_head` (B-6) is accepted as an *optional* strictness hint for a future
client that wants a hard 409; unused in Phase 4.

### 5.5 Head and branch heads

`head_revision_id` is a cached convenience valid **only** when
`status == "linear"`. The truth is derived: **a branch head is a revision with
no children**, and `diverged` means more than one. Derived, so it cannot drift;
cached for the linear case, so the launch path (area F) has an O(1) answer.

**There is no winner-selection rule.** This is the deliberate rejection of
CouchDB's deterministic winner. There is no "longest history", no "highest
sort order", no "newest timestamp". A diverged line has no head until a person
resolves it.

### 5.6 Resolution, as a data operation

A resolution is a normal revision:

- `parent_revision_id` = the chosen side (bytes provenance — this is why parent
  stays a scalar rather than becoming a multi-parent array; the bytes came from
  exactly one place and the model should say so),
- `supersedes_revision_ids` = the other branch heads,
- `capture_method: "resolution"`,
- `blob_sha256` = the chosen side's digest (same CAS object; no copy).

Effects: the superseded heads gain a child, so they stop being heads; the line
returns to `linear`; the losing bytes are **still there**, still exportable,
still restorable. "Resolve" never deletes. This is git's merge commit minus
the merge, and it is what makes our answer strictly better than Steam's
irreversible two-button dialog.

---

## 6. Clock trust

**Rule: exactly one clock is allowed to order anything, and it is the server's.**

- `recorded_at` — server-stamped inside the insert transaction. Orders
  revisions; used for the snapshot's `inserted_at <= as_of_time` filter
  (matching the existing `Snapshot` pattern); used for display as *"saved to
  Playstead"*.
- `device_captured_at` — the Mac's wall clock at capture. **Never sorted on,
  never compared across devices, never used to pick a head or a winner.**
  Stored because SAVE-04 requires showing the user a time and because "when I
  was actually playing" is the time a person can recognise — the server's
  receipt time can be a week later after an offline stretch, which is exactly
  the case that makes a naive product show the wrong thing.
- `device_reported_now` + `device_clock_offset_ms` — the device sends its clock
  reading *at POST time*; the server computes
  `server_received_at - device_reported_now`. This separates **clock error**
  from **queue delay**, which a single skew number conflates. A week-old
  outbox entry from a correct clock yields offset ≈ 0; a drifted clock yields a
  large offset regardless of queue age. Two cheap fields, and they are what let
  area G say "this Mac's clock was 3 hours fast" instead of showing a lie
  confidently.
- `device_monotonic_ms` — the device's monotonic uptime at capture. Cannot go
  backwards, so two revisions from the *same* device are correctly orderable
  even across a wall-clock jump. One bigint. Ordering across devices remains
  the DAG's job.

**How we present a time we don't trust (constraint on area G, not a UX
decision):** the primary time is the device capture time, because it is the one
the person can recognise; it is attributed ("this Mac reported") and it carries
a divergence annotation when `|device_clock_offset_ms|` exceeds a threshold
(120 s is a reasonable start). The server time is always available as the
secondary, and it is the one any sorted list is actually sorted by. Never show
a bare unattributed timestamp — that is Steam's dialog, and its own guidance
concedes the timestamp "is not enough if the computer clock was wrong".

**Landmine:** UUIDv7 revision ids embed a device-supplied millisecond
timestamp. Sorting revision ids therefore sorts by an untrusted clock while
looking like sorting by an id. Call this out in the schema docstring and pin it
with test 6 (§11).

---

## 7. Protocol shape

The `save` entity kind is frozen and registered; there is **no new sync path**.
Two endpoints, both following the existing shapes exactly.

### 7.1 `PUT /api/v1/saves/uploads/:command_id` — the bytes

A direct sibling of `ImportsController.create/2`. Streams the body through
`Blobs.put_stream/3`, never buffering. Requires `Content-Length` and
`Repr-Digest: sha-256=:…:` (the idempotency fingerprint is over those headers,
which is precisely why this cannot be one endpoint with the metadata —
`Idempotency.fingerprint/1` canonicalizes a *parsed* body and cannot see a
stream). Hard size cap (16 MiB in Phase 4; GBA is 32 KB, memory cards are up to
8 MB). Creates a **pending, user-owned blob reference with a TTL** so an
orphaned upload is reapable and cannot be used to fill the disk.

Returns `{sha256, size_bytes, status: "stored" | "existing"}`. Because the
store already returns `:existing` for known content, a retry after a network
failure costs zero bytes, and an unchanged save short-circuits before the
metadata call.

*Rejected alternative:* reusing `PUT /api/v1/imports/uploads/:command_id`. That
handler creates a source file + asset set + import receipt — it means "a game
arrived", and a save is not a game. Same streaming mechanics, different
context; `Blobs` stays format-free either way (P2 D-12).

*Rejected alternative:* a generic `PUT /api/v1/blobs/uploads/:id`. Every other
upload path in this codebase binds a blob to a domain row in the same
transaction; a generic one makes unreferenced blobs a first-class possibility.

### 7.2 `POST /api/v1/saves/revisions` — the revision

Body (this is the **frozen, additive-only published contract**, P2 D-23):

```jsonc
{
  "id":                     "<uuidv7>",        // client natural key, P1 D-20
  "save_line": {
    "id":                   "<uuidv7>",
    "content_key":          "<sha256>",
    "asset_set_id":         "<uuid>",
    "system":               "gba",
    "save_kind":            "battery",         // SEED-019 discriminator
    "slot":                 "0",
    "save_format":          "raw_sram"
  },
  "parent_revision_id":     "<uuidv7>|null",
  "supersedes_revision_ids": [],
  "base_sha256":            "<sha256>",
  "blob_sha256":            "<sha256>",
  "size_bytes":             32768,
  "capture_method":         "periodic_flush",
  "adapter_id":             "mgba-standalone",
  "adapter_version":        "0.10.5",
  "format_confidence":      "known",
  "device_captured_at":     "2026-09-03T18:22:41.113Z",
  "device_reported_now":    "2026-09-03T18:22:43.907Z",
  "device_monotonic_ms":    418322,
  "play_session_id":        "<uuid>|null",
  "expected_head":          null                // B-6, optional strictness
}
```

Headers: `Idempotency-Key` (P1 D-20, enforced by the existing plug).

Handler: mirrors `PlaySessionsController.create/2` line for line —
`Idempotency.execute(device.id, key, fingerprint, effect_fun)`, with
`effect_fun` calling `Playstead.Saves.record_revision/3`, which inside the
ambient transaction (a) upserts the line, (b) adopts the pending blob, (c)
inserts the immutable revision, (d) recomputes head/status, (e) calls
`ChangeJournal.append/4` twice — once for the line, once for the revision.

Response `201`:

```jsonc
{
  "revision_id": "...", "save_line_id": "...",
  "recorded_at": "...",                 // server truth
  "line_status": "linear" | "diverged",
  "head_revision_id": "...|null",
  "branch": false,
  "conflicts_with": [],                 // other branch head ids when branch: true
  "base_matched": true
}
```

### 7.3 The journal payload

New module `Playstead.Sync.SavePayload`, built exactly like
`Playstead.Sync.CurationPayload` (D-08 template) and
`Playstead.Catalogue.Payload` (a `@frozen_keys` list plus a test asserting no
accidental additions). One entity kind (`"save"`), two inner shapes
discriminated by `type`:

- `type: "save_line"` — `entity_id` = the line id. Carries identity, status,
  `head_revision_id`, `branch_head_ids`.
- `type: "save_revision"` — `entity_id` = the revision id. Carries lineage,
  digest, provenance, both times, `play_session_id`.

Never in the payload: server filesystem paths, ROM titles, any other user's
data. Parent pointers *are* in the payload — the client must reconstruct the
DAG and cannot derive it from anything weaker. The Mac already treats unknown
inner `type` values as valid-but-ignored (`ChangesClient.swift:75`), so adding
a third inner type later is non-breaking.

### 7.4 The snapshot branch

`Snapshot.read/1` gains `save: fetch_saves(user_id, as_of_time)` alongside the
existing `catalogue:`, `job:`, `curation:` keys. **This is mandatory, not
optional:** `Compaction.run/0` deletes journal entries older than 90 days, so a
lineage that lives only in the journal has a 90-day event horizon. A client
that resyncs after a 410 must still reconstruct the full DAG.

Bounded, because a line can accumulate thousands of revisions: the snapshot
carries every line, **every branch head**, and the most recent N (50) ancestors
of each head. Deep history is a separate paginated read,
`GET /api/v1/saves/lines/:id/revisions`. Rationale: the client's *invariants*
(am I diverged? what can I launch from?) need heads; deep history is browsing.
Flagged as a collision with area D in §12.

### 7.5 Error codes to register (additive to `PlaysteadWeb.ErrorCodes`)

```elixir
save_parent_unknown:          {409, "Save Parent Unknown"},        # retryable, Retry-After
save_revision_immutable:      {409, "Save Revision Immutable"},
save_branch_limit_exceeded:   {422, "Save Branch Limit Exceeded"},
save_blob_missing:            {422, "Save Blob Missing"},
save_digest_mismatch:         {422, "Save Digest Mismatch"},
save_blob_too_large:          {413, "Save Blob Too Large"},
save_line_kind_unsupported:   {422, "Save Kind Unsupported"},      # capability skew, P1 D-19
save_not_fast_forward:        {409, "Save Not Fast Forward"}       # reserved for expected_head (B-6) only
```

Reuse `storage_insufficient` (507) and `validation_failed` (422) unchanged.

---

## 8. Is this over-engineering for a one-device product?

The measured delta between "no lineage at all" and this model is: **one nullable
column (`parent_revision_id`), one array column, one derived boolean, and one
equality check in the handler.** Everything else — immutable revisions, content
digests, device and adapter provenance — is required anyway by SAVE-01
(capture), SAVE-02 (surfacing), SAVE-03 (restore), and PORT-01 (export). The
conflict machinery is roughly one column and one `if`. It is not a subsystem.

And single-device does not mean divergence-free. Four one-Mac paths produce it
today:

1. Clean reinstall + restore, while the pre-reinstall outbox had undrained
   revisions.
2. Restoring an older revision, playing forward, then restoring a newer one —
   two children of different bases on one machine.
3. A user editing the `.sav` out of band with a save editor, then playing.
4. A crashed capture racing a manual import of the same game's save.

Add the 24-second measured loss window (03-SPIKE-REPORT) and an exit signal that
is indistinguishable from a crash, and the shape of the failure "two versions
exist and neither is obviously wrong" is a *routine* Phase 4 event, not a
two-Mac exotic.

Against PROJECT.md: priority #1 is data safety, #2 is save continuity, and the
constitution's explicit constraint is "never silently discard save conflicts".
The roadmap makes it success criterion 5. A simpler model that genuinely
satisfies SAVE-04 does exist — "every capture is an immutable revision, keep
them all, and mark the line diverged when two revisions claim the same base" —
and that model **is this one**. Anything simpler than that either drops a side
or decides for the user.

Verdict: not over-engineering. The expensive part of SAVE-04 is area G's
resolution surface, not B's data model.

---

## 9. Retention collision with area D — read this, area D

An immutable DAG constrains pruning, and the constraint is precise:

> **Prune bytes. Never prune nodes.**

- A revision row is a few hundred bytes; its blob is 32 KB. Releasing the blob
  recovers ~99% of the storage. Keeping every node forever costs ~35 MB per
  decade of hourly captures on a personal server. There is no reason to delete
  a node, ever.
- Pruning a blob sets `blob_pruned_at` and re-emits an **upsert** with
  `bytes_available: false`. The lineage stays intact, export (area H) and area
  G can still say "this version existed, on this Mac, at this time, but its
  bytes were released".
- Deleting a revision *row* is only legal via a `ChangeJournal.tombstone/3`.
  A row deleted without a tombstone silently breaks cursor convergence: a
  client at an older cursor keeps a revision the server dropped, forever, with
  no event to correct it. **Flagging loudly: if area D proposes row-level
  pruning without tombstones, it breaks the `save` kind's convergence
  silently.** Same class of bug as the cursor-gap lost update D-21 already
  rules out.
- **Never prunable bytes:** any current branch head while `status = "diverged"`;
  any revision named in an unresolved conflict; the current head of a linear
  line; anything referenced by an in-flight export; the immediate parent of any
  unpruned revision (so `base_matched` stays checkable).
- **CAS refcounting:** two branches with identical bytes share one blob (this
  is common — SRAM is mostly zeros). Area D must refcount by revision, not
  delete on first orphan. P2 D-12's `delete/1` is defined only for uncommitted
  temporaries, which already points the right way.
- **Pending-upload orphans:** §7.1's TTL on pending blobs is area D's to
  actually reap.

---

## 10. Adversarial pass on my own recommendation

**"You accept non-fast-forward writes, so a buggy or hostile client can spam
branches until the line is unusable."** Real. Three guards: byte-identical
children of the head are collapsed and create no revision (kills the
periodic-flush spam vector at the source); the idempotency receipt + client
UUIDv7 makes a retried POST a replay, not a new branch; and a hard cap of 32
open branch heads returns `422 save_branch_limit_exceeded` — a loud failure,
never silent loss. Residual: a determined client can still make 32 branches.
Accepted; the user sees a loud error and no data is lost.

**"You store a device clock you don't trust, and someone will eventually sort
by it."** Very likely, and the UUIDv7 id makes it worse because sorting *ids*
looks innocent. Mitigation is a test, not a convention: test 6 (§11) asserts
head selection and branch-head derivation are invariant under adversarial
device times (a week in the past, a year in the future, non-monotonic).

**"`content_key` from the primary ROM member is fragile for multi-file sets."**
True for systems with multi-file content. GBA is single-file, so Phase 4 is
safe, but the rule for choosing the primary member is a decision area C already
owns. Flagged, not resolved here.

**"Two roots is a normal first-run situation and you call it a conflict."**
Correct on both counts. It *is* a genuine divergence — two incomparable saves —
and it also should not read as alarming. Constraint on area G, not a reason to
weaken the model: a divergence where one side has zero play sessions and
near-empty bytes deserves gentler language, not a different data shape.

**"You've built git for a 32 KB file."** The loudest thing a hostile reviewer
says, and the answer is §8's arithmetic: one nullable column. The alternative
that *avoids* the column is B-4, which is precisely the RetroArch/Steam
failure mode the requirement was written to prevent.

**"Immutability means you can never fix a mistake."** Correct by design, and
the escape hatch is additive: a wrong revision is superseded, not edited. The
only mutable field on a revision is `blob_pruned_at`.

**"The two-step upload leaves a window where bytes exist with no revision."**
Yes. That window fails *safe* — orphan bytes cost storage, not data. The
reverse ordering (revision first, bytes later) would create revisions pointing
at nothing, which fails unsafe.

**Residual risks I am not fixing, recorded honestly:**
1. No test exercises two *physically distinct* Macs with independent clocks and
   independent outboxes (§11). The two-credential ExUnit test is the standing
   proxy.
2. A client that never posts `play_session_id` produces revisions with no play
   context, satisfying SAVE-04's letter and not its spirit. Area A owns
   ensuring the linkage actually happens.
3. Branch-head derivation is O(children) per line; unindexed it degrades on a
   line with thousands of revisions. Needs an index on
   `(save_line_id, parent_revision_id)`. Noted, not a design risk.

---

## 11. How this is proven (03.5 D-03: named, discovered, executed, non-skipped, passed)

**Server, ExUnit** — two paired device credentials against one server give
complete coverage of the server contract without any hardware:

1. `Playstead.Saves.LineageTest` — *"records two revisions naming the same
   parent as separate branch heads and marks the line diverged"* (the
   two-device divergent offline simulation).
2. `Playstead.Saves.LineageTest` — *"does not advance head_revision_id on a
   non-fast-forward revision"*.
3. `Playstead.Saves.LineageTest` — *"a second root on a line with an existing
   head is recorded as a branch, not a replacement"*.
4. `PlaysteadWeb.Api.V1.SaveRevisionsControllerTest` — *"returns 409
   save_parent_unknown with Retry-After for an unseen parent"*; *"replays an
   identical POST from the receipt without creating a second revision"*
   (idempotent replay, P1 D-20); *"returns 409 save_revision_immutable when an
   existing revision id is reposted with different fields"*.
5. `Playstead.Sync.SavePayloadTest` — frozen-key assertion, mirroring the
   existing catalogue payload test, so no call site can add a field by accident.
6. `Playstead.Saves.ClockTrustTest` — *"head selection and branch-head
   derivation are invariant under a device_captured_at one year in the future,
   one week in the past, and non-monotonic across two revisions"*.
7. `Playstead.Sync.SaveConvergenceTest` — snapshot-then-`/changes` and
   changes-only reconstruct byte-identical DAGs including a diverged line;
   **and** after `Compaction.run/0` past the horizon, the snapshot alone still
   yields every branch head. (This is the test that would have caught the
   90-day event horizon.)
8. `Playstead.Saves.CollapseTest` — *"a byte-identical child of the head returns
   200 with the existing head and creates no revision"*.
9. `Playstead.Saves.ResolutionTest` — *"a resolution revision supersedes the
   other branch heads, returns the line to linear, and deletes nothing"*.

**Mac, XCTest:**

10. `SaveOutboxTests` — *"orders revision POSTs per line so a parent always
    precedes its child"*; *"re-queues a 409 save_parent_unknown with backoff
    rather than dropping the revision"*.
11. `JournalApplierSaveTests` — *"applies save_line and save_revision entries
    into the local DAG"*; *"ignores an unknown inner type without failing the
    batch"* (the forward-compat property `ChangesClient.swift` already has).
12. `SaveLineageStoreTests` — *"derives two branch heads from a locally stored
    divergence"*.

**What genuinely needs the two-Mac path that does not exist:** proof that two
real macOS processes, with independent wall clocks and independent outbox
drains, produce a divergence the user actually sees end to end. Tests 1 and 10
are proxies, not that proof. Per 03.5 D-09, the client-side stand-in is a
deterministic, compile-gated test profile that injects a second device's
revision through the **real** `/changes` applier — never raw SQL. Record the
gap as a known verification limitation rather than claiming coverage; that is
exactly the fail-open-gate pattern 03.5 was created to stop.

---

## 12. Coherence notes — what I assume, where I collide

| Area | Assumption / collision |
|---|---|
| **A — capture trigger** | A owns `capture_method`'s value set and *when* a revision is minted. **Collision:** A must not mint a revision per 24 s flush tick — that is the branch-spam vector. §5.4's byte-identical collapse is the shared guard and A should rely on it. B also requires that A hands over a *consistent* snapshot (copy, then hash the copy): a digest that doesn't describe its own bytes poisons the whole model. |
| **C — restore gate** | **Collision, loud:** B keys save-line identity on `content_key` (the ROM's sha256), so C's rule for picking the primary content member is B's identity rule too. B supplies C with `system`, `save_kind`, `save_format`, `size_bytes`, `adapter_id/version`, `format_confidence`. B's only claim on C: a restore-then-play produces a child of the restored revision, with `capture_method: "restore"` on the materialization. |
| **D — retention** | **Collision, loud:** §9. Prune bytes not nodes; row deletion only via tombstone; refcount shared CAS blobs; reap pending-upload orphans; never prune a diverged branch head. Also: the snapshot's bounded-history rule (§7.4) is where D's pruning policy becomes visible to clients. |
| **E — status ladder** | B supplies `status: "diverged"` as a word, never a colour (WCAG 1.4.1 satisfiable). **Assumption:** a diverged line rides the existing `attention` rung of P3 D-13's single status slot rather than needing a new rung. E owns the placement. |
| **F — launch preflight** | **Collision, loud:** with a diverged line, **F must not auto-pick a branch to materialize.** Auto-picking is silent last-write-wins wearing a launch-path costume, and it is exactly what SAVE-04 forbids. F's options are (a) launch from the most recent *resolved* revision, or (b) require resolution first. B has no opinion between those; B forbids the third. Note also CACH-04: divergence is already-local state, so answering "is this line diverged?" is a local SQLite read, zero network. |
| **G — resolution UX** | B gives G: both sides retained, device + attributed time + clock-offset annotation + `play_session_id`, and a resolution primitive that supersedes rather than deletes. **B forbids** "delete the other one" as an outcome, and forbids presenting time or file size as the discriminator (Steam's two lies: the clock may be wrong and every GBA SRAM is exactly 32768 bytes). B asks G for gentler language on the two-empty-roots case. |
| **H — export** | **Collision, loud:** a diverged line must export **all branch heads**, not just one. But P2 D-34/D-35's layout is sorted and **timestamp-free**, while SAVE-04 requires showing time. Resolution: branch paths are disambiguated by a stable non-temporal discriminator (revision-id prefix or a deterministic ordinal), and the times live in the `Sidecar` manifest. Do not put device time in a path. |

---

## 13. Forward compatibility — the exact seams

| Seed | The field/seam that keeps it open | What I deliberately did NOT build |
|---|---|---|
| **SEED-001 — save curation & provenance** | Present day one because they are only knowable at capture time and unrecoverable later: `origin_device_id`, `capture_method`, `adapter_id`, `adapter_version`, `blob_sha256` (content fingerprint), `save_format` + `format_confidence` (format identity, known-vs-inferred), `device_captured_at` (capture time), `parent_revision_id` + `supersedes_revision_ids` (revision ancestry). **Deferred safely:** naming, notes, tags, treasuring — all additive string/array fields on an existing row, none retroactively derivable-lossy. **Conversion history** needs no new column: a converted revision is a revision with `capture_method: "converted"` whose lineage already records what it came from. |
| **SEED-002 — physical cartridge** | `capture_method` gains `"cartridge_read"`; `origin_device_id` points at a hardware device row; a write-back is a revision with `capture_method: "cartridge_write"`. **Zero schema change.** Not built. |
| **SEED-019 — system saves vs save states** | `save_kind` exists on day one and Phase 4 accepts only `"battery"`, rejecting anything else with `save_line_kind_unsupported`. Save states later become `save_kind: "state"` with their own compatibility semantics (a state is bound to an exact adapter build; a battery save is not) and their own slot space. **This is the single most important forward-compat field in the schema** — collapsing the two into one undiscriminated vocabulary is unrecoverable once published, and it is precisely what SEED-019 warns about. Not built. |
| **SEED-006 — screenshots** | A future `preview_blob_sha256` on a revision. Additive. Not built. |
| **Multi-slot / directory saves** | `slot` exists on day one, always `"0"`; `save_kind: "memory_card" \| "sram_directory"` reserved. Adding the slot dimension later would be a one-way payload break; adding it now costs one constant string. Not built. |

---

## 14. Decisions (one-shot; `D-xx` are placeholders)

| # | Decision | Rationale (one line) | Reversibility |
|---|---|---|---|
| **D-B1** | Model save divergence as a **parent-pointer immutable revision DAG** per save line — not vector clocks, not CRDTs, not a sequence. | Because the blob is unmergeable, the DAG never has to merge, so it costs one nullable column and gives exact causality and free provenance. | Costly (published payload) |
| **D-B2** | Save-line identity is **`(user_id, content_key, save_kind, slot)`**, where `content_key` is the ROM sha256 — never `asset_set_id`. | Re-importing a ROM makes a new asset set; keying on it would orphan every save. | One-way |
| **D-B3** | Ship `save_kind` (`"battery"` only, all else rejected) and `slot` (`"0"`) **on day one**. | SEED-019's discriminator and the multi-slot dimension are unrecoverable if omitted from a published payload; they cost two constant strings now. | One-way |
| **D-B4** | The base is **`parent_revision_id`**; `NULL` means root; a second root on a line with a head is a real divergence; restore-then-play parents on the restored revision even though that device never saw its ancestors. | Lineage is a property of where the bytes came from, not of what the device observed — the one thing no counter scheme can express. | Costly |
| **D-B5** | Also record **`base_sha256`** and a derived **`base_matched`**; a mismatch is recorded, never rejected. | Catches out-of-band edits and torn reads without pushing the user back to a filesystem workaround (RetroArch's footgun). | Cheap |
| **D-B6** | **Accept-and-branch, not 409-and-reject.** A non-fast-forward revision is stored (`201`, `"branch": true`), the head does not move, the line becomes `diverged`. | The parent pointer is what keeps the client honest; rejecting adds no safety and leaves the losing side's only durable copy on a client, against priority #1. | Costly |
| **D-B7** | The **only** rejection is `409 save_parent_unknown` + `Retry-After` (client outbox ordering, self-healing). Plus `save_branch_limit_exceeded` (32) and `save_revision_immutable` as loud caps. | A retryable ordering error is not a data-safety decision; the caps fail loud, never silent. | Cheap |
| **D-B8** | **No automatic winner, ever.** `head_revision_id` is meaningful only when `status == "linear"`; branch heads are *derived* as revisions with no children. | Explicit rejection of CouchDB's deterministic-winner rule, whose own docs say the winner is neither latest nor best. | Cheap |
| **D-B9** | A **byte-identical child of the head creates no revision** (200, points at the existing head). | Kills the periodic-flush branch-spam vector at the source and saves area D a pile of duplicates. | Cheap |
| **D-B10** | **Resolution is a new revision**: parent = chosen side, `supersedes_revision_ids` = the others, `capture_method: "resolution"`. Nothing is ever deleted. | Non-destructive by construction — strictly better than Steam's irreversible two-button dialog, and it converges the line to one leaf. | Cheap |
| **D-B11** | **Server `recorded_at` is the only orderable time.** Store `device_captured_at`, `device_reported_now`, `device_clock_offset_ms`, `device_monotonic_ms`; none may order or select. Display device time attributed and annotated when offset is large. | Device clocks drift and UUIDv7 ids embed one; separating clock error from queue delay is two cheap fields and is what lets the UI stop lying. | Cheap |
| **D-B12** | Two endpoints: `PUT /api/v1/saves/uploads/:command_id` (streamed bytes, `Repr-Digest` + `Content-Length`, TTL'd pending blob, hard size cap) then `POST /api/v1/saves/revisions` (metadata, `Idempotency-Key` + client UUIDv7). Both mirror `ImportsController` / `PlaySessionsController` exactly. | `Idempotency.fingerprint/1` canonicalizes a parsed body and cannot fingerprint a stream — the split is forced, not stylistic, and it makes retries free. | Costly |
| **D-B13** | One `Playstead.Sync.SavePayload` with `@frozen_keys` and inner `type: "save_line" \| "save_revision"`, following D-08's curation template; **plus a `save:` branch in `Snapshot.read/1`.** | Journal compaction deletes entries after 90 days — without a snapshot branch the lineage has a 90-day event horizon. Mandatory. | Costly |
| **D-B14** | Provenance carried now: `origin_device_id`, `capture_method`, `adapter_id/version`, `save_format`, `format_confidence`, `blob_sha256`, `size_bytes`, `play_session_id` (nullable FK, the only play-context denormalization). Naming/tags/notes/conversion-history deferred. | These are only knowable at capture time; the deferred ones are additive fields on an existing row. | One-way for the included set |
| **D-B15** | Retention rule, binding on area D: **prune bytes (`blob_pruned_at` + an upsert with `bytes_available: false`), never prune nodes; any row deletion requires a `ChangeJournal.tombstone/3`; refcount shared CAS blobs; never prune a diverged branch head.** | A node is ~400 bytes and a blob is 32 KB — deleting nodes buys ~1% of the storage and silently breaks cursor convergence. | Cheap to keep, costly to violate |
| **D-B16** | Accept `expected_head` as an **optional** strictness hint (reserved `save_not_fast_forward`), unused in Phase 4. | Lets a future stricter client opt into hard optimistic concurrency without a protocol change. | Cheap |

---

## 15. Sources

- CouchDB replication & conflict model — <https://docs.couchdb.org/en/stable/replication/conflicts.html>
- PouchDB conflict guide — <https://pouchdb.com/guides/conflicts.html>
- RetroArch Cloud Sync guide (conflict detection & manual resolution) — <https://docs.libretro.com/guides/retroarch-cloud-sync/>
- libretro/RetroArch#16663 (cloud sync breaking N64 saves), #17731, #17474 — <https://github.com/libretro/RetroArch/issues/16663>
- Steam Cloud sync conflict behaviour & data-loss reports — <https://savegamelocation.com/blog/steam-cloud-not-syncing-fix-save-conflicts/>
- Nintendo Switch Online Save Data Cloud compatibility & overwrite semantics — <https://en-americas-support.nintendo.com/app/answers/detail/a_id/41267/>
- Nintendo Life, games excluded from cloud saves — <https://www.nintendolife.com/guides/which-nintendo-switch-games-do-not-support-cloud-saves>

Mutable and worth revalidating before implementation: RetroArch's cloud-sync
conflict behaviour (young feature, has changed across releases) and CouchDB's
winner algorithm (documented as an implementation detail applications must not
depend on). Neither is load-bearing — we copy the shape and reject the winner.
