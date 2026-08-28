# Phase 2 Research — Area A: Import surfaces & staging

Researcher: advisor-researcher (area A). Scope: A1–A10 only. Builds on locked Phase 1 decisions D-01, D-14, D-15, D-17, D-18, D-20, D-21, D-22 and the "already decided" list in BRIEF.md. Existing code consulted: `playstead-server/lib/playstead/{idempotency.ex,sync/change_journal.ex,sync/entity_kind.ex,command_id.ex,readiness.ex}`, `lib/playstead_web/{router.ex,endpoint.ex}`, `config/config.exs` (Oban: Basic engine, `queues: [default: 10]`, Pruner 7d, Cron), `Dockerfile` (runs as `nobody`, `/app/blobs` pre-created), `docker-compose.yml` (named volume `playstead_blobs:/app/blobs`).

---

## One-shot recommendations (summary)

- **A-01 (draft): Three ingestion surfaces ship in Phase 2, each with an honest size class.** (a) LiveView browser upload = single-file immediacy (default ceiling 4 GiB, configurable) using a custom `UploadWriter` that hashes while streaming to a temp file on the blob volume; (b) a read-only host **inbox** bind-mounted at `PLAYSTEAD_INBOX_PATH=/app/inbox` is the *only* large-collection path in v1, scanned on explicit "Stage a collection" action (no inotify/auto-scan); (c) `PUT /api/v1/imports/uploads/{command_id}` single streaming upload with a pre-flight `POST /api/v1/imports/precheck` (sha256+size → exists/absent) so the Phase 3 Mac client never uploads bytes the server already has. — Reversibility: costly — the inbox path and the API upload shape are public compose/protocol surface.
- **A-02 (draft): API upload = one streaming PUT, raw `application/octet-stream`, required `Content-Length`, required `Repr-Digest: sha-256=:…:` (RFC 9530), required `Idempotency-Key`, client UUIDv7 command id in the path; body is never fingerprinted — the idempotency fingerprint is method+path+digest+length.** No tus/chunking in Phase 2; a retry of an interrupted PUT re-sends the whole body (documented; TRAN-01 replaces this). Server verifies its own streamed SHA-256 against `Repr-Digest`; mismatch → 422 `import_digest_mismatch`, nothing stored. — Reversibility: reversible — tus/multipart is additive under a new `transfer` capability; the PUT stays as the small-file path.
- **A-03 (draft): Oban OSS only: one `ImportSessionWorker` job per staged session (unique on `session_id`, `queue: :import` with concurrency 1) that iterates `source_file` rows as its durable cursor and hashes files with `Task.async_stream(max_concurrency: PLAYSTEAD_IMPORT_CONCURRENCY, default 2, ordered: false)`.** Per-file Oban fan-out is rejected (Basic engine has no global concurrency; 10k rows of snooze churn on pause). Single-file imports (LiveView/API) run inline in the request — no job. — Reversibility: reversible — the per-file rows are the contract; swapping the driver loop for Pro Batch later touches one module.
- **A-04 (draft): Pause is cooperative and per-file: the session finishes the file currently being hashed, then stops.** Control lives in `import_sessions.state` + `requested_control` (`pause|cancel|nil`) checked between files; `Oban.pause_queue` is not used (runtime-only, global, not per-session). Resume/retry re-enqueue the unique session job; retry re-queues only `failed` rows (max 3 attempts each); cancel keeps every managed copy already made and marks remaining rows `skipped` — the confirmation says exactly that. Crash mid-file → job rescued, orphan temp swept, that one file re-hashed from zero. — Reversibility: reversible — states are additive.
- **A-05 (draft): Hybrid reconcile: a `source_file` row records `(origin, relative_path, size_bytes, mtime)` as a staging fingerprint; on re-scan a row with an identical fingerprint and a terminal outcome is reported "unchanged" and skipped without re-hashing; any mismatch (or no row) re-hashes.** Blob identity is always full SHA-256; the fingerprint only decides whether to re-read a *staged* file. Export→reimport (PORT-02) always re-hashes every byte (locked). An advanced "Verify everything" action forces full re-hash. — Reversibility: reversible — the fingerprint is an optimization column; dropping it costs a rehash, never correctness.
- **A-06 (draft): Progress reports both bytes and files; bytes drive the bar, files the caption; time estimate appears only after enumeration completes and ≥10 s of throughput, rounded ("about 12 min"), never seconds.** Fine-grained progress goes to LiveView via `Phoenix.PubSub` (ephemeral, ≤4 Hz per session); the change journal gets a `job` entry only on state transitions plus a throttled checkpoint (≥5 s and ≥1 % bytes apart), never per file. Per-file outcomes are DB rows (they are the receipts); each new asset appends its own `catalogue` journal entry inside the per-file transaction. — Reversibility: reversible.
- **A-07 (draft): Pre-confirmation preview is honest about what is knowable before bytes move.** Single file (LiveView): name, exact byte size, "Copy into my library — your original stays where it is; uses 1.2 GB of 480 GB free", format guess from extension flagged as a guess; duplicate status is only known *after* the copy and is stated in the receipt ("exact duplicate — nothing new was stored"). Single file (API/Mac): client hashes locally and calls `precheck`, so the Mac preview can say "already in your library" before transfer. Staged folder: file count, total bytes, per-extension recognized/unknown/archive(opaque) counts, files over the size limit, free-space verdict — all from enumeration, no hashing; time estimate deferred to A-06. — Reversibility: reversible.
- **A-08 (draft): Write path = stream to `PLAYSTEAD_BLOB_PATH/tmp/<uuidv7>.partial` (same volume), `:crypto.hash_update` per 1 MiB chunk, `:file.sync`, then `File.rename` into `objects/sha256/ab/cd/<hash>`; only then the DB transaction (blob + source_file + receipt + journal).** If the CAS path already exists *with* a DB row: trust hash + size check (no byte compare); exists *without* a DB row (crash between rename and commit): re-hash it, then adopt. Orphan `tmp/*.partial` swept at boot and at session start. No post-write re-read in the hot path; export-verify (PORT-02) and a later scrub (Phase 5) cover bit-rot. — Reversibility: one-way — the on-disk layout and "trust the hash" are the custody promise every backup/restore tool relies on.
- **A-09 (draft): Limits: max single file 8 GiB default (`PLAYSTEAD_MAX_IMPORT_FILE_BYTES`); free-space preflight requires `bytes + max(1 GiB, 5 % of volume)` and is re-checked before every file write; hash concurrency default 2 (memory per worker ≈ chunk size × in-flight ≈ single-digit MB); at most 2 concurrent API uploads per device.** Codes: 413 `import_file_too_large`, 507 `storage_insufficient`, 422 `import_digest_mismatch`, 411 `upload_length_required`, 422 `import_empty_file`, 429 `too_many_uploads` + `Retry-After`; each maps to receipt outcome "safely failed" with the same reason text. — Reversibility: reversible — numbers are config; codes are additive registry entries.
- **A-10 (draft): Storage adapter = `Playstead.Blobs.Store` behaviour with a writer handle: `open_write/1 → writer`, `write_chunk/2`, `commit/2 (writer, sha256) → {:ok, :stored | :existing}`, `abort/1`, `exists?/1`, `stat/1 → {:ok, %{size}}`, `stream/2 (sha256, range: nil | {from, to})`, `free_bytes/0`, `writable?/0`; `delete/1` exists for quarantine/abort of uncommitted temp only — no v1 code path deletes a committed blob.** Lives at `lib/playstead/blobs/store.ex` + `store/local_disk.ex`, selected in `runtime.exs`; the `Playstead.Blobs` context is the only caller; Import never touches the adapter. — Reversibility: costly — the behaviour is the seam S3 (STOR-01) must fit; changing it later means two adapters change.

