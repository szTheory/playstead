# Research D — Export & reimport identity (PORT-02)

Phase 2 proves the **server-side** export → verify → reimport contract and fixes the manifest format that the Phase 4 Mac client (PORT-01) will reuse. Everything below builds on the locked decisions: managed copy only; sha256 = object identity; content-addressed `objects/sha256/ab/<hash>`; exact-sha256 dedupe within a tenant with many `source_file` provenance rows per blob; archives opaque; sidecar is an optimization only, reimport re-hashes every byte; byte preservation + deterministic *generated* layout, never preservation of a user-modified layout; Oban for durable work; receipts written with effects; `nobody` runtime user; `PLAYSTEAD_BLOB_PATH=/app/blobs`; `user_id` on every owned row; change-journal entity kinds frozen (`job` covers export).

---

## One-shot recommendations (summary)

- **E1 (draft): Phase 2 ships server-side export into an operator-mounted export directory (`PLAYSTEAD_EXPORT_PATH`, default `/app/exports`, compose bind-mounts `./exports`), run as an Oban job; the same manifest is served by `GET /api/v1/exports/:id/manifest` and blobs by `GET /api/v1/blobs/:sha256` (Range-capable, needed by Phase 3 anyway), and a contract test writes the folder from the API alone and asserts it is byte-identical to the server-written folder. No browser zip download in Phase 2.** — Reversibility: reversible for the surface (a zip/download can be added later); the manifest-as-API-resource contract is one-way once Phase 3/4 clients consume it.
- **E2 (draft): Layout is a BagIt-shaped bag: `<target>/data/<system-slug>/<set folder>/<member files exactly as originally named>`; set folder = sanitized display title, with ` [<uuid8>]` appended only for sets whose folder name collides after NFC + case-fold within the same system; member filenames are the recorded original basenames (CUE/GDI/M3U descriptors reference them — renaming breaks the set), sanitized only when unsafe cross-platform, with `original_name` and `exported_as` both recorded; all names written NFC, compared NFC + case-fold; deterministic sort order everywhere (systems, sets by folder then UUID, members by ordinal, manifest lines by path bytes); the payload layout + manifest are a pure function of library state.** — Reversibility: costly — the layout is what PORT-01 and user muscle memory will expect; changing it later means two generations of folders in the wild.
- **E3 (draft): Sidecars: (1) root `playstead-manifest.json` (schema `playstead-export/1`, canonical JSON, no timestamps) indexing every set with its folder, UUID, member fingerprint and sidecar hash; (2) one `playstead-set.json` per set folder carrying the full set graph (UUID, system, title, status, members[] {path, original_name, sha256, size, role, ordinal, required}, provenance, recognition evidence with provider/version/confidence/user_override); (3) BagIt `bagit.txt`, `manifest-sha256.txt` (GNU-compatible: `<hex>  data/<path>`), `tagmanifest-sha256.txt`, `bag-info.txt`; (4) `README.txt` in plain language. Volatile facts (export id, timestamp, server build, verification result) live only in `bag-info.txt` and the DB receipt, so the payload + JSON manifests are byte-stable across runs. Schema evolution: additive within major; readers ignore unknown fields; unknown major → sidecar treated as absent.** — Reversibility: one-way — the schema id and versioning rule are a published contract the moment one user exports; layout/field additions stay reversible.
- **E4 (draft): Write-then-verify: each file is written to a `.playstead-tmp-*` sibling, fsynced, renamed, then a second pass re-opens and re-hashes every payload and tag file and compares to the DB; the export record moves `writing → verifying → verified|verification_failed` and the receipt names every mismatch. Manifest integrity = `tagmanifest-sha256.txt` (BagIt); no signing in v1. Partial exports: the target must be empty or carry this export's own `.playstead-export.json` marker; resume re-hashes and skips matching files, rewrites mismatching *own* files, refuses to touch any file it did not write, and never deletes anything. Users verify later with `sha256sum -c manifest-sha256.txt`, `bagit.py --validate`, or the console's "Verify again" action on the export record.** — Reversibility: reversible (verification is a re-runnable job; signing is additive later).
- **E5 (draft): Reimport identity = hybrid, hash-set first. Every file is re-hashed. A logical asset set's natural key is `member_fingerprint` = sha256 over the canonical sorted list of `(role, sha256)` of its members, unique per `user_id`. Sidecar UUID is a hint: if fingerprint matches an existing set → alias outcome (zero new blobs, zero new sets, N new `source_file` rows; UUID agreement is recorded, disagreement is logged as evidence). If the UUID exists in this tenant but bytes differ → never reattach; import as new set flagged variant/patched with "derived from export of <title>" evidence, or `incomplete_set` when it is a strict subset. If the UUID is unknown everywhere → create the set **reusing the sidecar UUID** so wipe → reimport restores identical identifiers; if it exists for another tenant or is malformed → mint a new UUIDv7 and record `claimed_uuid` in provenance. Missing/tampered sidecar → plain folder import; relationships come from set-level grouping rules (IMPT-04). Round-trip assertions: export → wipe → reimport ⇒ identical set graph (UUIDs, members, roles, ordinals, required) and zero new blobs; export → reimport into the same library ⇒ zero new logical records, N alias provenance rows.** — Reversibility: one-way — the fingerprint definition is the dedupe identity every future import and client relies on.
- **E6 (draft): Scope = one set, a selection, or the whole library, all through one `exports` record + `Playstead.Export.Worker` Oban job that shares the import job's progress/pause/cancel model (per-member checkpoint rows, status checked between members, resumable by re-enqueue). Whole-library export includes everything Playstead holds for the user, including incomplete/unrecognized/custom sets (under their system or `_unsorted/`) and quarantined blobs (under `_quarantined/`), each with `status` in its sidecar; only user-excluded items are opt-in.** — Reversibility: reversible.
- **E7 (draft): Fix now for PORT-01: schema id + additive rule; `sets[]` entries carry `kind: "asset_set"` and the root manifest reserves `saves[]`; every set folder reserves a `saves/` subfolder (a member literally named `saves` is renamed with the sanitize rule); role and status are open string vocabularies; the API returns the exact manifest JSON the server writes; blob GET is by sha256 with Range + ETag = sha256. Nothing else is frozen.** — Reversibility: one-way for the reserved names and schema id; everything else stays additive.
- **E8 (draft): Vocabulary: "Export" = "Your games as ordinary files". Never "backup"; README and receipt say "a copy on the same disk is not a backup". Durable `exports` row: scope, target path, file/set counts, bytes, status, verification result with per-file mismatches, started/finished, last_verified_at, generator version; surfaced in the job console with the same receipt shape as imports. Verification wording: "Every file was read back and matched its recorded hash" / "3 files did not match; nothing was deleted".** — Reversibility: reversible.
- **E9 (draft): Adopt BagIt (RFC 8493) as the container profile (published `BagIt-Profile-Identifier`), GNU `sha256sum -c`-compatible manifest lines, OCFL's canonical-JSON + sidecar-digest discipline, git-annex's "never touch foreign files" rule, and igir/RomVault's system-folder + game-subfolder convention — no DAT-tokenised paths in v1.** — Reversibility: costly (see E2/E3).

