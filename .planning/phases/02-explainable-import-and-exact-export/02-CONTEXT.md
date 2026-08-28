# Phase 2: Explainable Import and Exact Export - Context

**Gathered:** 2026-08-28
**Status:** Ready for planning

<domain>
## Phase Boundary

The server-side custody pipeline and its console/API surfaces: managed-copy import with streaming SHA-256 into a content-addressed local blob store; durable per-file import receipts carrying the full outcome taxonomy; ordered multi-file asset manifests with explicit required members; staged, resumable, observable collection imports on Oban with pause/resume/retry/cancel/reconcile; a Needs Attention inbox with five audited, reversible resolutions; a pluggable recognition provider with header evidence and admin-supplied DAT packs; and deterministic BagIt-shaped ordinary-folder export with write-then-verify and lossless reimport that creates no duplicate logical records (IMPT-01–06, PORT-02).

Surfaces are the LiveView console and `/api/v1` (the Phase 3 Mac client consumes the API contracts frozen here). No Mac UI, no download/cache (Phase 3), no saves in exports (Phase 4), no backup/health/reclaim (Phase 5), no archive inspection (deferred spike), no S3 (v2).

</domain>

<decisions>
## Implementation Decisions

All decisions below were produced by four parallel multi-lens research fan-outs (security, product/first-adopter UX, Elixir/OTP/Oban/Ecto idiom, durability, SRE/self-hoster ops, data-model/protocol, accessibility/microcopy, ROM-preservation domain) with online prior-art research and adversarial passes, reconciled across areas, and approved by the owner as a set. Twelve points where lenses disagreed were put to the owner; every ruling is recorded inline as **Owner ruling**. Full option tables, adversarial passes, and sources: `discussion-research/`. Phase 1 decisions are cited as `P1 D-xx`.

### Ingestion Surfaces

- **D-01:** Three ingestion surfaces ship, each with an honest size class. (a) LiveView browser upload for single-file immediacy via a custom `Phoenix.LiveView.UploadWriter` that hashes while streaming to a temp file on the blob volume; (b) a read-only host **inbox** bind-mounted at `PLAYSTEAD_INBOX_PATH=/app/inbox` (compose: `./inbox:/app/inbox:ro`) is the only large-collection path in v1, scanned on an explicit "Stage a collection" console action — no inotify/auto-scan; (c) `PUT /api/v1/imports/uploads/{command_id}` single streaming upload plus `POST /api/v1/imports/precheck` (sha256 + size → exists/absent) so the Mac client never sends bytes the server already has. **Owner ruling:** read-only bind mount over a named volume — humans copy files into a host folder they can see, and `:ro` makes "source untouched" a filesystem guarantee. — **Reversibility:** costly — the compose file's public shape and the API surface are published; the inbox path appears in setup docs.
- **D-02:** API upload = one streaming `PUT`, `application/octet-stream`, required `Content-Length`, required `Repr-Digest: sha-256=…` (RFC 9530), required `Idempotency-Key` (P1 D-20), client UUIDv7 command id in the path; the idempotency fingerprint is method + path + digest + length (the body is never fingerprinted). No tus/chunking in Phase 2; an interrupted PUT re-sends the whole body (documented; TRAN-01 replaces this in v2 under a `transfer` capability). Server re-hashes and compares; mismatch → `422 import_digest_mismatch`, nothing stored. — **Reversibility:** reversible — resumable upload is additive under a capability key.
- **D-03:** Upload ceilings: 4 GiB for the browser path, 8 GiB for the API path and inbox (covers PS2 dual-layer), both configurable. Preflight copy for oversize browser files: "Files over 4 GB: copy them into your inbox folder instead." **Owner ruling:** split ceilings — honest about websocket uploads; nudges disc collections to the inbox.
- **D-04:** IMPT-01 preview shows only what is knowable before bytes move. Single file: name, exact byte size, primary action **Copy into my library**, "Your original stays where it is; uses 1.2 GB of 480 GB free", extension-based format guess labelled as a guess; duplicate status is stated in the receipt after the copy (browser cannot hash first). Mac/API: local hash + `precheck` lets the preview say "already in your library" before transfer. Staged folder: file count, total bytes, recognized/unknown/archive-kept-unopened histogram, over-limit files, free-space verdict — no hashing during preview.

### Durable Work: Staged Collections

