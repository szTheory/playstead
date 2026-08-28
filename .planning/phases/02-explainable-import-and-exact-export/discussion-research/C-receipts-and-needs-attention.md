# Phase 2 Research — Area C: Receipts & Needs Attention

Researcher: advisor-researcher (area C). Date: 2026-08-28.
Scope: IMPT-03 (durable receipt), IMPT-06 (Needs Attention resolutions), with the pieces of IMPT-02/04/05 and PORT-02 they touch. Builds on Phase 1 D-01 (user_id everywhere), D-20 (idempotency receipts, 90-day retention), D-21 (change journal, frozen entity kinds), D-22 (problem+json stable codes), and the locked Phase 2 decisions in the brief.

---

## One-shot recommendations (summary)

- **D-C1 (draft): Two tables, one vocabulary.** `import_sessions` (one per user-initiated import, single file or staged collection; carries rolled-up counts by outcome and lifecycle state) and `import_receipts` (exactly one per submitted source file, immutable, indefinite retention, user_id-scoped). A receipt always references its `source_file`; nullable references to `blob` (when bytes landed), `asset_set` (when a set was created or joined), and the `recognition` row that determined the outcome. Import receipts are library records and are a separate table from Phase 1's protocol-level `idempotency_receipts`; the only link is that the API's idempotency receipt body contains the `import_session_id`. — Reversibility: costly — the per-file receipt is the unit the Mac client, export manifest, and inbox all key off; collapsing to session-only later would lose the provenance grain PORT-02 needs.
- **D-C2 (draft): Nine frozen outcome codes, receipt outcome is terminal, recognition is appended.** `new_asset | exact_duplicate | alias | variant | incomplete_set | unrecognized | patched | quarantined | failed_safely`. `alias` and `variant` are two codes (different bytes → same release vs different bytes → different release of the same title) because the user copy and the inbox routing differ. "Supported format, no reference match" is `unrecognized` with a recognition attribute `reason ∈ {no_reference_installed, no_match, ambiguous}` — the attribute drives inbox routing, the code drives the receipt. A receipt never changes after commit; installing a DAT pack later appends a new `recognition` row and the asset_set's *current* recognition state moves, while the receipt shows "at import: unrecognized · now: recognized (No-Intro 2026-08-01)". — Reversibility: one-way — codes are published protocol (problem+json-style registry); adding is additive, renaming is a v2 break.
- **D-C3 (draft): The inbox holds only items that need a human decision.** Lands in Needs Attention: `incomplete_set`, `quarantined`, `patched`, `failed_safely` after bounded retries, `unrecognized` only when `reason = ambiguous` or the system family could not be determined, and any `alias/variant` where the matcher flagged ambiguity. Does NOT land: `new_asset`, `exact_duplicate`, clean `alias/variant`, and `unrecognized{no_reference_installed | no_match}` — those go straight into the library carrying a quiet "Not yet identified" state. Evidence card: full SHA-256 (copyable, shown as 12-char prefix + reveal), exact byte size + human size, detected format + magic-byte evidence, header fields only for magic-validated formats, ordered member list with missing members highlighted, source path *as reported by the client* (labelled as a claim), plain-language reason, expert diagnostics behind a disclosure. Never shown or implied: illegal, bad, corrupt-as-judgement, disposable, virus. — Reversibility: reversible — routing rules are server config + copy.
- **D-C4 (draft): Resolutions are small, audited, reversible commands; "Exclude" is soft.** (1) *Correct system or metadata* inserts a `recognition` row with `source: user_override` (confidence 1.0, never deletes machine rows), re-derives display title, clears the attention flag. (2) *Attach missing companion* binds an existing user-owned blob/source_file to the manifest member slot, or opens a new import bound to `{asset_set_id, member_role, ordinal}`; the set becomes complete when every required member verifies. (3) *Retain as custom content* sets `asset_set.declared_by_user = true`, `recognition_state = custom`, and for quarantined-for-policy items releases the opaque blob for download/export (never for inspection). (4) *Exclude* sets `excluded_at` on the asset_set (or on the source_file/quarantine item when no set exists); bytes stay in the CAS; hidden from library, catalogue snapshot emits a tombstone; reversible from an "Excluded" filter in the inbox; no byte deletion anywhere in Phase 2 — reclaim ("Remove from server storage") is a documented Phase 5 storage action with sudo + confirmation. (5) *Retry safe processing* re-enqueues inspection/recognition for the existing blob (or, for `failed_safely`, re-requests the bytes from the client); never re-copies from a server path. Every resolution writes an `AuditLog` entry `attention_resolved` with the resolution code and the prior state, and all except retry are undoable from the item's history. — Reversibility: reversible (that is the point).
- **D-C5 (draft): Quarantine is a processing state, not a second store.** Quarantined bytes live in the same CAS (`objects/sha256/…`) with `blob.scan_state = quarantined` and a `quarantine_reason` code; they are never inspected, downloaded, exported, or counted as library content until released. Triggers (frozen codes): `magic_mismatch`, `size_over_cap`, `parse_failure`, `archive_preflight_refused`, `name_policy_violation`, `scanner_flagged` (future). Retention: indefinite until the user acts; the inbox shows the storage held. Next actions: retry (after upgrade/new inspector), retain as custom (opaque release; blocked for `archive_preflight_refused` until the archive-security gate passes), exclude. — Reversibility: reversible — flag semantics; a separate namespace could be introduced behind the storage adapter later without changing receipts.
- **D-C6 (draft): "Failed safely" is a guarantee with five named classes.** Write path: stream → `tmp/<uuid>` on the same filesystem as `objects/` → fsync → verify streaming SHA-256 against a re-read → hard-link/rename into `objects/sha256/ab/<hash>` → DB transaction (blob, source_file, receipt, journal entry, next Oban job) → commit. Any failure before commit deletes the temp file and the receipt records `failed_safely{class ∈ io_error | disk_full | hash_mismatch | interrupted | worker_crashed}` with a `retryable` flag. Disk-full pauses the session (one banner, not one toast per file). Transient classes get bounded Oban retries (3, backoff) *before* a receipt is finalized; only exhausted retries create an inbox item. A boot-time sweeper removes orphaned `tmp/` files older than the longest job timeout. Surfaces: session counts and a single per-session status line; never per-file toasts. — Reversibility: reversible.
- **D-C7 (draft): Sessions are `job`, asset_sets are `catalogue`, receipts are REST-only.** Change journal: `job` entity = import_session (payload: state, counts by outcome, `attention_count`, `updated_seq`); `catalogue` entity = asset_set (payload includes `recognition_state`, `attention: {reason} | null`, `excluded_at`). Receipts are not journaled per row (a 40k-file collection would flood the feed); they are paginated REST under `/api/v1/import-sessions/:id/receipts` and `/api/v1/attention` for the inbox, both cursor-paginated. Snapshot materializes `catalogue` (non-excluded asset_sets) and `job` (sessions not in a terminal state older than the compaction horizon). — Reversibility: costly — client sync engines build on it; additive fields are fine, moving receipts into the journal later is additive too.
- **D-C8 (draft): Group by reason, filter by session, bulk only where the action needs no per-item input.** Default view: reason groups with counts; a session chip filters. Bulk actions: Exclude, Retain as custom, Retry, and Assign system (when all selected share `unrecognized/ambiguous`); Attach companion and full metadata correction are per-item. No aging or auto-purge; items stay until resolved. Nav shows a neutral count badge only when > 0 (no red). Semantics: a `table` with a header select-all checkbox, per-row checkbox, row action `menu` button; bulk toolbar is `role=toolbar` that appears when selection > 0; count updates announced via a polite `aria-live` region; confirmation dialogs are `role=dialog` with focus trapped and the primary action named after the effect ("Exclude 40 files"). — Reversibility: reversible.
- **D-C9 (draft): Adopt the microcopy table in C9 as the canonical strings**, keyed off outcome/resolution codes so contract tests assert codes and copy lives in one place. Headline strings: "Added to your library", "Already in your library", "Another copy of a game you have", "A different version of a game you have", "Some parts are missing", "Not yet identified", "Looks modified", "Set aside for review", "Couldn't finish — nothing was changed". — Reversibility: reversible.
- **D-C10 (draft): Physical bytes are global, everything the user sees is user-scoped.** `blobs` (physical CAS rows, keyed by sha256) carry no `user_id`; `source_files`, `import_sessions`, `import_receipts`, `asset_sets`, `attention_items`, `recognition` overrides all carry `user_id`. "Exact duplicate" is evaluated per user (does *this user* already have a source_file for this sha256), so a duplicate for A is `new_asset` for B while the disk stores one copy; the same-bytes/other-user case is never disclosed. Exclude/reclaim semantics are per user; a blob is physically reclaimable only when no user references it. — Reversibility: costly — splitting physical vs logical ownership is a schema shape; going the other way (per-user physical copies) later means re-keying storage.