---

## A1 — Which ingestion surfaces ship, and the large-collection path

### Lenses
- **Product/UX (first adopter):** Ethos says "a single file feels immediate; a massive folder becomes a staged background job". The first adopter has a 50 GB folder on a NAS and one ROM on the desktop. Browser upload of 50 GB is dishonest: LiveView chunks at 64 KB over the socket (default `chunk_size: 64_000`, `max_file_size: 8 MB` default) — a 50 GB collection over a websocket in a tab that must stay open is a support ticket, not a feature.
- **Security:** every surface must enforce the same custody rules; the inbox must be mounted read-only so "source untouched" is enforced by the kernel, not by discipline. Inbox paths are untrusted (symlinks, `..`, control chars).
- **SRE/self-hoster:** Immich, Jellyfin and RomM all converge on "a folder the container can see". Jellyfin's inotify watcher silently fails in Docker when `fs.inotify.max_user_watches` is low (issue #16874) and does not work on NFS/CIFS; Immich marks its watcher experimental and warns it "likely won't work" on network drives. Explicit scan is the only honest default.
- **Protocol/Phase 3:** the Mac client needs an API upload in Phase 3; if it isn't in Phase 2, Phase 3 has to design a server surface. Immich's mobile flow hashes client-side and calls `checkBulkUpload` before sending bytes — that is the pattern that makes the Mac preview honest (A7).
- **Preservation domain:** a "collection" is a folder tree of CUE+BIN, CHD, zips (opaque), `.gba`, etc. The scan must preserve relative paths for provenance and for IMPT-04's manifest grouping (area B/C), which needs siblings enumerated together.