- **D-05:** Oban OSS only. One `ImportSessionWorker` job per staged session (unique on `session_id`, `queue: :import`, concurrency 1) iterates `source_file` rows as its durable cursor and hashes via `Task.async_stream(max_concurrency: PLAYSTEAD_IMPORT_CONCURRENCY, default 2)`. Per-file job fan-out is rejected (the Basic engine has no global concurrency; pausing would mean snoozing thousands of jobs). Single-file imports run inline in the request, no job. Export (D-38) reuses this job/progress/control model.
- **D-06:** Pause is cooperative and per-file: finish the file being hashed, then stop. Truth lives in `import_sessions.state` + `requested_control`, checked between files; `Oban.pause_queue` is not used (runtime-only, global). Resume and retry re-enqueue the unique session job; retry re-queues only `failed` rows (max 3 attempts each). Crash mid-file → orphan temp swept, that file redone. Bounded Oban retries happen before a receipt is finalized; only exhausted retries create inbox items.
- **D-07:** Cancel keeps every managed copy already made, marks the rest `skipped`, and the confirmation says exactly that. No "stop and remove what this session added" path. **Owner ruling:** keep — never silently remove library content; avoids the dedupe trap where a session matched blobs it did not create. Undo is per-item Exclude (D-27).
- **D-08:** Reconcile is hybrid: `source_file` records `(origin, relative_path, size_bytes, mtime)`; on re-scan a row with an identical fingerprint AND a terminal outcome is reported "unchanged" and skipped without re-hashing; anything else re-hashes. Blob identity is always full SHA-256; export→reimport always re-hashes every byte (locked); an advanced "Verify everything" forces a full re-hash.
- **D-09:** Progress = bytes (bar) + files (caption); a time estimate appears only after enumeration and ≥10 s of throughput, rounded, never in seconds. LiveView receives ≤4 Hz `Phoenix.PubSub` ticks (hints, never correctness). The change journal receives a `job` entry only on state transitions plus throttled checkpoints (≥5 s and ≥1 % apart), never per file; each new asset appends its own `catalogue` entry inside the per-file transaction (P1 D-21 entity kinds are frozen — Phase 2 adds producers, never kinds).
- **D-10:** Limits and codes: max single file 8 GiB; free-space preflight `bytes + max(1 GiB, 5 %)` re-checked before every write; hash concurrency 2; ≤2 concurrent API uploads per device; `read_timeout` 60 s; session cap 250k files. Problem+json codes (P1 D-22 registry): `413 import_file_too_large`, `507 storage_insufficient`, `422 import_digest_mismatch`, `411 upload_length_required`, `422 import_empty_file`, `429 too_many_uploads`, `422 import_session_too_large`. Each maps to a `failed_safely` receipt with the same plain-language text.

### Write Path and Storage Seam

- **D-11:** Write path: `PLAYSTEAD_BLOB_PATH/tmp/<uuidv7>.partial` on the same volume → hash per 1 MiB chunk (SHA-256 + CRC32/MD5/SHA-1 in the same pass, D-20) → `:file.sync` → **read back and re-hash the file from disk** (default on; `PLAYSTEAD_IMPORT_VERIFY=false` documented for slow disks) → `File.rename` into `objects/sha256/ab/cd/<hash>` → one DB transaction (blob, source_file, receipt, journal entries, next Oban step). CAS path exists with a DB row: trust hash + size check, no byte compare; exists without a row (crash between rename and commit): re-hash, then adopt. Orphan temps swept at boot and at session start. **Owner ruling:** default-on read-back — data safety is priority #1 and this is the moment the custody promise is made; resolves the A-08/C-06 conflict. — **Reversibility:** one-way — the on-disk layout and trust-the-hash rule are the custody promise every backup, export, and S3 migration relies on.
- **D-12:** `Playstead.Blobs.Store` behaviour with a writer handle: `open_write/1`, `write_chunk/2`, `commit/2 (writer, sha256) → {:ok, :stored | :existing}`, `abort/1`, `exists?/1`, `stat/1`, `stream/2 (sha256, range)`, `free_bytes/0`, `writable?/0`; `delete/1` exists only for uncommitted temp files — **no v1 code path deletes a committed blob**. Lives in `lib/playstead/blobs/store.ex` + `store/local_disk.ex`, selected in `runtime.exs`; the `Playstead.Blobs` context is the only caller; Import never touches the adapter. — **Reversibility:** costly — this is the seam the v2 S3 adapter must fit.
- **D-13:** Physical bytes are global; everything visible is user-scoped (P1 D-01). `blobs` carry no `user_id`; source_files, import sessions, receipts, asset_sets, attention items, overrides, and exports do. Duplicate is evaluated per user (user A's duplicate is user B's `new_asset`; one copy on disk; never disclosed across users). Physical reclaim (Phase 5) requires zero cross-user references. — **Reversibility:** costly — schema shape for physical vs logical ownership.

### Formats, Manifests, and Recognition