---

## Detailed analysis

### C1. Receipt granularity & schema

**Lenses**
- *Product/UX*: the first adopter drops one file and expects one answer; later drops a 3,000-file folder and expects one summary with the ability to drill down. Both shapes are required by REQUIREMENTS (IMPT-03 "durable receipt", IMPT-05 "reconcile without duplicating"). A session-only receipt cannot answer "what happened to `Final Fantasy III (USA).sfc`?"; a per-file-only receipt cannot answer "did my folder import finish?".
- *Data model / PORT-02*: reimport must re-hash every byte and treat the sidecar as optimization. The natural unit of "we saw this exact file from this source path" is the `source_file` row; the receipt is the outcome attached to that observation. Keying receipts by source_file gives PORT-02 a deterministic "0 new, N exact duplicates" reimport receipt for free.
- *Elixir/Ecto/Oban*: two schemas, `Playstead.Imports.Session` and `Playstead.Imports.Receipt`, written in the same `Ecto.Multi` as the blob/source_file effect and the Oban job for the next stage (Oban.insert/3 inside a Multi is transactional and supports `unique`). Counters on the session are derived (`COUNT … GROUP BY outcome`) or maintained with an `UPDATE … SET counts = counts || …` inside the same transaction — derived is simpler and correct; cache only if the console page proves slow.
- *Durability*: receipt written before visibility, in the effect's transaction (same discipline as `Playstead.Idempotency.execute/4` and `ChangeJournal.append/4`). A crash between file rename and commit leaves an orphaned CAS object with no rows — a boot sweeper reconciles (see C6); no receipt is ever "half written".
- *Security*: a receipt must never carry the plaintext bytes, the server-side temp path, or the storage key in the API payload beyond the sha256; source path is user-supplied and rendered as a claim.
- *Protocol / Phase 3*: the Mac client will POST an import intent (IMPT-01 preflight) and then stream bytes; the idempotency receipt for that POST must return the same `import_session_id` on retry. That is the *only* touchpoint between D-20 receipts and import receipts.
- *SRE*: indefinite retention, small rows (~300 B); 100k receipts is trivial in Postgres. Index `(user_id, session_id)`, `(user_id, outcome)`, `(user_id, source_file_id)`.
- *Preservation domain*: RomVault/igir report per input file with a status (igir: FOUND/MISSING/DUPLICATE/UNUSED/DELETED); ClrMamePro's scan results are per set + per rom. Per-file grain is the norm; session summaries are an add-on.