---

## E1. Export target/surface for Phase 2

### Lenses
- **Security:** a browser download of multi-GB zips via LiveView is a long-lived HTTP response from a `nobody` process — DoS and memory footguns, plus it hands the user an *archive*, which this project treats as opaque and dangerous on the way back in. Writing into a server-side directory keeps the trust boundary inside the container; the only new attack surface is path handling of the target directory name (must be a single sanitized component under `PLAYSTEAD_EXPORT_PATH`, never an absolute path from a form field).
- **Product/first adopter:** the self-hoster's mental model is "my server has a folder with my games in it that I can copy anywhere". A path they configured in compose is exactly that. A zip in Downloads is a worse fit for 40 GB.
- **Elixir/OTP/Oban:** export is a long-running, resumable job — Oban, not a request process. LiveView subscribes to progress via PubSub like import.
- **Durability:** crash mid-write is the norm to design for; a directory on disk can be resumed, a streaming HTTP zip cannot.
- **SRE/ops:** `nobody` (uid 65534) must be able to write the target. Named volumes are chowned from the image (D-14 lesson); **bind mounts are not** — the host directory keeps host ownership. Disk-space preflight is mandatory: exporting a library the size of the blob volume onto the same disk halves free space.
- **Protocol/data model:** Phase 3 already needs `GET /api/v1/blobs/:sha256` (download-on-demand) and a way to fetch set manifests. Serving the export manifest over the API costs nothing extra and is what Phase 4 consumes.
- **Household:** export scope is per `user_id`; the target directory is namespaced per user (`<root>/<user-slug or id>/<export name>`) even while the UI is single-user.