- **D-14:** v1 allowlist = seven system ids in two tiers, a frozen registry like `Playstead.Sync.EntityKind`: `gba gb gbc nes snes md psx` (+ `unknown`). Tier A signature-validated (magic + checksum/complement): `gba`, `gb`, `gbc`, `nes` (iNES/NES 2.0), `md` (`SEGA` at 0x100). Tier B structure-validated (heuristic, labelled as such): `snes` (internal checksum⊕complement, 512-byte copier rule), `psx` (`.cue`+`.bin` via bounded CUE parse; `.chd` header-only, no hunk decompression). Validators are pure Elixir binary pattern matches on the first ≤64 KiB (no NIFs/ports/external tools), never raise, and get adversarial fixtures (QUAL-02). Everything else is accepted as a blob and receipted "kept as-is, not recognized". "Supported" = system assigned AND format evidence recorded; the tier is evidence, never a verdict on the bytes. Adapter-facing names (RetroArch core ids, ES-DE folders) are a client mapping, not server truth. **Owner ruling:** seven ids over GBA+PSX only. — **Reversibility:** one-way for the id strings (they go into export manifests and the client journal); additive otherwise.
- **D-15:** IMPT-04 is proven with Redump-style PS1 CUE+BIN. `asset_member{ordinal, role ∈ descriptor|track|primary|disc|patch|parent|companion, required, blob_id (null while missing), declared_name, export_path}`. CUE is parsed as text with hard caps (≤64 KiB, ≤99 FILE/TRACK entries, `BINARY` only, bare relative names, no `..`/separators/control chars). Missing BIN → `incomplete_set`, inbox "attach missing companion". M3U multi-disc and CHD parent roles exist in the vocabulary but are not proven in Phase 2. — **Reversibility:** costly — roles and ordinals go into the sidecar (D-35) and the Phase 3 catalogue contract (D-23).
- **D-16:** Recognition without a DAT is a header-evidence pipeline: extension, magic/structure result, header fields (GBA title/game code, GB flags, NES mapper/NES 2.0, SNES title/checksum/copier, MD serial/region, CUE track table), size facts, No-Intro filename parse. "Supported format, no reference installed" is a normal quiet state that never enters Needs Attention (D-26). Evidence rows are append-only.
- **D-17:** Frozen definitions. **alias** = same sha256 already in the user's library under a different name → new `source_file`, no new blob. **variant** = different bytes, same logical release — without a reference only "possible variant" via matching header serial/game code on the same system; certainty requires a DAT match. **patched** = IPS/UPS/BPS *patch files* detected by magic (`PATCH`/`UPS1`/`BPS1`) stored as role `patch` (BPS/UPS base CRC32 may link to an existing blob as a candidate, never applied); patched *ROMs* are not claimed without a reference. Header-stripped / non-power-of-two sizes are evidence lines, never verdicts.
- **D-18:** Phase 2 ships the `recognition` schema, the `Playstead.Recognition.Provider` behaviour, the built-in `HeaderEvidence` provider, and an admin-supplied Logiqx-XML DAT-pack importer (SAX, no DTD/entities, size/entry caps, fuzzed) as the **last, independently droppable plan**. Pack provenance: `source_url, retrieved_at, upstream_version, file_sha256, license_claim (enum + note), transform_version`. Confidence: `exact | header | filename | user`. Corrections live in `recognition_overrides` with an audit id; evidence rows are never rewritten. No pack is ever bundled (Redump: public domain per its site; libretro-database: CC BY-SA 4.0; No-Intro: no published license) — admin-supplied only, with the license claim recorded. **Owner ruling:** DAT import in, as the last droppable plan. — **Reversibility:** reversible for the importer; one-way for the evidence-vs-override split.
- **D-19:** System assignment = extension map → header confirm (upgrade or contradict) → user override, stored as `asset_set.system_id` + `system_source ∈ extension|header|reference|user`. Contradictions (extension says one, header says another) → Needs Attention "confirm system" with both shown. User correction writes an override row + `AuditLog` entry.
- **D-20:** CRC32/MD5/SHA-1 are computed alongside SHA-256 in the single streaming pass and stored as columns on `blob`. Headerless NES (skip 16) and SNES copier (skip 512) fingerprints are computed in the same pass once the header is seen, stored in `blob_fingerprints{kind, offset, crc32, md5, sha1}` — DATs hash headerless, so both forms are needed. — **Reversibility:** reversible, but backfill would re-read the whole store — the expensive path this avoids.
- **D-21:** Archives (detected by magic, not extension: zip, 7z, rar, gzip, xz, zstd) are accepted as opaque blobs, system `unknown`, outcome `unrecognized{reason: archive_not_opened}`. The IMPT-01 preflight states it before copy ("N archives will be kept exactly as-is but can't be played until archive support ships — extract first if you want them playable") including their storage cost; Needs Attention groups them as **one item per import** ("312 archives kept unopened") with resolutions retain-as-custom / exclude. Archives are never quarantined merely for being archives. **Owner ruling:** accept opaque over refuse-at-preflight. The archive-security gate remains a deferred spike; its acceptance criteria are in `<specifics>`.
- **D-22:** Display title = No-Intro filename parse when it succeeds (`Title (Region) (Languages) (Version) (Devstatus) (Additional) [Status]` → `display_title` + `tags`), else the sanitised filename stem; the cartridge-header title is evidence, never preferred. Original name kept byte-exact in `source_file.original_name`; display form NFC-normalised, control/bidi/zero-width characters stripped, capped at 200 code points, rendered only through HEEx escaping; `title_override` via the override row.
- **D-23:** `catalogue` change-journal payload (entity_id = asset_set UUID): `{id, system, status ∈ complete|incomplete, display_title, title_source, tags{region,languages,version,dev_status}, manifest_version, members:[{ordinal, role, required, sha256, size, name}], recognition{status ∈ no_reference|exact|header|filename|user, confidence, provider, provider_version, reference_name}, attention, excluded_at, updated_at}`; tombstone on exclude. Source paths, legacy hashes, and provenance stay out of the client payload. Snapshot (P1 D-21) gains `catalogue` and `job` branches. — **Reversibility:** one-way — this is the Phase 3 client contract; additions only, never renames.