**Prior art**
- igir writes a CSV report with one row per file and a Status column (FOUND, MISSING, DUPLICATE, UNUSED, DELETED) — per-file grain with a fixed vocabulary, filterable. https://igir.io/output/reporting/
- restic distinguishes the *run* outcome (exit 0/1/3) from per-file read errors, and still creates the snapshot minus unreadable files — exactly the session-vs-file split. https://restic.readthedocs.io/en/stable/040_backup.html
- Immich records per-asset duplicate groups and lets users resolve per group; its "Deduplicate All" is a session-level action over per-asset facts. https://docs.immich.app/features/duplicates-utility/
- Phase 1 `Playstead.Idempotency` — receipts are keyed `(device_id, idempotency_key)`, 90-day pruning, response body cached; this is transport replay, not a library record.

**Options**

| Option | Pros | Cons / footguns | Who it hurts |
|---|---|---|---|
| A. Per-source-file receipt only | Simplest schema; PORT-02 reimport falls out | No durable "did my folder finish?"; pause/resume state has nowhere to live; counts need a GROUP BY every render | Large-collection users, Phase 3 job view |
| B. Per-session receipt only (JSON blob of outcomes) | One row per import; easy summary | Un-indexable per-file lookup; JSON grows unbounded; a 40k-file session row is a hot-row contention point for Oban workers; reimport can't cheaply say "already have it" | Everyone past ~500 files |
| C. Both: session row + per-file receipt rows (recommended) | Right grain for both questions; session is the `job` entity for the journal; receipts join to source_file/blob/asset_set/recognition | Two tables; need to define which is authoritative for counts (receipts are) | Nobody materially |
| D. Reuse `idempotency_receipts` with a longer TTL | No new table | Conflates transport replay with library history; device-scoped not user-scoped; retention conflict with D-20; LiveView imports have no device | Household, self-hoster backups |

**Adversarial pass on C**
- *Crash mid-write*: receipt is in the same transaction as blob/source_file; either all exist or none. The stray CAS object is reconciled by sweeper (C6).
- *Malicious input*: source path and filename are strings in `source_file`, length-capped and control-char-stripped at the boundary; receipt payload contains only codes and ids.
- *Huge collection*: 40k receipt rows per session; counts via indexed GROUP BY on `(session_id, outcome)`; LiveView uses streams + pagination, never loads all rows.
- *Future Mac client*: client keeps its own `command_id` (UUIDv7) as the session's natural key (`on_conflict: :nothing`), so an outbox replay after receipt expiry converges (D-20b).
- *Future S3*: receipts reference blob ids, not storage keys. Adapter-neutral.
- *Household*: `user_id` on both tables from day 1 (D-01).
- *Export/reimport*: reimport session's receipts are all `exact_duplicate` with `source_file.origin = export_reimport` and `sidecar_manifest_id` set; contract test asserts 0 new asset_sets.

**Recommendation**: D-C1 above. Builds on D-01, D-20b, D-21, and the locked "receipts written in the same transaction as effects". Claude's discretion: exact column names, whether counts are cached.

---

### C2. Outcome taxonomy

**Lenses**
- *Preservation domain*: DAT tooling vocabulary is about *set completeness against a reference* (Correct/Missing/Unknown/UnNeeded in RomVault; FOUND/MISSING/DUPLICATE/UNUSED in igir). No-Intro naming carries `(Rev 1)`, `(Beta)`, region, and `[b]`/`[h]`/`[t]` style flags in older TOSEC/GoodTools DATs for bad/hacked/trained dumps. So: "alias" and "variant" are different relationships in the reference world — a re-dump or headered/unheadered copy of the *same* release vs a *different* release of the same title. "Patched" in v1 can only be detected via reference flags or a user-provided patch base (no auto-patching); most modified ROMs will simply be `unrecognized`.
- *Product/UX*: the code must map to one sentence the user understands. Merging alias+variant produces "related to something you have", which forces a second question the UI must answer anyway. Keep them separate.
- *Protocol*: codes are strings, additive-only; clients key copy off codes (D-22 discipline). "Terminal receipt + appended recognition" avoids clients needing to re-download receipts when a DAT pack is installed; only the `catalogue` entity changes.
- *Data model*: `recognition` rows are evidence with `{source, version, hash_kind, hash, confidence, result, user_override}`. `asset_set.current_recognition_id` points at the winning row (user override always wins).
- *Security*: the recognition attribute `no_reference_installed` must not be an admission gate (locked: "recognition is not an admission control gate").
- *Distributed*: recognition may complete after the receipt when inspection is asynchronous; the receipt's outcome is fixed at "the point the bytes were committed and the first recognition pass finished" — a single Oban pipeline per file: `store → inspect → recognize → finalize receipt`. The receipt row exists from `store` with `outcome = pending` and is finalized once; `pending` is an internal state and is never a published code (API shows the session as `in_progress` and omits pending receipts or lists them under `processing`).

**Prior art**: igir statuses (link above); RomVault status vocabulary (Correct, Missing, Unknown, UnNeeded, Corrupt, InToSort) https://wiki.romvault.com/doku.php?id=error_messages ; RetroArch's strict scan silently omits unmatched files unless "Scan Without Core Match" — the anti-pattern the ethos forbids https://docs.libretro.com/guides/roms-playlists-thumbnails/ ; RomM keeps unmatched ROMs visible and offers an "Unmatched" rescan after adding providers — the model for re-evaluable recognition https://docs.romm.app/latest/troubleshooting/scanning/ .

**Options**