### Prior art
- LiveView uploads: `allow_upload/3` defaults `max_entries: 1`, `max_file_size: 8 MB`, `chunk_size: 64_000`, temp-file writer by default; `UploadWriter` runs in the channel uploader process ("any blocking work will block the channel"). https://phoenix-live-view.hexdocs.pm/Phoenix.LiveView.html#allow_upload/3 , https://phoenix-live-view.hexdocs.pm/Phoenix.LiveView.UploadWriter.html
- Immich external libraries: daily scan cron, experimental watcher, `:ro` mount recommended, deleted-on-disk → trash on rescan. https://docs.immich.app/features/libraries/
- Immich bulk-upload precheck (client hashes SHA-1, server answers duplicate/accept). https://api.immich.app/endpoints/assets/checkBulkUpload
- RomM: scans a mounted library folder; ROM identity `(platform_id, fs_name)` enforced with a unique index after a race produced duplicate entries (PR #3606). Lesson: a scan keyed on path needs a DB uniqueness guard. https://github.com/rommapp/romm/pull/3606
- Jellyfin inotify limits in Docker. https://github.com/jellyfin/jellyfin/issues/16874

### Options
| Option | Pros | Cons / footguns | Who it hurts |
|---|---|---|---|
| 1. LiveView upload only in Phase 2; API + inbox later | Smallest surface | IMPT-05 "large collection" via browser is not credible; Phase 3 has to invent an upload API anyway | First adopter with a NAS; Phase 3 |
| 2. LiveView + inbox (bind mount, explicit scan) + API single PUT | Each size class has an honest path; Mac client contract exists before Phase 3; inbox is how every self-hosted media server already works | Three code paths (mitigated: all three feed one `Playstead.Import` service); inbox needs docs on ownership/`nobody` readability | Self-hoster who must chown/`:ro` mount correctly |
| 3. Inbox with auto-watch (inotify) | "Drop and forget" | Silent failure in Docker/NFS; partially-copied files get hashed mid-copy; contradicts quiet-by-default when it half-works | Everyone on NAS |
| 4. API upload as the large path (Mac client uploads folders) | One transfer protocol | Mac client is Phase 3; requires TRAN-01 resumability to be honest for 50 GB | Phase 2 has no large path |

### Adversarial pass (option 2)
- **Half-copied file in the inbox:** user is still `cp`-ing when they click Stage. Mitigation: enumeration records size+mtime; a file whose size or mtime changes between enumeration and hashing is marked `attention: changed while staging` and re-queued for retry, never committed. Docs say "finish copying, then stage".
- **Inbox on a different filesystem from blobs:** reading is fine (we copy). Temp+rename happen inside the blob volume (A8) — no EXDEV.
- **Inbox mounted writable by mistake:** code never opens inbox files for write; readiness row warns if the mount is writable ("Playstead does not need write access to your inbox").
- **`nobody` cannot read the host folder:** enumeration fails fast with a per-file `permission denied` outcome and one session-level hint ("make files readable by the container user (uid 65534)"). Immich documents the same pitfall.
- **Symlink escape:** enumerate with `File.lstat`; skip symlinks and non-regular files (outcome `skipped: link`); reject paths with NUL/control characters.
- **Household later:** a session is owned by `user_id`; the inbox root is server-wide, but sessions are per user; per-user inbox sub-folders are a v2 knob.
- **Future S3:** inbox is a read source, unaffected; the API PUT streams through the server regardless of backend.

### Recommendation
Option 2. Builds on D-14/D-15 (compose shape, named volumes; the inbox is a *bind mount* not a named volume because humans copy files into it from the host), D-18 (`/api/v1`), and the locked "managed copy only; source untouched". Reversibility: costly (public compose and API surface). Claude's discretion: whether the LiveView surface also accepts a folder pick via `webkitdirectory` for small folders (≤ a few hundred MB total) — no product consequence either way.

---

## A2 — API upload transfer mechanics for the Phase 3 Mac client

### Lenses
- **Protocol/durability:** D-20 requires `Idempotency-Key` per mutating request and a receipt in the same transaction as the effect. `Playstead.Idempotency.fingerprint/1` hashes the *body* — impossible for a multi-GB stream; the upload endpoint needs a header-based fingerprint variant.
- **Security:** raw body must bypass `Plug.Parsers` (endpoint already has `pass: ["*/*"]`; a controller `read_body` loop is the Phoenix-idiomatic way). `Content-Length` required so the server can refuse over-limit and check free space before reading a byte; no chunked transfer-encoding accepted in v1 (413/411 up front).
- **Distributed systems:** the client-declared digest turns "did the bytes arrive intact" into a server-verifiable claim; server never trusts it as identity — it re-hashes and compares.
- **Phase 3 Mac:** URLSession streams file bodies from disk natively; a single PUT is the simplest thing that works for GBA/PS1-class files on a LAN. tus needs PATCH/HEAD/offset state — explicitly TRAN-01 (v2).

### Prior art
- tus 1.0: `HEAD`/`PATCH`, `Upload-Offset`, creation/checksum/expiration/termination extensions. https://tus.io/protocols/resumable-upload
- Nextcloud chunked v2: chunks 5 MB–5 GB, assembled by MOVE, 24 h expiry of stale upload dirs. https://docs.nextcloud.com/server/latest/developer_manual/client_apis/WebDAV/chunking.html
- Plug.Parsers `length`/`read_length`/`read_timeout` and `body_reader` for raw access. https://hexdocs.pm/plug/Plug.Parsers.html
- RFC 9530 `Repr-Digest` (standard replacement for ad-hoc `X-Checksum` headers). https://www.rfc-editor.org/rfc/rfc9530.html
- TECHNICAL-RISKS already says: "begin with server-proxied streamed upload for a small-file MVP (bounded length, SHA-256 computed while streaming). Spike tus or S3 multipart before multi-GB."

### Options
| Option | Pros | Cons / footguns | Who it hurts |
|---|---|---|---|
| 1. Single streaming PUT + `Repr-Digest` + `precheck` | Trivial client; server hashes once; dedupe before bytes move; idempotent by construction | Interrupted 6 GB upload restarts from zero; no partial-progress on server | Remote (non-LAN) users with big discs — explicitly v2 |
| 2. tus-style now | Resumable | New state table + expiry sweeper + spike the brief says to run first; would pre-empt TRAN-01 without the spike | Phase 2 scope |
| 3. LiveView only, API deferred to Phase 3 | Less Phase 2 work | Phase 3 designs a server surface mid-client-build; contract tests for import receipts have no API consumer | Phase 3 |

### Adversarial pass (option 1)
- **Retry after the original completed but the response was lost:** `Idempotency-Key` receipt replays the original receipt without re-reading the body — the plug must short-circuit *before* `read_body`. Order in the pipeline: auth → idempotency fetch → (replay) or (read stream).
- **Retry while the original is still streaming:** D-20's 409 + `Retry-After` applies; the client waits, then gets the replayed receipt.
- **Same file uploaded twice with different keys:** second PUT re-streams, hashes, finds the CAS path → outcome `exact duplicate`, a new `source_file` row (provenance kept, locked) — no duplicate logical record.
- **Digest header wrong (client bug):** 422 `import_digest_mismatch`; temp file deleted; nothing stored; receipt "safely failed: the copy did not match the file on your Mac".
- **Content-Length lies (short body):** read loop sees EOF early → same 422 path; long body → server stops reading at declared length and closes.
- **Slow client / stalled socket:** `read_timeout` per chunk (default 15 s → set 60 s) ends the request; temp swept.
- **Household:** command id is a client UUIDv7 unique-constrained per user (D-20b); receipts scoped per device.
- **Future S3:** the writer handle in A10 hides whether bytes land on disk or in a multipart upload.

### Recommendation
Option 1. Builds on D-18, D-20 (fingerprint variant: method+path+`Repr-Digest`+`Content-Length`; body excluded, documented in the endpoint spec), D-22 (codes). Reversibility: reversible — tus arrives under a new `transfer` capability key; `precheck` and the PUT remain.

---

## A3 — Oban job model for a staged collection

### Lenses
- **Oban idiom (OSS 2.24):** Basic engine: per-queue concurrency only, "no global concurrency or rate limiting"; unique jobs are query-based, "prone to race conditions in some circumstances"; jobs "aren't executed inside of a transaction, which alleviates any limitations on how long a job can run" (Reporting Progress guide). Pro's Batch/Chunk/Workflow are exactly the fan-out primitives — and unavailable.
- **Durability:** the durable cursor must live in *our* tables, not in Oban args/meta; a job that dies mid-loop is rescued and must resume from the rows.
- **Backpressure/slow disk:** `Task.async_stream` with bounded `max_concurrency` and `ordered: false` naturally applies backpressure — the loop cannot enumerate faster than hashing drains.
- **SRE:** 10,000 files as 10,000 Oban rows is fine for Postgres but doubles the "why is my DB busy" surface; a single job row per session keeps Oban's `Pruner` and Lifeline behaviour trivial.

### Options
| Option | Pros | Cons / footguns | Who it hurts |
|---|---|---|---|
| 1. One session job, rows as cursor, bounded `Task.async_stream` inside | OSS-only; pause/cancel are one flag check; one job row; concurrency bounded per session and via `queue: :import` concurrency 1 globally | One session at a time per node (second session waits — fine for a personal server); job process must supervise tasks correctly | Household running two sessions concurrently (they serialize) |
| 2. Per-file fan-out jobs | Oban does retry/backoff per file; parallel sessions | Pause = snooze thousands of jobs or drain; no global concurrency in Basic engine (two sessions → 2×N hashes); unique-job races on re-scan; 10k+ rows | Slow-disk users; pause UX |
| 3. Session job that enqueues per-file jobs, then waits | Per-file retry semantics | Same pause/global-concurrency problems as 2 plus a coordinator that needs Pro Batch callbacks to know completion | Same |

### Adversarial pass (option 1)
- **Node restart mid-session:** job in `executing` becomes orphaned; Oban's Lifeline plugin (OSS) rescues after `rescue_after` (default 30 min) — too slow. Mitigation: on application boot, `Playstead.Import` marks sessions in `running` as `interrupted` and re-enqueues their unique job (unique on `session_id`, `states: :incomplete`), which resumes from rows in `pending`; the previous job row, if rescued later, sees the session already `completed`/`running under a newer job` and exits `:ok`. Also add `Oban.Plugins.Lifeline` with a shorter `rescue_after` (5 min).
- **Task crash on one file:** `async_stream` returns `{:exit, reason}` for that file only; row → `failed` with reason; loop continues.
- **Two nodes:** not a v1 deployment (D-14 single app container); `queue: :import` concurrency 1 per node is enough.
- **Malicious huge file count (1M files):** enumeration writes rows in batches of 1,000 with `insert_all`; session shows "enumerating… 412,000 files" before hashing begins; a hard cap (`PLAYSTEAD_MAX_SESSION_FILES`, default 250,000) yields a clear 422.
- **Memory:** each in-flight hash holds one 1 MiB chunk; N=2 → trivial; enumeration must be streamed (`File.stream!`/`Path.wildcard` avoided — use a recursive `File.ls` walk that emits rows in batches).

### Recommendation
Option 1. Builds on the locked "Oban for durable work; retries bounded; idempotent; UUIDv7 command IDs; receipts in the same transaction as effects" and D-20b (unique keys). Reversibility: reversible. Claude's discretion: exact `async_stream` timeout, batch size for `insert_all`, Lifeline `rescue_after`.

---

## A4 — Pause / resume / retry / cancel semantics

### Lenses
- **UX:** "Pause" that takes up to a minute to take effect (finishing an 8 GiB file on a slow disk) is acceptable if the UI says "Pausing — finishing the current file (2.1 of 3.6 GB)…". A pause that abandons a half-hashed file wastes work and surprises nobody positively.
- **Durability:** the pause must survive a restart; `Oban.pause_queue/2` "does not persist across restarts" and is queue-global, so it cannot be the truth.
- **Data safety:** cancel must never delete managed copies already committed — they are library content with receipts. Rolling back a session would violate "imports leave sources untouched; reversibility earns trust" in the other direction (silent deletion).
- **Oban idiom:** `Oban.cancel_job` "kills" an executing job — an abrupt kill mid-write is exactly what A8's temp+rename makes safe, but we prefer cooperative exit so counters and rows are consistent.

### Prior art
- Oban `pause_queue`: "All running jobs will remain running until they are finished"; not persisted. https://oban.hexdocs.pm/Oban.html
- Oban worker return values `:ok | {:error,_} | {:cancel,_} | {:snooze,_}`, default `max_attempts: 20`. https://oban.hexdocs.pm/Oban.Worker.html
- Syncthing keeps failed temp files up to a day to avoid redoing work on retry. https://docs.syncthing.net/users/syncing.html

### Options
| Option | Pros | Cons / footguns | Who it hurts |
|---|---|---|---|
| 1. Cooperative per-file pause; state in `import_sessions`; job exits `:ok` on pause; resume re-enqueues | Durable, per-session, restart-proof; clean counters | Pause latency = one file's hash time | Nobody materially |
| 2. `Oban.pause_queue` | One call | Runtime-only; global (pauses every session); resume after restart is implicit and surprising | Household; anyone who restarts the container |
| 3. Abort in-flight chunk on pause (kill task) | Instant | Wasted IO; temp cleanup path exercised on every pause; progress goes backwards | Slow-disk users |

### Adversarial pass (option 1)
- **Pause pressed twice / pause during "pausing":** idempotent flag; UI shows "Pausing…" then "Paused at 4,210 of 10,000 files".
- **Resume while the old job is still finishing its file:** unique job (`states: :incomplete`) prevents a second job; resume sets `requested_control: nil` and the running job simply continues. 
- **Cancel:** rows `pending` → `skipped: cancelled`; rows `failed` stay `failed` (visible in Needs Attention); session → `cancelled`; confirmation copy: "Stop staging? 4,210 files already in your library stay. 5,790 files will not be copied; you can stage the folder again later."
- **Retry:** re-enqueues the session job with only `failed` rows selected; per-row `attempts` ≤ 3; a file that fails 3× is a Needs Attention item with "retry safe processing" (IMPT-06 vocabulary).
- **Restart mid-file:** see A3; temp swept at session start; that file's row stays `pending` (it only becomes terminal in the commit transaction) so it is simply redone.

### Recommendation
Option 1. Builds on A3, D-20b, the receipts vocabulary. Reversibility: reversible.

---

## A5 — Reconcile after interruption / re-run without duplicating unchanged content

### Lenses
- **Correctness vs speed:** full re-hash of 50 GB every re-scan is ~5–10 min on SATA SSD, 30+ min on a USB HDD/NAS. Every mature tool (Syncthing, rclone, igir, RomVault) uses size+mtime as the "did it change" test and hashes only on mismatch; all of them keep content hashes as identity.
- **Data safety:** the fingerprint can only ever cause an *extra* hash (false "changed"), never a skipped one, provided equality is strict and any doubt → rehash.
- **Preservation domain:** RomVault documents timestamp-granularity conflicts on remote shares causing spurious "modified" flags — harmless here (costs a rehash).
- **Protocol/data model:** the `source_file` row must carry enough to answer "is this the same staged file I already handled" and "where did this blob come from" for export provenance.

### Prior art
- Syncthing: rescan checks "modification time, file size, and permission bits"; only then rehashes. https://docs.syncthing.net/users/syncing.html
- rclone: default compares size+modtime, `--checksum` forces hash compare. https://rclone.org/commands/rclone_sync/
- igir file cache: keyed on absolute path, invalidated when "size or modified timestamp has changed". https://igir.io/advanced/file-cache/
- RomM: unique index on `(platform_id, fs_name)` after a race created duplicate library entries. https://github.com/rommapp/romm/pull/3606
- git-annex: importing two files with same content yields two files, one stored object (SHA256E). https://git-annex.branchable.com/backends/

### Options
| Option | Pros | Cons / footguns | Who it hurts |
|---|---|---|---|
| 1. Full re-hash every run | Zero trust in metadata | Re-scan of a big inbox costs the full read every time; discourages the "stage again after fixing a few files" loop | NAS/HDD users |
| 2. Fingerprint only (skip if size+mtime match) | Fast | Fingerprint match on a *pending* (never-hashed) row must still hash — easy to get wrong; mtime-preserving overwrites (rare, `cp -p` of a different file with same size) are missed | Nobody if rule is "skip only terminal rows" |
| 3. Hybrid: skip only rows with matching fingerprint AND terminal outcome; hash everything else; advanced "Verify everything" | Fast in the common loop, safe by construction | One more column set; docs must explain "unchanged" | — |

### Adversarial pass (option 3)
- **User replaces a file with a same-size file and preserves mtime:** missed until "Verify everything". Documented; this is the same posture as Syncthing/rclone/igir. Data safety is unaffected (nothing is deleted; the old blob is still correct for the old bytes).
- **Same file appears at two inbox paths:** two `source_file` rows (provenance, locked), one blob, second outcome `exact duplicate`.
- **File removed from inbox after import:** nothing happens — the managed copy is canonical; row keeps its staging path for audit; no "missing" alarm (the inbox is not a library, unlike Immich external libraries).
- **Export→reimport:** locked full re-hash; the sidecar is consulted only to *group* members (area C) and to report "matches manifest"; dedupe is by sha256 → zero duplicate blobs, and the logical-record dedupe (asset_set UUID from the sidecar) is area C's concern.
- **Household:** fingerprint uniqueness is per `(user_id, origin, relative_path)`; DB unique index (RomM lesson) prevents a racing double-stage from creating two rows.

### Recommendation
Option 3. `source_file` columns: `user_id`, `import_session_id`, `origin` (`inbox|browser|api|export_reimport`), `relative_path` (inbox-relative; for uploads the client-supplied display name, sanitized for display only), `size_bytes`, `mtime` (as reported, full precision), `blob_id` (nullable until hashed), `outcome`, `outcome_detail`, `attempts`, `command_id`. Builds on the locked three-layer identity model and "keep many source_file provenance rows per blob". Reversibility: reversible.

---

## A6 — Progress reporting

### Lenses
- **UX honesty:** bytes are the truthful unit (one 4 GB CHD ≠ one 32 KB `.gb`); files are what users count. Percent by files lies during the big files; percent by bytes lies about "how many things are left". Show both: bar = bytes, caption = "4,210 of 10,000 files · 18.2 of 61.4 GB". Estimates only after a throughput sample; Plex/Jellyfin users complain precisely about missing/indeterminate scan progress.
- **Protocol (D-21):** the `job` entity kind is frozen; the Mac client reconstructs job state via `/changes`/snapshot. A 10,000-file session must not produce 10,000 `job` journal entries — but it legitimately produces up to 10,000 `catalogue` entries (each new asset is a catalogue change the Mac must learn).
- **Oban idiom:** the Reporting Progress guide's pattern is PubSub broadcast from the executing job.
- **SRE:** journal writes are serialized behind the advisory lock in `ChangeJournal.write/5`; per-file journal entries at hash speed are fine (they're inside the per-file commit anyway); per-progress-tick entries are not.

### Options
| Option | Pros | Cons | Who it hurts |
|---|---|---|---|
| 1. Files only | Simple | Bar stalls on big files; "estimates" are noise | Disc-collection users |
| 2. Bytes only | Truthful bar | Users can't tell "how many games are in" | Everyone |
| 3. Both; PubSub for LiveView; throttled `job` journal checkpoints; per-asset `catalogue` entries in the per-file txn | Honest, cheap, protocol-consistent | Two channels to keep in sync (PubSub is a hint; DB is truth — same rule as D-21 events) | — |

### Adversarial pass (option 3)
- **LiveView mounts mid-session:** reads session row + counts from DB, then subscribes; PubSub ticks are deltas that never override the DB on reconnect.
- **Mac client polling `/changes`:** sees ≤ one `job` entry per ~5 s per session plus state transitions, and one `catalogue` entry per new asset — bounded and compactable.
- **Estimate whiplash:** compute from an EWMA of bytes/s over the last 60 s; display rounded and only when remaining > 30 s; never "0 seconds".
- **10,000 files in 40 s (tiny GB ROMs on NVMe):** journal gets ~8 job checkpoints; catalogue entries 10,000 — necessary and correct.

### Recommendation
Option 3. Builds on D-21 (frozen `job` kind; events are hints, never correctness). Reversibility: reversible. Claude's discretion: exact throttle constants.

---

## A7 — IMPT-01 pre-confirmation preview

### Lenses
- **UX:** "see before confirmation" must be true, not theatrical. The browser can tell us name, size, and client-reported MIME *before* any byte moves; magic bytes and the hash are only knowable after the copy. Say so.
- **Security:** never render the client filename with authority; show it as "the file you chose", sanitized; the extension-based format guess is labelled a guess.
- **Domain:** for staged folders, extension histograms are genuinely useful pre-hash information ("312 .gba, 40 .cue + 88 .bin, 12 .zip (kept as-is, not opened), 3 unknown").
- **Phase 3 Mac:** local hashing + `precheck` (A2) lets the Mac preview say "already in your library" honestly before transfer — the strongest form of IMPT-01.

### Options
| Option | Pros | Cons | Who it hurts |
|---|---|---|---|
| 1. LiveView pre-upload preview (name/size/free space/format guess) → confirm copies, hashes, commits; duplicate reported in receipt | Honest; no wasted temp uploads on cancel | "Exact duplicate" only known after the copy — but "storage used: 0 B, nothing new stored" is a fine receipt | Nobody |
| 2. LiveView auto-uploads to temp, then previews with hash/dup status, then confirm commits | Richest preview | Transfer happens before consent; temp orphans on tab close; contradicts "copy on confirm" copy | Users who cancel |
| 3. Client-side hashing in the browser (WebCrypto) before upload | Dup status pre-transfer | Reads the whole file in JS (slow, memory), duplicates logic the Mac client will own | Big-file users |

### Recommendation
Option 1 for LiveView, `precheck`-backed preview for the API/Mac path. Preview contents — single file: display name; exact bytes + humanized; "Copy into my library"; "Your original stays where it is. A verified copy will be stored by your server."; "Uses 1.2 GB of 480 GB free" (or the 507 refusal with numbers); "Looks like a Game Boy Advance file (from its name — we'll confirm after copying)". Folder: counts and bytes; extension histogram with recognized/unknown/archive(opaque); files over the size limit listed; free-space verdict for the total; "Time estimate appears once copying starts". Builds on ethos Import contract, D-22. Reversibility: reversible.

---

## A8 — Write path & atomicity

### Lenses
- **Durability:** temp on the same volume → `rename` is atomic; `:file.sync` before rename makes the data durable; Erlang cannot `fsync` a directory (`:file.open` on a directory returns `eisdir`), so rename durability without a directory fsync is the accepted gap — mitigated by ordering (rename *before* the DB commit) so the DB never references a blob that might not exist; the reverse (blob without row) is a harmless orphan that re-import adopts.
- **Security:** the CAS path is server-generated (`objects/sha256/ab/cd/<64hex>`), never from user input (OWASP). Temp names are UUIDv7, no user text.
- **Dedupe:** git, restic, git-annex, Syncthing all trust the hash on "object exists". A byte compare on every duplicate doubles IO on the very collections dedupe is for. Size mismatch at the same hash is the one cheap collision/corruption detector and is free.
- **SRE:** orphan sweep must not race a running session: sweep only files older than the session-start high-water mark, and never during an active session on the same node.

### Prior art
- restic local backend: write to temp, sync, rename; broken files keep `*-tmp-*` names and are ignored. https://github.com/restic/restic/pull/3436
- Syncthing temp-file naming and retention. https://docs.syncthing.net/users/syncing.html
- Crash-consistency: fsync file before rename; directory fsync for durable rename. https://0xkiire.com/crash-consistency-fsync-rename/
- Docker: named volumes stay on one filesystem (no EXDEV); overlay layer renames can hit EXDEV — never write temp into the image layer. https://github.com/pnpm/pnpm/issues/3439

### Options
| Option | Pros | Cons | Who it hurts |
|---|---|---|---|
| 1. temp(same volume) → hash while streaming → fsync → rename → DB txn; existing+row ⇒ trust hash+size; existing+no-row ⇒ rehash & adopt; no re-read | Atomic visibility, crash-safe ordering, single read of input | No directory fsync (Erlang limit); bit-rot on write undetected until export-verify/scrub | Extremely rare hardware faults |
| 2. Same + full re-read verify after rename | Detects write-path corruption immediately | Doubles IO for every import; 50 GB stage becomes 100 GB of IO | HDD/NAS users; slows the happy path |
| 3. Byte-compare on duplicate | Paranoid against SHA-256 collision | Reads both copies; no mainstream CAS does this | Dedupe-heavy users |

### Adversarial pass (option 1)
- **Crash after rename, before commit:** blob exists, no rows; next import of the same bytes hits "exists, no row" → rehash (once) → adopt; a Phase 5 scrub can also adopt/report orphans.
- **Crash before rename:** `tmp/<uuid>.partial` swept at boot/session start; the source_file row is still `pending`.
- **Disk full mid-write:** `write` returns `{:error, :enospc}` → temp deleted → row `failed: storage_insufficient` → session pauses itself (not retry-storms) with a clear message; A9 preflight makes this rare.
- **Two concurrent imports of the same new bytes (API + session):** both write temps; the second `rename` overwrites an identical file atomically (POSIX rename replaces) — harmless; the DB unique on `blobs.sha256` makes the second commit take the `on_conflict` path and record `exact duplicate`.
- **Hash-collision fantasy:** size check at same hash; a size mismatch → `attention: integrity` and never overwrite.
- **Future S3:** same shape — upload to a temp key while hashing, then `CopyObject` to the CAS key and delete temp; `commit/2` hides it.
- **Household:** blobs are global per server (dedupe within tenant is locked; v1 has one tenant); `source_file`/receipts carry `user_id`.

### Recommendation
Option 1. Builds on the locked CAS layout and "transactional metadata before visibility". Reversibility: one-way for layout and trust-the-hash; the optional re-read verify is a config flag (Claude's discretion, default off).

---

## A9 — Ingest resource limits & quotas

### Lenses
- **Domain:** biggest common single files: PS2 dual-layer DVD ≈ 8.5 GB (just over 8 GiB = 8.59 GB, fits), GameCube 1.4 GB, PS1 ~700 MB, CHDs smaller. 8 GiB covers v1 target systems; Blu-ray-class (25–50 GB) is not a v1 system.
- **SRE:** free-space must be measured on the blob volume from inside the container (`:disksup` needs `:os_mon` in `extra_applications`; alternative: `System.cmd("df", ["-kP", path])` parsed — either is Claude's discretion). Margin protects Postgres on the same disk and the temp file.
- **Security/DoS:** per-device concurrent upload cap + `Content-Length` up-front refusal + per-chunk read timeout; Hammer already present for throttles.
- **Protocol:** every limit is a stable `code` (D-22) and a receipt outcome (IMPT-03 "safely failed") with the same text, so LiveView and Mac say the same thing.

### Options
| Option | Pros | Cons |
|---|---|---|
| 1. Fixed generous defaults, all env-configurable, one code per limit | Predictable; documented in `.env.example` (D-15) | Numbers are guesses until real collections hit them |
| 2. Derive limits from volume size | "Smart" | Surprising; hides the numbers users need to plan |

### Recommendation
Option 1 with: `PLAYSTEAD_MAX_IMPORT_FILE_BYTES=8GiB`, `PLAYSTEAD_IMPORT_CONCURRENCY=2`, `PLAYSTEAD_MAX_SESSION_FILES=250000`, free-space margin `max(1 GiB, 5 %)`, API per-device concurrent uploads 2, `read_timeout` 60 s, hash chunk 1 MiB. Codes: 413 `import_file_too_large`, 507 `storage_insufficient`, 422 `import_digest_mismatch`, 411 `upload_length_required`, 422 `import_empty_file`, 429 `too_many_uploads`, 422 `import_session_too_large`. Builds on D-15, D-22. Reversibility: reversible.

---

## A10 — Storage adapter boundary

### Lenses
- **Elixir idiom:** a `@behaviour` with a small callback set, adapter chosen by config, a context module (`Playstead.Blobs`) that owns the public API and the DB rows; callers never `Application.get_env` the adapter themselves. Same shape as `Ecto.Adapter`, `Swoosh.Adapter`, Oban engines.
- **Durability:** the behaviour must expose the temp→commit two-phase shape (A8) or S3 cannot implement "hash while streaming, then name by hash".
- **Phase 3/CACH-01:** `stream/2` takes an optional byte range now so Range downloads are an endpoint concern, not an adapter change.
- **Data safety:** no v1 caller deletes a committed blob; `delete/1` exists so quarantine cleanup and tests can use it, guarded in `Playstead.Blobs` (not exposed on the context in v1).

### Options
| Option | Pros | Cons |
|---|---|---|
| 1. Behaviour with writer handle (`open_write/write_chunk/commit/abort`) + `exists?/stat/stream/free_bytes/writable?/delete` | Fits disk and S3 multipart; hashing stays in `Playstead.Blobs` (one implementation, tested once) | Slightly more ceremony than `put(sha, path)` |
| 2. `put(sha256, source_path)` file-path API | Simplest | Forces every surface to have a local file first; S3 would stage to disk anyway; hashing duplicated per surface |
| 3. Use a VFS library (e.g. jido_vfs) | Adapters for free | Generic filesystem semantics, not CAS semantics; external dependency on the custody core |

### Recommendation
Option 1. Module layout: `lib/playstead/blobs.ex` (context: `store_stream/2`, `precheck/2`, `open/2`, `stat/1`), `lib/playstead/blobs/store.ex` (behaviour), `lib/playstead/blobs/store/local_disk.ex`, `lib/playstead/blobs/blob.ex` (schema). Import (`lib/playstead/import/*`) depends on `Playstead.Blobs` only. Builds on "local disk first behind a storage adapter", D-15 config layering. Reversibility: costly (the seam S3 must fit). Claude's discretion: whether `commit/2` returns the final path or an opaque storage key (recommend opaque key stored on `blobs.storage_key`).

---

## Deferred ideas surfaced
- Inbox auto-watch (inotify/polling) once a filesystem-type check and a "file stable for N seconds" debounce exist — v2.
- tus / S3 multipart resumable upload with `Upload-Expires` sweeper — TRAN-01 (v2), keyed to a `transfer` capability.
- Periodic blob scrub (re-hash sample/all, adopt orphans, report bit-rot) and "Verify library" — Phase 5 (OPER-03/PORT-03) health surface.
- Per-user inbox sub-folders for household mode — v2 (schema already carries `user_id`).
- Optional post-write full re-read verify as a config flag for paranoid self-hosters.
- Oban Lifeline `rescue_after` tuning and a `PLAYSTEAD_IMPORT_CONCURRENCY` auto-derivation from CPU count.
- Browser folder pick (`webkitdirectory`) for small folders in LiveView.
- `Repr-Digest` on downloads and `Range` support — Phase 3 (CACH-01) endpoint work; adapter already supports ranges.
- Container resource limits (memory) in compose once import workers exist — Phase 5 docs.

## Sources
- Phoenix LiveView `allow_upload/3` — https://phoenix-live-view.hexdocs.pm/Phoenix.LiveView.html#allow_upload/3
- Phoenix LiveView `UploadWriter` — https://phoenix-live-view.hexdocs.pm/Phoenix.LiveView.UploadWriter.html
- Phoenix LiveView uploads guide — https://phoenix-live-view.hexdocs.pm/uploads.html
- Plug.Parsers (length/read_length/read_timeout/body_reader) — https://hexdocs.pm/plug/Plug.Parsers.html
- Oban core (pause_queue, cancel_job, Basic engine limits) — https://oban.hexdocs.pm/Oban.html
- Oban.Worker (return values, max_attempts, backoff) — https://oban.hexdocs.pm/Oban.Worker.html
- Oban unique jobs — https://oban.hexdocs.pm/unique_jobs.html
- Oban.Job (meta, unique, priority, conflict?) — https://oban.hexdocs.pm/Oban.Job.html
- Oban Reporting Job Progress — https://oban.hexdocs.pm/reporting-progress.html
- Oban Pro overview (Batch/Chunk/Workflow, Smart engine) — https://oban.pro/docs/pro/overview.html
- tus resumable upload protocol 1.0 — https://tus.io/protocols/resumable-upload
- Nextcloud chunked upload v2 — https://docs.nextcloud.com/server/latest/developer_manual/client_apis/WebDAV/chunking.html
- RFC 9530 Digest Fields (`Repr-Digest`) — https://www.rfc-editor.org/rfc/rfc9530.html
- OWASP File Upload Cheat Sheet — https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html
- Immich external libraries — https://docs.immich.app/features/libraries/
- Immich checkBulkUpload API — https://api.immich.app/endpoints/assets/checkBulkUpload
- Immich duplicate-before-upload discussion — https://github.com/immich-app/immich/discussions/8840
- RomM first scan — https://docs.romm.app/5.1.0/getting-started/first-scan/
- RomM duplicate-entries race fix — https://github.com/rommapp/romm/pull/3606
- Jellyfin inotify limit in Docker — https://github.com/jellyfin/jellyfin/issues/16874
- Syncthing syncing internals (temp files, rescan) — https://docs.syncthing.net/users/syncing.html
- rclone sync (size/modtime vs `--checksum`) — https://rclone.org/commands/rclone_sync/
- igir file cache — https://igir.io/advanced/file-cache/
- igir reading archives / CRC32 default — https://igir.io/input/reading-archives/
- git-annex backends (SHA256E) — https://git-annex.branchable.com/backends/
- restic temp-name writes — https://github.com/restic/restic/pull/3436
- Crash consistency fsync/rename — https://0xkiire.com/crash-consistency-fsync-rename/
- EXDEV in Docker overlay vs named volumes — https://github.com/pnpm/pnpm/issues/3439
- Hashing files in Elixir (chunked `File.stream!` + `:crypto.hash_update`) — https://www.poeticoding.com/hashing-a-file-in-elixir/
- Elixir `:disksup`/os_mon note — https://elixirforum.com/t/diskspace-retrieve-disk-usage-statistics-for-a-given-filesystem-path/72064
- Playstead TECHNICAL-RISKS.md and EXPERIENCE-ETHOS.md (project-local)