### Receipts, Outcomes, and Needs Attention

- **D-24:** Two tables, one vocabulary: `import_sessions` (one per user-initiated import; rolled-up counts + lifecycle) and `import_receipts` (exactly one per submitted source file, immutable, indefinite retention, user-scoped). A receipt always references its `source_file`; nullable refs to `blob`, `asset_set`, and the deciding `recognition` row. Entirely separate from Phase 1 `idempotency_receipts` (P1 D-20, 90-day protocol retention); the only link is the API idempotency receipt body carrying `import_session_id`. — **Reversibility:** costly — the per-file grain is what the Mac client, export manifest, inbox, and PORT-02 reimport key off.
- **D-25:** Nine frozen outcome codes: `new_asset | exact_duplicate | alias | variant | incomplete_set | unrecognized | patched | quarantined | failed_safely`. Reason attributes refine, never add codes: `unrecognized{no_reference_installed | no_match | ambiguous | archive_not_opened | signature_mismatch}`; `quarantined{size_over_cap | name_policy_violation | scanner_flagged}`; `failed_safely{io_error | disk_full | hash_mismatch | interrupted | worker_crashed}`. The receipt outcome is **terminal**; installing a DAT later appends a `recognition` row and updates the asset_set's current state, and the receipt view shows "at import: unrecognized · now: recognized". Tests assert codes, never English strings. — **Reversibility:** one-way — codes are published protocol; additive only.
- **D-26:** The inbox holds only items needing a human decision. In: `incomplete_set`, `quarantined`, `patched`, `failed_safely` after retries are exhausted, `unrecognized{ambiguous | signature_mismatch}` or unknown system, the one grouped archives item, ambiguous alias/variant, "confirm system" contradictions. Out: `new_asset`, `exact_duplicate`, clean alias/variant, `unrecognized{no_reference_installed | no_match}` — these stay in the library with a quiet "Not yet identified" badge and a single dismissible library hint "Install a reference pack to identify games". **Owner ruling:** library badge over a per-session inbox item — the first adopter sees their library, not 312 chores. Evidence card: full SHA-256 (prefix + copy), exact size, format + magic, header fields for validated formats only, member list with missing members highlighted, source path labelled as a client claim, plain-language reason, expert disclosure. Never: illegal, bad, corrupt-as-verdict, disposable, virus.
- **D-27:** Resolutions are small, audited, reversible commands (`AuditLog` entry each; all but retry undoable). **Correct system/metadata** = insert `recognition_overrides{source: user}` (always wins, never deletes machine rows), re-derive title. **Attach missing companion** = bind an existing user-owned blob or open a new import bound to `{asset_set, role, ordinal}`. **Retain as custom content** = `declared_by_user`, releases policy-quarantined bytes as opaque only. **Exclude** = `excluded_at` + catalogue tombstone; bytes kept; restorable from an "Excluded" filter; the inbox shows "N GB held by excluded items". **Retry safe processing** = re-enqueue inspection/recognition, never re-copy. No byte deletion anywhere in Phase 2; physical reclaim is a Phase 5 sudo-gated storage action beside the backup story. **Owner ruling:** no reclaim path in Phase 2.
- **D-28:** Quarantine is a processing state, not a second store: same CAS, `blob.scan_state = quarantined` + reason code; never inspected, downloaded, or exported-as-playable until released; the machine verdict is shared, the release decision is per user (on source_file/asset_set). Triggers are **policy** failures only (size over cap, name policy, future scanner) — signature mismatch and archives route to Needs Attention as `unrecognized`, not quarantine. Indefinite retention; inbox shows storage held. Actions: retry, retain as custom, exclude.
- **D-29:** "Failed safely" is a guarantee with five classes (D-25). Failure before commit deletes the temp; no partial blob is ever visible; the source is untouched; the receipt is retryable. Disk-full pauses the session with one banner. Counts, never toasts; a boot sweeper clears orphaned temps.
- **D-30:** Journal and API mapping: import sessions and exports → `job` (payload: state, counts by outcome, `attention_count`, coalesced per D-09); asset sets → `catalogue` (D-23). Receipts and the inbox are cursor-paginated REST only: `GET /api/v1/import-sessions/:id/receipts`, `GET /api/v1/attention`, `POST /api/v1/attention/:id/resolve` (with `Idempotency-Key`). — **Reversibility:** costly — client sync engines build on it; moving receipts into the journal later is additive.
- **D-31:** Inbox ergonomics: group by reason, filter by session; bulk actions only where no per-item input is needed (Exclude, Retain, Retry, Assign system). No aging/auto-purge. Neutral navigation count only when > 0. Plain `<table>` + native checkboxes, `role="toolbar"` bulk bar, polite `aria-live` counts, dialogs naming effect + count. Undo lives in the Excluded filter, not transient toasts.
- **D-32:** Microcopy keyed off codes (see `<specifics>` for the table); "Copy into my library" is the primary import action (EXPERIENCE-ETHOS).