| Option | Pros | Cons | Who it hurts |
|---|---|---|---|
| A. 7 codes exactly as IMPT-03 phrases them (alias_or_variant, unrecognized_or_patched merged) | Matches requirement text | Every consumer must split them again for copy; "patched" and "unrecognized" have different inbox routing | UI, clients |
| B. 9 codes (recommended): split alias/variant and unrecognized/patched | One code → one sentence → one routing rule | Two more strings to document | Nobody |
| C. Outcome as (code, relation, reason) triple | Maximal expressiveness | Clients must implement the matrix; contract tests explode | Phase 3 client |
| D. Mutable receipt outcome (update when recognition improves) | "Current truth" in one place | Destroys "what happened at import" provenance; journal churn; contradicts append-only evidence rule | Auditability, PORT-02 |

**Adversarial pass on B**
- *DAT installed later*: new `recognition` row appended; `catalogue` journal upsert; receipt untouched; inbox item (if any) auto-resolves when ambiguity clears — write an audit entry `attention_auto_resolved`.
- *Same sha256 submitted twice in one session* (folder with two identical files): second is `exact_duplicate` referencing the first's blob; both receipts exist.
- *Alias vs exact duplicate confusion*: alias is *different* bytes. Same bytes is always `exact_duplicate`, even under a different name; the new filename is preserved as a second `source_file`.
- *No reference data at all (v1 default install)*: every recognizable-format file is `unrecognized{no_reference_installed}`. This MUST NOT flood the inbox (see C3); the library shows "Not yet identified" quietly and a one-line settings nudge "Install a reference pack to identify games automatically".
- *Malicious DAT*: DAT text is untrusted; display titles derived from it are sanitized/length-capped; a DAT cannot change outcome codes, only recognition rows.
- *Future S3*: no impact.

**Recommendation**: D-C2. Builds on D-22 (stable code registry pattern), the locked "match is evidence" rule.

---

### C3. Needs Attention inbox contents & evidence

**Lenses**
- *Product/UX (first adopter)*: the inbox must be nearly empty after a normal import. If the default install (no DAT) routes every file to the inbox, the product's first impression is a 3,000-item to-do list — the opposite of "exceptions are part of the happy path".
- *Security*: evidence must not become an exploit surface: header fields are rendered only for formats whose parser passed the gate; magic bytes are shown as hex; filenames are escaped; source paths are truncated with a full-value disclosure.
- *Accessibility*: evidence is a definition list (`dl`) not a table; missing members use text + icon, not color alone.
- *Preservation*: the most useful evidence for a human is the No-Intro-style name candidates with their hashes and what differed (size, CRC). For `incomplete_set`, the CUE's referenced FILE lines vs what was supplied is the evidence.
- *Ops*: diagnostics behind disclosure include Oban job id, attempt count, and the correlation id (D-22), never the server temp path.

**Prior art**: Immich duplicate review shows side-by-side assets with size/EXIF richness and recommends which to keep, but never deletes without user selection https://docs.immich.app/features/duplicates-utility/ ; RomM keeps unmatched visible in the platform view with a Match button https://docs.romm.app/latest/troubleshooting/scanning/ ; Jellyfin's Identify dialog + lock-metadata pattern (and its refresh-overwrites-manual-identify bug, Issue #11773) is the cautionary tale for why user overrides must be a distinct recognition source that always wins https://github.com/jellyfin/jellyfin/issues/11773 ; git-annex moves bad objects to `.git/annex/bad` and reports "verification of content failed" — clear, non-judgemental, recoverable https://git-annex.branchable.com/internals/ ; restic prints a count of read errors and continues https://restic.readthedocs.io/en/stable/040_backup.html .

**Options**

| Option | Pros | Cons | Who it hurts |
|---|---|---|---|
| A. Every non-`new_asset`/`exact_duplicate` outcome goes to the inbox | Simple rule | Floods with `unrecognized` in a no-DAT install; alias/variant need no decision | First adopter |
| B. Decision-required only (recommended) | Inbox stays calm; matches ethos | Needs an explicit routing table and a "Not yet identified" library state | Nobody; requires LIBR-04-style badge in Phase 3 |
| C. Inbox as a filter over receipts (no separate table) | Fewer tables | Attention state must persist across recognition changes and resolutions; receipts are immutable | Implementers |

Routing table (B):

| Outcome / attribute | Inbox? | Reason shown |
|---|---|---|
| new_asset, exact_duplicate | no | — |
| alias, variant (clean) | no | receipt only |
| alias/variant with `ambiguous` | yes | "We found more than one likely match" |
| incomplete_set | yes | "Some parts are missing" |
| unrecognized{no_reference_installed, no_match} with known system | no | library badge "Not yet identified" |
| unrecognized{ambiguous} or system unknown | yes | "We couldn't tell which system this is for" |
| patched | yes | "Looks modified compared with the reference" |
| quarantined | yes | reason-specific |
| failed_safely (retries exhausted) | yes | "Couldn't finish — nothing was changed" |

Evidence card contents: title line (best display title or original filename), outcome badge, plain reason, `dl` with: SHA-256 (12-char prefix, copy full), size (exact bytes + human), format detected (e.g. "GBA ROM (magic 24 FF AE 51)"), header fields for validated formats (internal title, game code, region), members list for sets (role, ordinal, expected name, present/missing, hash if present), source ("Reported by your Mac: /Volumes/…" — claim), imported at, session link, candidates list for ambiguity (name, source/version, hash kind, confidence), disclosure "Details for support" (job id, attempts, correlation id, inspector version).

Never: "illegal", "pirated", "bad dump" (use "does not match the reference"), "corrupt" as a verdict (use "couldn't be read as a <format>"), "unsafe/virus" (use "set aside for review"), "delete" as the suggested default.