### Prior art
- Immich has no export; users are told the originals live on disk under the storage template ([discussion #1644](https://github.com/immich-app/immich/discussions/1644), [#11526](https://github.com/immich-app/immich/discussions/11526)). Lesson: "just read the volume" is not an export — filenames are UUIDs unless a template job is run.
- RomM writes gamelist.xml/Pegasus sidecars and media next to ROMs and explicitly never moves/renames/deletes ROM files ([RomM exports](https://docs.romm.app/latest/reference/exports/)).
- git-annex export writes a tree to a remote and will overwrite/delete unrelated files unless the remote is also `importtree` ([git-annex export](https://git-annex.branchable.com/git-annex-export/)) — the failure mode to avoid.
- rclone `check --download` / restic `check --read-data` are the "actually read the bytes back" verifications ([rclone check](https://rclone.org/commands/rclone_check/)).

### Options
| Option | Pros | Cons / footguns | Who it hurts |
|---|---|---|---|
| (a) Server-side export into mounted dir | Resumable, verifiable, honest for multi-GB, matches self-hoster mental model, single code path | Bind-mount ownership for `nobody`; needs disk preflight; user must reach the host to copy | Hosted-service users (n/a in v1) |
| (b) Browser zip download from LiveView | Zero ops setup | Archive on the way back in (opaque policy), memory/timeouts, no resume, no post-write verification possible | Anyone with > a few GB |
| (c) API-only (client writes folder) | Exactly what Phase 4 Mac does | No Mac client in Phase 2, so PORT-02 would be proven only by tests, not a usable surface | First adopter today |
| (d) a + c with one manifest builder | One truth, two writers, contract-tested equivalence | Slightly more surface | — |

### Adversarial pass (on d)
- *Bind mount owned by root:* job fails at preflight with the exact `chown 65534:65534 ./exports` command in the receipt; readiness row in Settings shows "Export folder: not writable" before any export is attempted.
- *Target inside blob root or blob root inside target:* refuse (realpath comparison) — otherwise an export can recurse into itself or a later "clean target" could touch custody.
- *Disk full mid-write:* `:file.write` returns `{:error, :enospc}`; member checkpoint marks `failed`, job snoozes and reports "needs N GB more"; nothing is deleted; resume after space is freed.
- *Slow disk / huge library:* bounded by per-member checkpoints; progress is bytes-verified over bytes-total, not file counts.
- *Future S3 blob adapter:* the writer streams from the storage adapter's `stream/1`; the export dir stays local. Fine.
- *Future Mac client:* uses (c). The equivalence test guarantees the same bytes on disk.

### Recommendation
See E1 summary. Builds on D-14 (volumes, `nobody`), D-18/D-20 (API-first, idempotent job creation with `Idempotency-Key`), the storage-adapter decision. Claude's discretion: whether disk free space comes from `:disksup` (os_mon) or `df -Pk`; the exact readiness-row wording.

---

## E2. Deterministic folder layout

### Lenses
- **Preservation/ROM domain:** multi-file sets are *referential*: a `.cue` names its `.bin` tracks by exact filename and case; `.gdi`, `.m3u`, `.ccd/.sub/.img` behave the same. Redump's convention is `Title (Region) (Track 01).bin` referenced verbatim from the cue ([Redump forum](http://forum.redump.org/topic/19969/sega-dreamcast-multicue-gdi/), [binmerge](https://github.com/Dimensional/binmerge)). Renaming member files silently breaks the set — so member filenames must be the recorded original basenames, not canonical names. No-Intro names are 7-bit ASCII with `/\:*?"<>|` forbidden and no leading/trailing dot or space ([No-Intro naming](https://wiki.no-intro.org/index.php?title=Naming_Convention)).
- **Security:** every recorded filename is untrusted. Path traversal (`..`, absolute, drive letters), control characters, NUL, Windows reserved device names (`CON`, `NUL`, `COM1`…, even with extensions), trailing dot/space, > 255 bytes ([MS naming rules](https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file)). Export writes only into `<target>/data/<system>/<set>/<basename>` — never a path with separators from the source.
- **Cross-filesystem:** APFS preserves normalization but is normalization-insensitive; HFS+ forced NFD; ext4/NTFS/exFAT are bag-of-bytes ([Eclectic Light explainer](https://eclecticlight.co/2021/05/08/explainer-unicode-normalization-and-apfs/), [mjtsai](https://mjtsai.com/blog/2017/06/27/apfs-native-normalization/)). APFS/NTFS/exFAT default case-insensitive; ext4 case-sensitive ([LWN](https://lwn.net/Articles/784041/)). Syncthing surfaces case conflicts rather than guessing ([Syncthing docs](https://docs.syncthing.net/users/syncing.html)). Name limits: 255 bytes on ext4, 255 UTF-8 chars on APFS, 255 UTF-16 units on NTFS/exFAT — use **255 bytes UTF-8** as the floor.
- **Product:** the first adopter wants `Game Boy Advance/Metroid Fusion (USA)/Metroid Fusion (USA).gba`, recognisable at a glance in Finder.
- **Data model:** `asset_member.expected_relative_export_path` already exists in the content model — populate it at import (basename only), so export is a lookup, not a computation.
- **Determinism:** "same library state ⇒ byte-identical layout" must hold with a display title that can change via Needs Attention correction — that is still a library-state change, so it is allowed to move the folder; identity on reimport does not depend on the folder name.

### Prior art
- igir: `--dir-dat-name` (system folder), `--dir-game-subdir multiple` (subfolder only for multi-file games), `--dir-letter` buckets; DAT tokens can map one ROM to multiple paths ([igir path options](https://igir.io/output/path-options/), [tokens](https://igir.io/output/tokens/)).
- RomVault: DAT-name tree, "ToSort" for unmatched, locked directories are never modified, but even locked dirs lose 0-byte files ([RomVault wiki](https://wiki.romvault.com/doku.php?id=tosort_directories), [issue #11](https://github.com/RomVault/RVWorld/issues/11)).
- OCFL separates *content path* (safe, may be opaque) from *logical path* and forbids `.`/`..`/empty components and prefix-overlap ([OCFL 1.1](https://ocfl.io/1.1/spec/)).
- BagIt: percent-encode only LF/CR/%; discourage case-only and normalization-only name differences; compare after consistent normalization ([RFC 8493](https://www.rfc-editor.org/rfc/rfc8493.html)).

### Options for the set folder name
| Option | Pros | Cons / footguns |
|---|---|---|
| Display title only | Prettiest | Collides (two dumps of "Tetris (USA)"; alias sets), changes on correction |
| Asset-set UUID only | Never collides, never moves | Unreadable; violates "ordinary folders" spirit |
| Title + ` [uuid8]` always | Readable + unique | Ugly suffix on every folder |
| Title, suffix only on collision (recommended) | Pretty in the common case, unique always, deterministic given library state | Adding a same-titled game later renames the earlier folder on the *next* export (acceptable: layout is generated, not preserved) |
| Primary member's original filename stem | "My file names back" | Multi-file sets have no obvious primary; same collisions |

Member filename policy: original basename verbatim (NFC), sanitized only when unsafe; sanitized form is deterministic (`CON.gba` → `CON_.gba`, trailing dots/spaces stripped, forbidden chars → `_`, overlong → truncated stem + ` [uuid8]` + ext). Both names recorded in the sidecar. Within a set, member basenames must be unique after NFC + case-fold — enforce at import (otherwise the set goes to Needs Attention as ambiguous).

### Adversarial pass
- *Two sets whose sanitized folder names collide only on a case-insensitive FS:* case-fold comparison catches it on the server (case-sensitive ext4) before writing.
- *Title "…" becomes empty after sanitization:* fall back to `Untitled [uuid8]`.
- *System unknown (custom content):* `_unsorted/`. Quarantined: `_quarantined/`. Leading underscore keeps them sorted first and visibly different; both are reserved system-slug names.
- *Set with 200 tracks × 200 bytes of name × deep root path:* total path can exceed Windows MAX_PATH 260; document it (Windows users enable long paths; macOS/Linux fine). Do not shorten deterministically-unstable.
- *User later renames folders and reimports:* explicitly not promised; reimport still works because identity is by hash.
- *Household:* per-user root (`data/` is per export; the export target itself is per user).

### Recommendation
See E2 summary. Builds on `asset_member.expected_relative_export_path`, the byte-preservation guarantee, and the "untrusted filenames" rule. Claude's discretion: exact slug table for systems (`gba`, `snes`, …) versus long names — but it must be a versioned, stable mapping stored with the recognition provider, not free text.

---

## E3. Sidecar manifest

### Lenses
- **Verification with ordinary tools:** GNU `sha256sum -c` accepts `<hex>  <path>` (two spaces, text mode) or `<hex> *<path>` (binary); BSD `shasum -a 256 -c` reads the same; both escape newline/backslash in names with a leading `\` ([sha256sum man](https://man7.org/linux/man-pages/man1/sha256sum.1.html)). BagIt's `manifest-sha256.txt` uses exactly `checksum filepath` with paths relative to the bag root starting `data/` — so one file serves both `sha256sum -c` and `bagit.py --validate` ([RFC 8493](https://www.rfc-editor.org/rfc/rfc8493.html), [bagit-python](https://github.com/LibraryOfCongress/bagit-python), [BagIt Profiles](https://bagit-profiles.github.io/bagit-profiles-specification/)).
- **Preservation:** OCFL keeps a single `inventory.json` with digest→paths plus a sidecar `inventory.json.sha512` and a fixity block for legacy hashes ([OCFL](https://ocfl.io/1.1/spec/)). That maps cleanly onto our three-layer identity: sha256 is the manifest digest; CRC32/MD5/SHA-1 (if computed for recognition) go into a `fixity` block as evidence, never identity.
- **Product:** a human opening the folder needs a README that answers "what is this, is it a backup (no), how do I check it, how do I put it back".
- **Protocol:** the same JSON must be servable over the API and consumable by Swift without surprises: RFC 3339 timestamps, lowercase hex, integers for sizes, no floats for confidence (use `0..100` integer or string), stable key order.
- **Durability:** the manifest itself can be truncated by a crash — hence tagmanifest + writing tag files last.

### Options
| Option | Pros | Cons / footguns |
|---|---|---|
| Single root JSON only | One file, simple | Moving one game folder elsewhere loses its relationships; a 10k-set manifest is one big blob |
| Per-set JSON only | Each folder self-describing, survives cherry-picking | No whole-export index; verify needs a walk |
| Both, root indexes per-set sidecars by hash (recommended) | Self-describing folders + one index + tamper detection of sidecars via root + tagmanifest | Two generators from one struct (must be one function) |
| BagIt-compliant container (recommended, with the above inside) | Independent validators exist; `data/` isolation; tagmanifest protects manifests; profile URI documents ours | One extra `data/` level; `bagit.txt` looks foreign to gamers |
| BagIt-inspired, flat (no `data/`) | Flatter | Loses off-the-shelf validation; still need our own tagmanifest |

Proposed `playstead-set.json` (illustrative, not final):
```json
{
  "schema": "playstead-export/1",
  "kind": "asset_set",
  "id": "0192f3a1-…",
  "member_fingerprint": "sha256:…",
  "system": "gba",
  "title": "Metroid Fusion (USA)",
  "status": "complete",
  "members": [
    {"ordinal": 0, "role": "primary", "required": true,
     "path": "Metroid Fusion (USA).gba", "original_name": "Metroid Fusion (USA).gba",
     "sha256": "…", "size": 8388608,
     "fixity": {"crc32": "…", "md5": "…", "sha1": "…"}}
  ],
  "provenance": [{"imported_at": "…", "source_name": "…", "import_receipt_id": "…"}],
  "recognition": [{"provider": "…", "provider_version": "…", "confidence": 100,
                   "user_override": false, "matched": "…"}]
}
```
Determinism: canonical JSON (sorted keys, 2-space indent, `\n` newline, UTF-8, no timestamps in payload manifests). `bag-info.txt` carries `Bagging-Date`, `Payload-Oxum`, `Playstead-Export-Id`, `Playstead-Server-Version`, `Playstead-Verification: verified|failed`, `BagIt-Profile-Identifier`.

Forward-compat rules (publish in README and docs): major in the schema id; additive fields within a major; readers MUST ignore unknown fields and unknown `role`/`status` strings (keep them as strings); a reader seeing an unknown major MUST treat the sidecar as absent and fall back to hash-only import.

### Adversarial pass
- *Sidecar drift between root and per-set:* impossible if one `%Export.Manifest{}` struct renders both; contract-test that root's recorded sidecar hash equals the written file.
- *Sidecar with 100k members:* still fine; JSON streaming not needed at Phase 2 scale, but keep members in an array, not a map, so it can be streamed later.
- *Non-ASCII titles:* JSON is UTF-8; BagIt paths need only LF/CR/% encoding, which sanitization already forbids in names.
- *User edits the JSON (e.g. fixes a title):* tagmanifest fails ⇒ sidecar ignored, files imported by bytes; the receipt says so.

### Recommendation
See E3 summary. Builds on the "sidecar is optimization only" decision and the three-layer identity model. **Owner question:** BagIt-compliant (`data/` level, `bagit.txt`) vs flat — see final message.

---

## E4. Verification and partial exports

### Lenses
- **Durability:** write to `<dir>/.playstead-tmp-<member-uuid>`, `:file.write` in 1 MiB chunks while hashing, `:file.sync`, `File.rename/2`, then sync the directory. **Footgun:** Erlang's `:file` cannot open a directory to fsync it; use `System.cmd("sync", ["-f", dir])` (coreutils ≥ 8.24, present in the Debian-slim image) after each set, or accept rename-durability as best-effort and rely on the verification pass. Rename atomicity ≠ durability without the directory fsync ([crash-consistency notes](https://0xkiire.com/crash-consistency-fsync-rename/), [write-file-atomic #64](https://github.com/npm/write-file-atomic/issues/64)).
- **Honesty:** a read-back straight after write can be served from the page cache; the verification proves "the bytes we handed the kernel are the bytes in the file", not media integrity. Say exactly that in the receipt ("read back and matched"), not "safe".
- **Security:** never follow symlinks in the target (`File.lstat`); refuse if any path component under the target is a symlink; refuse to overwrite a file that is not recorded as written by this export id.
- **Ops:** resume after container restart must be trivial — the `exports` row + per-member checkpoint rows are the state; the on-disk marker `.playstead-export.json` (export id, user id) ties the directory to the row so a different export cannot adopt it.
- **Product:** "Verify again" on an old export answers "is that folder on my NAS still good?" — the same job re-reads and updates `last_verified_at` (language PORT-03 will reuse).

### Prior art
- rclone `check --download`, restic `check --read-data(-subset)` ([rclone](https://rclone.org/commands/rclone_check/), [anjackson](https://anjackson.net/2023/07/04/robust-file-transfers-with-rclone/)).
- Syncthing temp-file-then-rename and reserved `.syncthing.*` namespace ([Syncthing](https://docs.syncthing.net/users/syncing.html)).
- BagIt completeness vs validity; `Payload-Oxum` as a fast pre-check; tagmanifest protects tag files ([RFC 8493](https://www.rfc-editor.org/rfc/rfc8493.html)).
- git-annex: exports can clobber foreign files unless the remote is import-tracked ([git-annex export](https://git-annex.branchable.com/git-annex-export/)).

### Options
| Option | Pros | Cons |
|---|---|---|
| Hash-while-writing only | Fast | Proves nothing about what landed on disk |
| Hash-while-writing + full read-back re-hash (recommended) | Honest "read back" claim; catches ENOSPC short writes, FS bugs | 2× read I/O of the export size |
| Read-back with `Payload-Oxum` fast path | Cheap | Only catches size/count errors — fine as a *pre*-check, not the verification |
| Sign the manifest (HMAC with server secret / device key) | Tamper evidence | Non-portable, key-management story missing, false sense of security; defer |

Partial-export rules: (1) target must be empty or contain this export's marker; (2) on resume, per-member rows in `written`/`verified` are re-hashed and kept if they match, rewritten if they do not; (3) any file present that is not in this export's written set ⇒ export stops with `target_has_unexpected_files` (receipt lists them) — never delete, never overwrite; (4) tag files (`bagit.txt`, manifests, README, `bag-info.txt`) are written last, after verification; (5) cancel leaves the directory as-is with the marker showing `cancelled` and the README not yet written — the console offers "Resume" or "Leave as is" (no delete button in v1).

### Adversarial pass
- *Crash between rename and directory sync:* file may vanish after power loss; resume's re-hash pass sees it missing and rewrites.
- *Verification fails on 3 of 10k files (bad RAM/disk):* status `verification_failed`, per-file list, "Retry those files" re-writes only them; nothing auto-deleted.
- *User points two exports at the same directory:* second refuses (marker mismatch).
- *Symlink planted in target pointing at `/app/blobs`:* lstat refusal before any write.
- *Future S3:* read side is the adapter; no change.

### Recommendation
See E4 summary. Builds on the "exports are tested" ethos principle, D-20 (receipts with effects), Oban durability. Claude's discretion: chunk size, whether `sync -f` is per set or per N files.

---

## E5. Reimport identity

### Lenses
- **Data model:** the three-layer model gives us blob identity (sha256) and logical identity (UUID) but no *derived* logical identity that survives a wiped database. A **member fingerprint** (sha256 over canonical sorted `(role, sha256)` pairs) is that missing natural key — exactly the D-20 pattern of client-generated/derived natural keys + `on_conflict`. It also makes "no duplicate logical records" a DB uniqueness constraint (`unique (user_id, member_fingerprint)`), not a heuristic.
- **Security:** the sidecar UUID is untrusted input. Reusing it is safe only if (a) it parses as a UUID, (b) it does not exist for any user, (c) it is not used for authorization anywhere (it is not — auth is `user_id` scope). Otherwise mint and record `claimed_uuid`.
- **Product:** the four receipt outcomes users see: *exact duplicate of "Metroid Fusion (USA)"* (alias), *new asset*, *incomplete set — missing 2 of 14 tracks listed in its manifest*, *variant/patched — 1 of 14 files differs from the export it came from*. Never "duplicate request", never "invalid manifest" as a red error.
- **Preservation:** roles matter for identity (a `.cue` swapped with a different `.cue` but same bins is a different set); ordinal does not (order derives from the descriptor).
- **Household:** the fingerprint is per-user; the same bytes imported by two users are two logical sets over shared… no — blobs are deduped *within a tenant* per the locked decision, so no cross-tenant sharing at all; keep it that way.

### Prior art
- OCFL: state maps digests to logical paths; identity of a version is its digest set, not its path set ([OCFL](https://ocfl.io/1.1/spec/)).
- RomM 4.x hash-based matching: identity from CRC/MD5/SHA-1 against DATs, dedupe by hash ([RomM library management](https://docs.romm.app/4.4.0/Usage/LibraryManagement/)); Playstead keeps those as evidence only.
- Jellyfin: local `.nfo` sidecars always win over remote metadata — the opposite of what we want for identity; we let bytes win ([Jellyfin nfo](https://jellyfin.org/docs/general/server/metadata/nfo/)).
- BagIt fetch.txt: a bag can be "complete but not valid" — the analogue of our `incomplete_set` retaining relationships from the sidecar.

### Options
| Option | Pros | Cons / footguns |
|---|---|---|
| (a) Trust UUID, verify bytes | Simple; restores identifiers | Edited bytes under an old UUID would either be rejected or silently reattached; sidecar becomes load-bearing |
| (b) Hash-set only, ignore UUIDs | Sidecar truly optional; robust | Wipe → reimport mints new UUIDs — clients' caches and saves keyed by set UUID break; not "identical" |
| (c) Hybrid: fingerprint first, UUID as hint/restore (recommended) | Bytes are truth; identifiers survive wipe; conflicts have defined outcomes | Two code paths to test; need explicit rules for every UUID×fingerprint combination |

Decision matrix (per set found in the folder, after re-hashing all files):

| Fingerprint matches existing set? | Sidecar UUID | Outcome |
|---|---|---|
| yes | same as existing | `exact_duplicate` (alias): N new `source_file` rows, 0 blobs, 0 sets |
| yes | different / absent | same alias outcome; record `claimed_uuid` mismatch as evidence |
| no, all member hashes known, subset of existing set | any | `incomplete_set`, linked to the existing set via manifest evidence; no new set until the user resolves (attach missing companion / retain as custom) |
| no, some hashes new | UUID exists here | `variant_or_patched` new set (new UUID), evidence "derived from export of <title>"; blobs deduped where hashes match |
| no | UUID unknown everywhere | new set, **UUID reused**, blobs imported (or deduped) |
| no | UUID exists for another user / malformed | new set, fresh UUIDv7, `claimed_uuid` recorded |
| sidecar missing or tagmanifest mismatch | — | plain folder import; grouping per IMPT-04 rules; receipt explains the sidecar was not used |

Round-trip guarantees to assert in tests (`Playstead.ExportRoundTripTest`):
1. export → `Repo.delete_all` (library tables) + blob dir wipe → reimport ⇒ `asset_sets`/`asset_members` graph equal (UUIDs, roles, ordinals, required) and `blobs` count equal, all sha256 equal.
2. export → reimport into the same library ⇒ `asset_sets` count unchanged, `blobs` count unchanged, `source_files` count += N, receipt outcomes all `exact_duplicate`.
3. export → delete one track file → reimport ⇒ one `incomplete_set` receipt naming the missing member, zero new sets.
4. export → flip one byte in one track → reimport ⇒ one `variant_or_patched` new set with derivation evidence; original untouched.
5. export → edit `playstead-set.json` title → reimport ⇒ tagmanifest mismatch, hash-only path, still `exact_duplicate`.

### Adversarial pass
- *Attacker-crafted sidecar claiming the UUID of a set that exists for another user:* UUID reuse refused (global uniqueness check), fresh UUID minted; no information leak beyond "already used" which is only visible in provenance to the importing user — acceptable; if the owner prefers zero oracle, always mint fresh when any collision and do not distinguish reasons in the UI.
- *Fingerprint collision by design:* sha256 over sorted pairs; negligible.
- *Role vocabulary drifts (a later provider renames roles):* fingerprint changes ⇒ false "new set". Mitigation: roles are frozen strings in v1 (`primary`, `descriptor`, `track`, `disc`, `patch`, `bios_dependency`, `parent`), and any renaming requires a migration that recomputes fingerprints.
- *Huge folder with thousands of sets:* per-set processing inside the staged-collection import job (IMPT-05); the sidecar is only a grouping hint.
- *Future Mac client exporting with saves in the folder:* `saves/` is ignored by the Phase 2 importer (reserved, skipped with a receipt note), not treated as unknown members.

### Recommendation
See E5 summary. Builds on the three-layer identity model, exact-sha256 dedupe per tenant, D-20 natural-key convergence, and the "sidecar is optimization only" rule.

---

## E6. Export scope and execution

### Lenses
- **Oban idiom:** one worker with `unique: [keys: [:export_id], states: [:available, :scheduled, :executing, :retryable]]`; the job reads the `exports` row's `requested_state` (`running|paused|cancelled`) between members and returns `{:snooze, n}` when paused (queue-level `pause_queue` is global and wrong for per-export pause) ([Oban docs](https://oban.hexdocs.pm/Oban.html)). Progress lives in `export_members` checkpoint rows, not in job `meta`, so LiveView can query it and it survives job pruning.
- **Product:** "Export" as a collection action (ethos: collection actions include export and verify) plus "Export everything" in Settings/Library. Selection = the same multi-select the library uses for other bulk actions.
- **Data safety:** a whole-library export that silently skipped Needs Attention items would be a lossy "clean exit" — unacceptable under principle 8 of the review questions ("clean exit from the ecosystem").
- **Protocol:** `POST /api/v1/exports` with `Idempotency-Key`, scope `{all | set_ids[] | collection_id}`, `target_name`; returns the export receipt; journal kind `job`.

### Options
| Option | Pros | Cons |
|---|---|---|
| Whole-library only | Simplest | No per-game "give me this one back"; Phase 4 wants per-set anyway |
| Per-set only | Minimal | No clean exit |
| All three scopes through one job (recommended) | One machine, one receipt shape, reuse of import's progress model | Selection UI in LiveView |

Needs Attention / quarantined / excluded policy: include everything Playstead holds for the user by default with a `status` in each sidecar (`complete`, `incomplete`, `unrecognized`, `custom`, `quarantined`), placed under the system folder when known, else `_unsorted/`, quarantined under `_quarantined/`; user-excluded items are opt-in ("Include items you excluded"). The README explains those folders in one sentence each.

### Adversarial pass
- *Concurrent import while exporting:* export snapshots the set list at job start (stored in `export_members`), so late imports are simply not in this export; receipt states "as of <time>".
- *Pause for a week then resume after an upgrade:* schema migrations are additive; the export row's `schema` id is fixed at creation so the finished bag is consistent.
- *User cancels then deletes the folder by hand:* "Verify again" reports "folder not found" calmly; row stays as history.

### Recommendation
See E6 summary. Builds on IMPT-05's job/progress model and D-20. Claude's discretion: queue name (`export` vs `default`), concurrency 1 per user.

---

## E7. Extension points for Phase 4 (saves) and the Mac client

What must be fixed now so PORT-01 does not reshape the manifest:
1. Schema id `playstead-export/1` + additive rule + "unknown major ⇒ ignore sidecar".
2. Root manifest has `sets[]` now and reserves `saves[]`; each entry carries `kind`.
3. Each set folder reserves `saves/` (future: `saves/<save_kind>/<revision-id>.<ext>` + `playstead-saves.json`); reserved names cannot be produced by sanitization (rename with `_` suffix).
4. Roles/status are open string vocabularies; the fingerprint uses only `(role, sha256)`.
5. API: `GET /api/v1/exports/:id/manifest` returns byte-identical JSON to the file; `GET /api/v1/sets/:id/manifest` returns the per-set sidecar; `GET /api/v1/blobs/:sha256` supports Range with `ETag: "<sha256>"` (Phase 3 needs all three).
6. BagIt profile URI published in docs; the Mac writes the same profile.
7. `bag-info.txt` gets `Playstead-Generator: server|mac`.
Everything else (README wording, folder for `_unsorted`, fixity algorithms) remains additive.

Reversibility: one-way for 1–3 and 5; reversible otherwise.

---

## E8. Honesty and microcopy

- Action label: **"Export"** with subtitle "Your games as ordinary files". Confirmation: "Playstead will write exact copies of N files (X GB) to `<path>` and read each one back to check it. Your library stays as it is. A copy on the same disk is not a backup."
- Receipt states: `preparing` → `writing (3.2 of 14.1 GB)` → `checking (read back 41 of 212 files)` → `verified` | `some files did not match` | `stopped: needs 2.1 GB more space` | `stopped: folder contains files Playstead did not write` | `cancelled`.
- Verified wording: "Every file was read back and matched its recorded SHA-256." Failed: "3 files did not match after writing. Nothing was deleted. Retry those files, or check the disk."
- Never: "backup", "safe", "bad file", "corrupt ROM". Use "did not match".
- Durable `exports` row: id, user_id, scope, target_path, set_count, file_count, byte_count, status, verification_result (jsonb per-file mismatches), schema, generator_version, started_at, finished_at, last_verified_at; visible in the job console and via `GET /api/v1/exports/:id`.
- README.txt first lines: what this folder is; that files are exact bytes and can be used directly; how to check (`sha256sum -c manifest-sha256.txt`); how to reimport (drop the folder onto Playstead or point the importer at it); that `playstead-*.json` help Playstead but are not needed to use the games; that this is not a backup unless it is on a different device and verified.

Reversibility: reversible.

---

## E9. Prior art digest

| Source | Take |
|---|---|
| BagIt RFC 8493 / bagit-python / BagIt Profiles | Adopt as container: `data/`, `manifest-sha256.txt`, `tagmanifest-sha256.txt`, `bag-info.txt`, `Payload-Oxum`, profile URI. Gives free third-party validation. |
| GNU coreutils / BSD sha256sum | `<hex>  <path>` lines, sorted, LF; avoid names needing `\` escaping by sanitizing. |
| OCFL 1.1 | Canonical JSON inventory + sidecar digest; digest→paths manifest; `fixity` block for legacy hashes; path constraints. |
| git-annex export/import | Never clobber foreign files; track what you wrote. |
| restic / rclone | Verification means reading the bytes back, and saying so. |
| igir / RomVault | System folder + per-game subfolder for multi-file games; unmatched go to a sorted-first holding folder; RomVault's 0-byte deletion in locked dirs is the anti-pattern. |
| No-Intro / Redump | Names are ASCII with forbidden chars; CUE references tracks by exact name — never rename members. |
| Immich / RomM / Jellyfin | "Read the volume" is not export; sidecars next to media are normal; sidecars must not outrank bytes for identity. |
| Syncthing | Temp-file-then-rename; surface case conflicts rather than guess. |
| APFS/HFS+/ext4/NTFS/exFAT | Write NFC, compare NFC + case-fold, 255-byte name floor, document Windows long paths. |

---

## Deferred ideas surfaced
- Saves in the export (`saves/` per set) and Mac-side export writer — Phase 4 (PORT-01).
- Signed manifests (device-key or server HMAC) — after a key-management story exists.
- Browser zip download for small single sets — after the archive-security gate, as a convenience only.
- "Verify again" scheduling / periodic re-verification of exports — Phase 5 (PORT-03 language).
- `posix_fadvise`/O_DIRECT read-back to defeat page cache — NIF territory, not worth it in v1.
- Export to S3-compatible destination (bag as object prefix) — v2 with the S3 adapter.
- Reference-in-place mode reusing the same bag layout as its on-disk form — IMPT-07 (v2).
- igir-style tokenised output paths (`{region}`, letter buckets) as user-selectable layouts — breaks determinism promise; only if demanded.
- `_unsorted` / `_quarantined` folder names and the system-slug table deserve a UI-SPEC pass.

## Sources
- https://www.rfc-editor.org/rfc/rfc8493.html
- https://github.com/LibraryOfCongress/bagit-python
- https://bagit-profiles.github.io/bagit-profiles-specification/
- https://ocfl.io/1.1/spec/
- https://man7.org/linux/man-pages/man1/sha256sum.1.html
- https://git-annex.branchable.com/git-annex-export/
- https://rclone.org/commands/rclone_check/
- https://anjackson.net/2023/07/04/robust-file-transfers-with-rclone/
- https://igir.io/output/path-options/
- https://igir.io/output/tokens/
- https://wiki.romvault.com/doku.php?id=tosort_directories
- https://github.com/RomVault/RVWorld/issues/11
- https://wiki.no-intro.org/index.php?title=Naming_Convention
- http://forum.redump.org/topic/19969/sega-dreamcast-multicue-gdi/
- https://github.com/Dimensional/binmerge
- https://docs.romm.app/latest/reference/exports/
- https://docs.romm.app/4.4.0/Usage/LibraryManagement/
- https://github.com/immich-app/immich/discussions/1644
- https://github.com/immich-app/immich/discussions/11526
- https://jellyfin.org/docs/general/server/metadata/nfo/
- https://docs.syncthing.net/users/syncing.html
- https://eclecticlight.co/2021/05/08/explainer-unicode-normalization-and-apfs/
- https://mjtsai.com/blog/2017/06/27/apfs-native-normalization/
- https://lwn.net/Articles/784041/
- https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file
- https://0xkiire.com/crash-consistency-fsync-rename/
- https://github.com/npm/write-file-atomic/issues/64
- https://oban.hexdocs.pm/Oban.html