### Export and Reimport Identity (PORT-02)

- **D-33:** Export is server-side into an operator-mounted directory (`PLAYSTEAD_EXPORT_PATH`, default `/app/exports`; compose bind-mounts `./exports`), run as an Oban job; the target name is a single sanitized path component under that root, never a free-form absolute path. The identical manifest is served by `GET /api/v1/exports/:id/manifest`, and blobs by `GET /api/v1/blobs/:sha256` (ETag = sha256; Range supported only as far as needed to prove the API-written folder is byte-identical to the server-written one — resumable-range semantics are proven in Phase 3 CACH-01). A contract test writes the folder from the API alone and asserts byte-identity. No browser zip in Phase 2. — **Reversibility:** reversible for the surface; manifest-as-API-resource is one-way once clients consume it.
- **D-34:** BagIt (RFC 8493) layout: `<target>/bagit.txt`, `bag-info.txt`, `manifest-sha256.txt` (GNU `sha256sum -c` line format), `tagmanifest-sha256.txt`, `README.txt`, `playstead-manifest.json`, and `data/<system-slug>/<set folder>/<member files>`. Set folder = sanitized display title, with a ` [uuid8]` suffix only on NFC+case-fold collision within a system; member filenames = recorded original basenames (CUE/GDI/M3U reference them — renaming breaks sets), sanitized only when cross-platform-unsafe with both `original_name` and `exported_as` recorded; NFC written, NFC+case-fold compared, 255-byte name floor; fully sorted; the layout is a pure function of library state. Whole-library export places incomplete/unrecognized/custom sets under their system or `_unsorted/`, quarantined blobs under `_quarantined/`, each with `status` in its sidecar; only user-excluded items are opt-in. **Owner rulings:** BagIt-compliant over a flat tree; include quarantined/unrecognized by default. — **Reversibility:** costly — PORT-01 and user muscle memory depend on it.
- **D-35:** Sidecars: root `playstead-manifest.json` (schema id `playstead-export/1`, canonical JSON, no timestamps — volatile facts live in `bag-info.txt`) and per-set `playstead-set.json` (UUID, `member_fingerprint`, system, title, status, members with path/sha256/size/role/ordinal/required, provenance, recognition evidence). Additive within a major; unknown major ⇒ sidecar ignored and the folder imports as plain files. — **Reversibility:** one-way for the schema id and versioning rule; fields stay additive.
- **D-36:** Write-then-verify: each file is written to a `.playstead-tmp-*` sibling, fsynced, renamed, directory synced; then a second pass re-opens and re-hashes every payload and tag file against the DB. The `exports` record moves `writing → verifying → verified | verification_failed` naming every mismatch. Manifest integrity = tagmanifest; no signing in v1. The target must be empty or carry this export's own `.playstead-export.json` marker; resume re-hashes and skips matches, rewrites its own mismatches, refuses to touch any file it did not write, and never deletes. "Verify again" re-runs on any past export.
- **D-37:** Reimport identity is hybrid, hash-set first. New natural key `member_fingerprint` = sha256 over the canonical sorted list of `(role, sha256)` member pairs, `unique (user_id, member_fingerprint)`. Fingerprint matches an existing set ⇒ `alias` (zero new blobs, zero new sets, N new `source_file` rows; UUID agreement recorded, disagreement logged as evidence). Sidecar UUID exists in this tenant but bytes differ ⇒ never reattach: `incomplete_set` if a strict subset, else a new set flagged variant/patched with "derived from export of <title>" evidence. UUID unknown everywhere ⇒ create the set **reusing the sidecar UUID** (well-formed, globally unused; it never authorizes anything) so wipe → reimport restores identical identifiers; owned by another user or malformed ⇒ mint a fresh UUIDv7 and record `claimed_uuid` in provenance. Missing/tampered sidecar ⇒ plain folder import with IMPT-04 grouping rules. **Owner ruling:** reuse the UUID when globally unused. Round-trip assertions are in `<specifics>`. — **Reversibility:** one-way — the fingerprint definition is the dedupe identity every future import and client relies on.
- **D-38:** Export scope = one set, a selection, or the whole library, through one `exports` row + `Playstead.Export.Worker` sharing the import job model (D-05/D-06: per-member checkpoint rows, control checked between members, resumable by re-enqueue).
- **D-39:** Reserved now for Phase 4 (PORT-01) and the Mac writer: schema id + additive rule; `sets[]` entries carry `kind: "asset_set"`; the root manifest reserves `saves[]`; every set folder reserves a `saves/` subfolder (a member literally named `saves` is renamed by the sanitize rule); role and status are open string vocabularies (the fingerprint uses only `(role, sha256)`); the three API endpoints in D-33; a published `BagIt-Profile-Identifier` URI. Nothing else is frozen. — **Reversibility:** one-way for the reserved names, schema id, and endpoints.
- **D-40:** Vocabulary: "Export — your games as ordinary files". Never "backup" or "safe"; README and receipt say "a copy on the same disk is not a backup". Durable `exports` row: scope, target path, set/file counts, bytes, status, per-file verification result, schema id, generator version, started/finished, `last_verified_at`; surfaced in the job console with the same receipt shape as imports. Verification wording: "Every file was read back and matched its recorded SHA-256" / "3 files did not match; nothing was deleted".