**Adversarial pass on B**: a malicious filename with RTL overrides or 4k chars — sanitized and truncated at ingest; a crafted header with script content — rendered as text by HEEx escaping, fields length-capped at inspection; 10k inbox items — paginated stream, grouped counts computed server-side; household — inbox strictly per user_id; export/reimport — reimport of an excluded item is `exact_duplicate` and stays excluded (the exclusion is on the asset_set, and the receipt notes "excluded earlier").

**Recommendation**: D-C3. Builds on ethos principle 5 and LIBR-04's quiet-by-default sibling.

---

### C4. Semantics of the five resolutions

**Lenses**
- *Data safety (priority #1)*: no resolution deletes bytes in Phase 2. "Exclude" hides. Physical reclaim is a separate, sudo-gated storage action that names the exact bytes and their references; it belongs with OPER-03/PORT-03 storage health in Phase 5.
- *Elixir idiom*: each resolution is a function in `Playstead.Imports.Attention` (`correct/3`, `attach/3`, `retain_custom/2`, `exclude/2`, `retry/2`), each an `Ecto.Multi` that writes the effect, the audit entry, the journal entry, and (for retry) the Oban job, then returns the updated item. LiveView and the API call the same functions.
- *Durability*: retry is idempotent via Oban `unique: [keys: [:blob_id, :stage], period: :infinity, states: [:available, :scheduled, :executing, :retryable]]`.
- *Protocol*: resolutions are POSTs under `/api/v1/attention/:id/resolve` with `{resolution, params}`, Idempotency-Key required (D-20a), returning the updated item; problem+json codes `attention_already_resolved`, `companion_hash_mismatch`, `resolution_not_applicable`.
- *Preservation*: "correct system" must not rewrite bytes or rename stored objects; export uses the *expected relative path* recorded on the member, which the correction may update (a display/export concern, not a byte concern).
- *Household*: a companion can only be attached from the same user's blobs.

**Prior art**: Immich trash (soft delete with retention, restore) as the model for exclude; Jellyfin Identify/lock-metadata for override precedence; RomM manual Match for correct-metadata; RomVault "fix" is the anti-model (moves/renames files).

**Options for Exclude** (the contested one)

| Option | Pros | Cons | Who it hurts |
|---|---|---|---|
| A. Soft exclude, bytes retained, no reclaim in Phase 2 (recommended) | Zero data-loss risk; trivially undoable; consistent with "one copy is not a backup" | Disk stays consumed; must show held storage honestly | Self-hoster with tight disk (mitigated by a visible "Excluded, holding 1.2 GB" line and the Phase 5 reclaim path) |
| B. Soft exclude + auto-purge after N days (Immich-style trash) | Reclaims space eventually | A timer that deletes user bytes is the exact thing the ethos rejects; backups may not have run | Anyone with a slow backup cadence |
| C. Hard delete with confirmation | Immediate reclaim | Irreversible; a blob shared with another asset_set/user must be refcounted; export sidecars may reference it | Everyone, priority #1 |

Semantics table:

| Resolution | Effect | Undo |
|---|---|---|
| Correct system or metadata | insert `recognition{source: user_override}`; set `asset_set.system_family`, display title; for `incomplete_set` may also change the manifest template | "Revert to detected" re-points `current_recognition_id` to the best machine row; override row kept with `revoked_at` |
| Attach missing companion | bind blob to `asset_member{role, ordinal}`; verify sha/size against CUE-declared expectations where available; recompute `asset_set.readiness` | "Detach" removes the binding; the blob and its source_file remain |
| Retain as custom content | `declared_by_user = true`, `recognition_state = custom`; for policy quarantine, `scan_state = released_opaque` | "Stop treating as custom" restores prior state; quarantine returns to held if it was released |
| Exclude | `excluded_at = now()`; catalogue tombstone; hidden everywhere except the inbox's "Excluded" filter | "Restore to library" clears `excluded_at`, journal upsert |
| Retry safe processing | enqueue inspect/recognize for the existing blob; for `failed_safely` with no blob, mark session member `awaiting_bytes` and let the client resend | none needed (idempotent) |

Every resolution: `AuditLog.record(user_id, :attention_resolved, %{subject: item_id, resolution:, from:, to:})`; undo writes `:attention_resolution_reverted`. Metadata never includes filenames or hashes (QUAL-03 spirit).

**Adversarial pass**: crash mid-resolution — single transaction; user mistake (excluded the wrong 40) — restore from the Excluded filter, bulk; attach the wrong companion — hash mismatch against the CUE's declared FILE or size expectation is a *warning*, not a block (Redump CUEs don't carry hashes; the user may know better), the binding records `verified_against: none|size|hash`; huge set — attach one at a time or "attach from this folder" bulk in a later phase; future Mac client — same REST commands; household — companion picker scoped by user_id; export/reimport — excluded sets are not exported; a reimport of previously excluded bytes reports `exact_duplicate` + "excluded on <date>".

**Recommendation**: D-C4. Builds on D-01, D-20a, Phase 1 AuditLog append-only rule.

---

### C5. Quarantine

**Lenses**
- *Security*: what quarantine protects is the *server's processing*, not the user's custody. Bytes that have already been streamed to disk under a generated key, never executed, and never parsed are inert. The risk is in inspection (parsers) and in serving (a client that auto-opens). So the flag must gate inspection and serving, not storage location.
- *Storage adapter / S3*: a separate `quarantine/` namespace means two write paths and a move on release; on S3 a move is copy+delete of a multi-GB object. A metadata flag is free on both backends.
- *Ops*: quarantined bytes count toward disk usage; the console must show "Set aside for review: 3 files, 812 MB" so the self-hoster is not surprised.
- *Preservation*: many legitimate dumps have odd sizes or unusual headers; quarantine copy must be "we couldn't safely read this as a GBA ROM", not "this file is dangerous".
- *Threat table (TECHNICAL-RISKS)*: traversal/symlink/nested/bomb are archive-inspection threats; since archives stay opaque until the gate passes, `archive_preflight_refused` in Phase 2 mostly means "declared size or member count over cap in the central directory scan" if even that preflight is enabled — otherwise archives are simply stored opaque and not quarantined at all.

**Prior art**: ClamAV `--move` quarantine + 30-day retention is common in ops guides but is a scanner convention, not a library convention; git-annex `.git/annex/bad` keeps the bytes for the user to recover; OWASP file upload cheat sheet: generated names, segregated storage, no execution, size caps https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html .

**Options**

| Option | Pros | Cons | Who it hurts |
|---|---|---|---|
| A. Same CAS + `scan_state` flag (recommended) | One write path; sha256 identity intact; S3-neutral; release is a DB update | Requires every serving/export path to check the flag (enforce in one `Blobs.servable?/1` predicate + query scope) | Implementers must be disciplined; contract-test it |
| B. Separate `quarantine/` namespace | Physical separation obvious to an operator | Move on release; two key formats in the storage adapter; export sidecars must never reference it; duplicate handling if the same sha256 arrives clean later | S3 adapter, ops |
| C. Reject at upload (no storage) | Zero disk | Loses the user's file outcome; "we refused your file" contradicts ethos; no evidence to show | User |

Triggers (frozen `quarantine_reason` codes): `magic_mismatch` (extension claims .gba, magic says otherwise — not by itself dangerous; quarantine only when the allowlisted parser would otherwise run on it), `size_over_cap` (per-format cap exceeded), `parse_failure` (allowlisted parser errored/timed out in its bounded worker), `archive_preflight_refused` (declared expansion or member count over cap), `name_policy_violation` (NUL/control/`..`/absolute in the *claimed* path — stored anyway under a generated key; the name is sanitized and the original kept as evidence), `scanner_flagged` (reserved; no scanner in v1).