### Claude's Discretion

- Exact table/column names, Ecto schema layout, migration ordering (forward-only, backward-compatible per P1 D-17), and LiveView component structure — follow idiomatic Phoenix 1.8 and the decisions above.
- Chunk size tuning, `Task.async_stream` timeouts, Oban Lifeline `rescue_after`, PubSub topic naming.
- `system-slug` display names for the seven ids, `_unsorted`/`_quarantined` folder names, and the import/inbox/export console information architecture — a UI-SPEC pass should refine these LiveView surfaces.
- Whether `precheck` accepts a batch of hashes or one per call.
- Exact No-Intro filename grammar coverage beyond the documented tag groups.
- The BagIt profile JSON contents and README.txt prose (within D-40's vocabulary rules).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project foundation
- `.planning/PROJECT.md` — Constraints (content posture, data ownership, reliability, security), priority order (data safety > reliable play/saves > clarity/low-admin > performance > delight > breadth), Key Decisions (managed copy, immutable bytes vs mutable saves), Project DNA.
- `.planning/REQUIREMENTS.md` — IMPT-01–06 and PORT-02 verbatim; v2 exclusions TRAN-01 / IMPT-07; PORT-01 (Phase 4) and CACH-01 (Phase 3) boundaries.
- `.planning/ROADMAP.md` §Phase 2 — goal, five success criteria, and the archive-security gate flag.
- `.planning/phases/01-private-custody-and-durable-protocol/01-CONTEXT.md` — P1 D-01 (household-ready scopes), D-17 (migration ratchet), D-18–D-22 (versioning, capability negotiation, idempotency, change journal/snapshot with frozen entity kinds, RFC 9457 codes). Phase 2 builds on these and may not reshape them.

### Discovery corpus (design authority)
- `.planning/discovery/TECHNICAL-RISKS.md` — three-layer identity model; content model table (blob / source_file / asset_set / recognition / bios_asset); import/dedupe/quarantine/export semantics table; "Ordinary-folder export guarantee"; threat table (parser exploit, zip bomb, traversal/symlink, storage loss, confidentiality); DAT licensing decision.
- `.planning/discovery/EXPERIENCE-ETHOS.md` §Import — "Copy into my library", receipt outcomes, Needs Attention inbox, quiet-by-default, humane exceptions.

### Phase 2 discussion research (option tables, adversarial passes, prior art, sources)
- `.planning/phases/02-explainable-import-and-exact-export/discussion-research/A-import-surfaces-and-staging.md`
- `.planning/phases/02-explainable-import-and-exact-export/discussion-research/B-formats-and-recognition.md`
- `.planning/phases/02-explainable-import-and-exact-export/discussion-research/C-receipts-and-needs-attention.md`
- `.planning/phases/02-explainable-import-and-exact-export/discussion-research/E-export-and-reimport-identity.md`

### External standards adopted by decision
- RFC 8493 (BagIt) — export container layout, `manifest-sha256.txt`/`tagmanifest-sha256.txt`, `bag-info.txt`.
- RFC 9530 (Digest Fields) — `Repr-Digest: sha-256=…` on API uploads.
- RFC 9457 (Problem Details) and IETF `draft-ietf-httpapi-idempotency-key-header` — inherited from Phase 1 for every new endpoint.
- Logiqx XML DAT format (No-Intro/Redump) — admin-supplied reference packs.
- No-Intro naming convention — filename parse for display titles and tags.
- GBATEK (GBA header), Pan Docs (GB/GBC header), nesdev iNES/NES 2.0, SNES internal header, Mega Drive `SEGA` header, CUE sheet grammar — Tier A/B validators (URLs in research B §Sources).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Playstead.Idempotency` + `idempotency_receipts` (P1 D-20): every new mutation endpoint (uploads, resolve, export create) reuses the plug and receipt-in-transaction pattern; the API upload fingerprint rule (D-02) is a specialisation, not a new mechanism.
- `Playstead.Sync.ChangeJournal` / `EntityKind` / `Snapshot` / `Compaction`: Phase 2 attaches producers for the already-registered `catalogue` and `job` kinds and adds snapshot branches; the write-side advisory-lock fencing is reused as-is.
- `Playstead.AuditLog`: every Needs Attention resolution, DAT-pack import, and export writes an entry.
- `Playstead.RateLimiter` (Hammer): per-device upload concurrency and per-IP staging-action limits.
- `Playstead.Readiness` already probes `PLAYSTEAD_BLOB_PATH` writability; extend with `PLAYSTEAD_INBOX_PATH` (readable) and `PLAYSTEAD_EXPORT_PATH` (writable) checks and `free_bytes/0`.
- `PlaysteadWeb.Problem` / `error_codes.ex`: register the D-10 codes in the existing stable registry.
- `Playstead.CommandId` (UUIDv7): command ids in upload paths and session ids.
- Oban 2.24 (OSS) is installed with existing workers (`Pairing.ExpireStaleRequestsWorker`, `Idempotency.PruneExpiredWorker`, `Sync.CompactionWorker`) as idiom references.

### Established Patterns
- Phoenix 1.8 scopes: every new schema carries `user_id` and every context function takes the scope (P1 D-01); blobs are the deliberate exception (D-13).
- Contexts own transactions; LiveView calls the same context functions as the API controllers and is never the protocol.
- Contract tests assert problem+json codes and journal convergence, never English strings.
- Migrations are forward-only and backward-compatible (P1 D-17).
- Release runs as `nobody`; new volume mount points must be pre-created and chowned in the image (Phase 1 gap 01-08 lesson) — applies to `/app/inbox` (read) and `/app/exports` (write); `scripts/compose-smoke.sh` should assert both.

### Integration Points
- `playstead-server/lib/playstead_web/router.ex`: new `/api/v1/imports/*`, `/api/v1/import-sessions/*`, `/api/v1/attention/*`, `/api/v1/exports/*`, `/api/v1/blobs/:sha256` routes under the existing `:device_auth` + idempotency pipelines; new LiveViews for import, inbox, sessions/jobs, reference packs, and exports under `:require_authenticated_user`.
- `docker-compose.yml` / `.env.example` / `docs/DEPLOY.md`: `./inbox:/app/inbox:ro`, `./exports:/app/exports`, `PLAYSTEAD_INBOX_PATH`, `PLAYSTEAD_EXPORT_PATH`, `PLAYSTEAD_IMPORT_CONCURRENCY`, `PLAYSTEAD_IMPORT_VERIFY`, upload ceilings.
- `Playstead.Sync.Snapshot`: add `catalogue` and `job` branches inside the same consistent transaction.
- Phase 3 consumes: `catalogue` payload (D-23), `precheck` + upload PUT (D-01/D-02), `blobs/:sha256` GET (D-33), attention REST (D-30), export manifest (D-35).

</code_context>

<specifics>
## Specific Ideas

### Receipt microcopy (keyed off codes; tests assert codes only)

| Code | Label | One-line explanation |
|---|---|---|
| `new_asset` | Added to your library | A verified copy is now stored by your server. |
| `exact_duplicate` | Already in your library | These exact bytes were imported before. We kept the new file name as a note. |
| `alias` | Another copy of a game you have | Same bytes, different name. Both names are kept. |
| `variant` | A different version of a game you have | Kept alongside the version you already had. |
| `incomplete_set` | Some parts are missing | This game needs more than one file. We kept what you gave us. |
| `unrecognized` | Not yet identified | Stored safely. Playstead couldn't match it to a reference yet. |
| `patched` | Looks modified | Doesn't match the reference exactly. Kept as-is. |
| `quarantined` | Set aside for review | We stored it but didn't process it: <reason>. |
| `failed_safely` | Couldn't finish — nothing was changed | Your original file is untouched. You can try again. |

Import primary action: **Copy into my library** — "Your original file stays where it is. A verified copy will be stored by your server and available to your devices."

### PORT-02 round-trip assertions (contract tests)
1. Export one set → wipe library → reimport ⇒ identical set graph (UUID, members, roles, ordinals, required flags) and zero new blobs.
2. Export → reimport into the same library ⇒ zero new logical records, N new `source_file` alias rows.
3. Export via API-only writer ⇒ byte-identical folder to the server-written export (same layout, same `manifest-sha256.txt`).
4. Reimport with one member deleted from the folder ⇒ `incomplete_set` with the manifest-declared missing member named; no reattachment to the original set.
5. Reimport with a tampered sidecar UUID (another tenant's / malformed) ⇒ fresh UUIDv7, `claimed_uuid` recorded, bytes deduped by fingerprint.

### Archive-security gate — acceptance criteria (deferred spike; must pass before any inspection ships)
- Corpus: path traversal (`../`, absolute, Windows drive, NUL), symlink/hardlink entries, nested archives ≥5 deep, zip bombs (42.zip-style and overlapping-entry), 100k-entry archive, declared-size lies, CRC-mismatch entries, encrypted entries, polyglots (valid ROM header + trailing archive).
- Limits: wall-clock, memory (separate BEAM node or OS process with rlimits — not a bare `Task`), recursion 0, entry count, per-entry and total expanded size, expansion ratio; runs as `nobody` in a tmpfs.
- Every fixture must produce a receipt without touching the blob store; adversarial fixtures run in CI (QUAL-02).

### Prior art adopted
- BagIt container + GNU `sha256sum -c` lines; OCFL canonical-JSON/fixity discipline; git-annex "never touch foreign files"; igir/RomVault system-folder + game-subfolder convention; Immich duplicate-review calm; Jupyter/Immich lessons on quiet library states; OWASP file-upload guidance (generated storage keys, no execution, magic over extension).

</specifics>

<deferred>
## Deferred Ideas

### Import / staging
- Inbox auto-watch (inotify/polling) with "file stable for N seconds" debounce — v2.
- tus / S3 multipart resumable upload with `Upload-Expires` sweeper — TRAN-01 (v2), keyed to a `transfer` capability.
- Periodic blob scrub / "Verify library" (re-hash, adopt orphans, report bit-rot) — Phase 5 (OPER-03/PORT-03).
- Per-user inbox sub-folders for household mode — v2.
- Browser folder pick (`webkitdirectory`) for small folders in LiveView.
- Container memory limits in compose once import workers exist — Phase 5 docs.

### Formats / recognition
- Archive-security gate spike, then inspected archives as `container` members of derived asset sets.
- M3U multi-disc and CHD parent/child proof; sector-level PS1 BIN reading (SYSTEM.CNF serial) after the parser-fuzz gate.
- ClrMamePro non-XML `.dat` and TOSEC naming parser; `.smd` interleaved MD, Lynx/A7800 headers, N64 byte-order variants.
- Online providers (Hasheous, libretro-database fetch) with per-provider consent — META-01 (v2).
- BIOS validation reusing the DAT hash-match primitive — Phase 3 (PLAY-03).
- RetroAchievements-compatible hash as a `blob_fingerprints.kind` — ACHV-01 (v2).
- Derived asset sets from BPS/UPS patches (explicit client action, never auto-apply); "possible overdump" verdicts once a reference size is known.
- Sharing reference packs across household users.

### Receipts / inbox
- Physical reclaim "Remove from server storage" with cross-user refcount, sudo, and backup-freshness check — Phase 5.
- Auto-resolution rules ("always retain .txt as custom") — v2 curation.
- Malware-scanner adapter (`scanner_flagged`) — hosted-tier prerequisite.
- Mac client inbox UI and receipt push — Phase 3+ (API is ready).
- Bulk "attach from this folder" companion binding; receipt export as CSV; inspector re-run on upgrade ("N items can be re-checked") — Phase 5 preflight.

### Export
- Saves in the export (`saves/` per set) and the Mac-side export writer — Phase 4 (PORT-01).
- Signed manifests — after a key-management story exists.
- Browser zip download for small sets — after the archive gate, convenience only.
- Scheduled re-verification of exports — Phase 5.
- Export to S3-compatible destinations; reference-in-place mode reusing the bag layout — v2.
- igir-style tokenised output paths as user-selectable layouts — only if demanded (breaks determinism promise).

</deferred>

---

*Phase: 02-explainable-import-and-exact-export*
*Context gathered: 2026-08-28*