Retention: indefinite until the user acts. No auto-purge (priority #1). Diagnostic detail: reason code, plain sentence, the specific limit exceeded with the observed value, inspector version, expert disclosure.

Next actions: Retry (after a server upgrade; the inbox says "Try again — Playstead has been updated since this was set aside" only when inspector version changed), Retain as custom content (releases as opaque: downloadable, exportable, never inspected; disabled for `archive_preflight_refused` until the archive gate ships, with copy explaining why), Exclude.

**Adversarial pass on A**: a bug that forgets the flag in a new download endpoint — mitigated by a single Ecto query scope `Blobs.servable(query)` used by every serving path and a contract test that a quarantined blob 404s on download/export/snapshot; a 4 GB `size_over_cap` file consuming disk — the cap is enforced *during streaming* (abort at cap+1 byte, class `size_over_cap` becomes a `failed_safely`-style no-store outcome, not a quarantine) so quarantine-by-size only applies to files under the streaming hard cap but over the per-format soft cap; household — a blob quarantined for user A and clean for user B cannot happen (same bytes, same inspection); the scan_state is physical and shared, the *decision* (retain/exclude) is per user — so `released_opaque` must be per-user too: model it as `source_file.release_state` rather than on the blob. Adjust: `blob.scan_state` = machine verdict; per-user release lives on the user's source_file/asset_set. Export/reimport — quarantined bytes are never exported; if they are reimported from elsewhere they re-quarantine deterministically.

**Recommendation**: D-C5 with the per-user release refinement. Builds on the locked opaque-archives gate and the storage-adapter decision.

---

### C6. "Failed safely"

**Lenses**
- *Distributed/durability*: the classic sequence — temp on same filesystem, fsync file, rename, fsync directory, then DB commit. If DB commit fails after rename, the CAS holds an unreferenced object: harmless, reconciled by sweeper or on next identical import (exists check by sha256 before write). If rename fails, temp is deleted. Never write directly into the final key.
- *Hash mismatch*: the streaming SHA-256 is computed during copy; after fsync, re-read the temp file and hash again (cheap for < 100 MB, bounded cost for large; make the re-verify configurable but default on — data safety > performance). Mismatch means the disk or filesystem lied; class `hash_mismatch`, do not retry automatically more than once, surface as a server-health concern (one inbox item + a readiness warning in Phase 5).
- *Disk full*: `:enospc` — abort the file, delete temp, pause the session (`state = paused{reason: disk_full}`), one banner "Your server's storage is full. Import paused; nothing was changed." Resume is manual. Do not retry file-by-file into a full disk (turns one problem into 3,000 failures).
- *Worker crash*: Oban marks the job `retryable`/`discarded`; the `tmp/<uuid>` is orphaned; sweeper removes temps older than `max_job_timeout`. Receipt for the file stays `pending` until the job's final attempt writes `failed_safely{worker_crashed}`; a `discarded` job with no receipt finalization is caught by a reconciliation pass on session resume.
- *Source untouched*: the server never has write access to the source; for LiveView uploads the source is the browser's file; for the Mac client the source is a local path the client reads. The guarantee is structural; state it in the receipt anyway ("Your original file was not changed").
- *SRE*: `tmp/` under the blob volume (same filesystem as `objects/`), owned by `nobody`, created at boot; a `df`-based free-space preflight before a session starts (IMPT-01's "consume a stated amount of storage").
- *UX*: quiet: session summary line "3 of 3,012 couldn't finish — retry available"; no toasts; inbox items only after retries are exhausted.

**Prior art**: restic exit code 3 semantics (continue, count errors, still create snapshot) https://restic.readthedocs.io/en/stable/040_backup.html ; Nextcloud's checksum-mismatch-on-upload ("will be resumed") shows the value of verifying after transfer and retrying transparently https://help.nextcloud.com/t/the-downloaded-file-does-not-match-the-checksum-it-will-be-resumed/119669 ; Oban unique jobs + Multi insertion https://oban.hexdocs.pm/Oban.html .

**Options**

| Option | Pros | Cons | Who it hurts |
|---|---|---|---|
| A. temp+fsync+rename, re-verify hash, bounded retry, session pause on ENOSPC (recommended) | Meets the guarantee; cheap | Second read for verify on large files | Slow-disk users (configurable) |
| B. Write directly to final key, mark blob `pending` until verified | One write | A crash leaves a wrong-length object under the right name; every reader must check `verified` | Everyone |
| C. Verify by size only | Fast | Misses bit-flips; contradicts IMPT-02's promise | Data safety |

**Adversarial pass on A**: two concurrent imports of the same sha256 — both write temps; the rename of the second finds the target exists (link/rename is idempotent for identical content: compare size, keep existing, delete temp); a client that lies about size — stream cap and receipt `size_over_cap`; a client that disconnects mid-stream (LiveView upload) — `interrupted`, retryable, temp deleted; S3 — the adapter implements "write to staging key, verify checksum, copy to final" with the same classes; household — no interaction.

**Recommendation**: D-C6. Builds on the locked Oban/bounded-retries decision and D-14 volumes.

---

### C7. Receipt surfaces & protocol mapping

**Lenses**
- *Protocol (D-21)*: entity kinds frozen. What a resuming client needs to *converge* is library state (asset_sets) and job state (sessions). Receipts are history, not state — they belong in a paginated REST resource, like Stripe events vs objects.
- *Volume*: journaling 40k receipts produces 40k journal rows and 200 pages of `/changes` for a client that only needs the catalogue delta; compaction horizon ≥ 90 days keeps them for months.
- *Phase 3*: the Mac client shows catalogue + job progress; the inbox may be console-only in Phase 3 (LIBR-05 puts "review imports" in the LiveView console). The API still exposes `/attention` so a later client can build it.
- *Snapshot*: add a `catalogue` branch (asset_sets where `excluded_at is null`) and a `job` branch (sessions active or terminal-within-horizon) to `Playstead.Sync.Snapshot`, exactly as its moduledoc anticipated.

**Options**

| Option | Pros | Cons |
|---|---|---|
| A. Sessions → `job`, asset_sets → `catalogue`, receipts REST-only (recommended) | Small journal; correct semantics; snapshot stays cheap | Client must fetch receipts on demand |
| B. Receipts embedded in the `catalogue` payload | One fetch | Payload bloat; receipts for failures/quarantine have no asset_set to hang off |
| C. Receipts as `job` sub-entities (`entity_id = session:receipt`) | Everything via journal | Journal flood; kind vocabulary abuse |

Endpoints (sketch, Claude's discretion on exact paths): `POST /api/v1/import-sessions` (idempotent), `POST /api/v1/import-sessions/:id/files` (stream one file; idempotent by client `command_id`), `POST …/pause|resume|reconcile`, `GET /api/v1/import-sessions/:id/receipts?cursor=`, `GET /api/v1/attention?cursor=&reason=`, `POST /api/v1/attention/:id/resolve`. LiveView: `/imports` (sessions list + detail with receipts), `/attention` (inbox), `/library/:asset_set` shows the receipt trail.

**Adversarial pass on A**: a client that misses everything — snapshot rebuilds catalogue + jobs; receipts refetched lazily; a job entity that flips 40k times — journal one entry per *state change or count bucket* (coalesce count updates: at most one journal entry per session per N seconds, always one on terminal state); household — per-user journal already.

**Recommendation**: D-C7. Builds on D-21 and the frozen `EntityKind`.

---

### C8. Inbox ergonomics

**Lenses**: UX (bulk is where 40 `.txt` files get excluded in one motion), accessibility (APG grid/table patterns; roving tabindex is overkill for a table with checkboxes — plain `table` with native checkboxes and buttons is more robust across AT), LiveView idiom (streams + JS-collected selection ids per the FullstackPhoenix bulk-actions pattern https://fullstackphoenix.com/tutorials/add-bulk-actions-in-phoenix-liveview ), quiet-by-default (LIBR-04).

**Recommendation** (D-C8): reason-grouped default with counts; session filter chip; sort newest-first inside groups; bulk toolbar for Exclude / Retain as custom / Retry / Assign system; per-item for Attach and full Correct; no aging; empty state "Nothing needs your attention" with a one-line "Recent imports" link; nav badge neutral count only; `aria-live="polite"` for selection and count changes; dialogs name the effect and count; Escape cancels; all actions reachable by keyboard; row focus outline visible. Undo via an "Excluded" filter rather than a transient toast-with-undo (the toast pattern is fragile under LiveView reconnects).

**Adversarial**: select-all across pages — bulk applies to the *visible* selection unless the user explicitly chooses "all 3,012 matching" (GitHub/Gmail pattern); reconnect mid-bulk — the command is one idempotent transaction keyed by a client-generated id; screen reader on a 10k-row stream — paginate at 50 and expose page controls.

---

### C9. Naming & microcopy

Keyed off codes; copy in one module; contract tests assert codes only.

| Code | Label | One-line explanation |
|---|---|---|
| new_asset | Added to your library | A verified copy is now stored by your server. |
| exact_duplicate | Already in your library | These exact bytes were imported before. We kept the new file name as a note. |
| alias | Another copy of a game you have | Different bytes, same release. Both copies are kept. |
| variant | A different version of a game you have | Kept alongside the version you already had. |
| incomplete_set | Some parts are missing | This game needs more than one file. We kept what you gave us. |
| unrecognized | Not yet identified | Stored safely. Playstead couldn't match it to a reference yet. |
| patched | Looks modified | Doesn't match the reference exactly. Kept as-is. |
| quarantined | Set aside for review | We stored it but didn't process it: <reason>. |
| failed_safely | Couldn't finish — nothing was changed | Your original file is untouched. You can try again. |

Resolutions: "Choose the system or details", "Add the missing part", "Keep as custom content", "Exclude from library" (confirm: "Exclude 40 files? They stay on your server and can be restored from Excluded."), "Try again". Undo labels: "Use detected details", "Remove this part", "Stop treating as custom", "Restore to library".

Quarantine reasons: magic_mismatch → "The file's contents don't look like a .gba file"; size_over_cap → "Larger than Playstead inspects for this format (128 MB)"; parse_failure → "Couldn't be read as a <format>"; archive_preflight_refused → "Archives aren't opened yet in this version"; name_policy_violation → "The file name contained characters Playstead can't store; the name was adjusted".

Session states: "Copying", "Paused — storage full", "Paused", "Finished", "Finished with 3 to review".

---

### C10. Household readiness

**Lenses**: D-01 requires `user_id` on every owned resource; a blob is *physical*, not owned. Dedupe "within a tenant" (locked) is a *visibility* rule; disk-level CAS can still be global because sha256 identity is content, not owner. Security: a cross-user existence oracle exists only via timing (skipped write); household threat model accepts this; a hosted tier would need constant-time behaviour or per-tenant CAS prefixes — noted as deferred. Reclaim: a blob is physically deletable only when zero `source_file` rows reference it across all users (refcount by query, not a counter column).

**Options**

| Option | Pros | Cons |
|---|---|---|
| A. Global physical CAS, user-scoped logical rows (recommended) | One copy on disk; simple S3 layout; exact dedupe stays per user in what the user sees | Timing oracle (accepted for household); reclaim needs cross-user refcount |
| B. Per-user CAS prefix (`objects/<user>/sha256/…`) | Perfect isolation; trivial per-user reclaim/export | Duplicate bytes across a household; hosted-tier-shaped complexity now |

**Recommendation**: D-C10. Receipts, sessions, attention items, resolutions, overrides all per user; "duplicate for A is new for B" is the intended behaviour; audit entries carry `user_id`.

---

## Deferred ideas surfaced

- Physical reclaim ("Remove from server storage") with cross-user refcount, sudo, and backup-freshness check — Phase 5 (OPER-03/PORT-03).
- Auto-resolution rules ("always retain .txt as custom") — v2 curation.
- Malware scanning adapter (`scanner_flagged`) — hosted-tier prerequisite.
- Constant-time duplicate responses / per-tenant CAS prefixes — hosted tier.
- Mac client inbox UI and per-file receipt push — Phase 3 or later; API is ready.
- "Attach from this folder" bulk companion binding — after IMPT-04 manifests prove out.
- Receipt export as CSV (igir-style report) — nice-to-have after Phase 2.
- Inspector re-run on server upgrade ("N items can be re-checked") — Phase 5 upgrade preflight.
- Header/trainer/overdump heuristics without a DAT — needs the archive/parsing gate.

## Sources

- igir report statuses — https://igir.io/output/reporting/
- restic backup exit codes and read-error behaviour — https://restic.readthedocs.io/en/stable/040_backup.html
- Immich duplicates utility — https://docs.immich.app/features/duplicates-utility/
- RomM scanning troubleshooting (unmatched, manual Match) — https://docs.romm.app/latest/troubleshooting/scanning/
- RomM library management — https://docs.romm.app/4.5.0/Usage/LibraryManagement/
- RetroArch playlist scanning (strict vs loose) — https://docs.libretro.com/guides/roms-playlists-thumbnails/
- RomVault error messages / status vocabulary — https://wiki.romvault.com/doku.php?id=error_messages
- Jellyfin: refresh overrides manual Identify (Issue #11773) — https://github.com/jellyfin/jellyfin/issues/11773
- Jellyfin: Identify with provider still overridden (Issue #16268) — https://github.com/jellyfin/jellyfin/issues/16268
- git-annex internals (`.git/annex/bad`) — https://git-annex.branchable.com/internals/
- git-annex fsck — https://git-annex.branchable.com/git-annex-fsck/
- Nextcloud checksum mismatch / resume — https://help.nextcloud.com/t/the-downloaded-file-does-not-match-the-checksum-it-will-be-resumed/119669
- Syncthing conflict semantics — https://docs.syncthing.net/users/syncing.html
- OWASP File Upload Cheat Sheet — https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html
- Oban unique jobs and Multi insertion — https://oban.hexdocs.pm/Oban.html
- LiveView bulk actions pattern — https://fullstackphoenix.com/tutorials/add-bulk-actions-in-phoenix-liveview
- W3C APG data grid pattern — https://www.w3.org/WAI/ARIA/apg/patterns/grid/examples/data-grids/
- ClamAV quarantine conventions (ops guides) — https://wiki.archlinux.org/title/ClamAV
- Phase 1 code: `~/projects/playstead/playstead-server/lib/playstead/idempotency.ex`, `~/projects/playstead/playstead-server/lib/playstead/sync/entity_kind.ex`, `~/projects/playstead/playstead-server/lib/playstead/sync/snapshot.ex`, `~/projects/playstead/playstead-server/lib/playstead/audit_log.ex`
