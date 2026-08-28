# Phase 2 Research — Area B: Formats & Recognition

Researched 2026-08-28 against PROJECT.md, REQUIREMENTS.md (IMPT-01..06, PORT-02), ROADMAP.md Phase 2, 01-CONTEXT.md (D-01..D-22), TECHNICAL-RISKS.md, EXPERIENCE-ETHOS.md, and the existing `Playstead.Sync` change-journal code (`entity_kind.ex` freezes `catalogue` as a kind with no producer yet; `entry.ex` payload is a free-form map; `snapshot.ex` materialises one branch per domain).

Builds on locked decisions: managed copy only; sha256 = identity; exact-sha256 dedupe with many `source_file` rows per blob; archives opaque until the gate; narrow magic-byte allowlist; matcher is evidence never rewrite; no bundled DAT payload; receipts in the same transaction as effects; `catalogue` journal kind frozen; every filename/header/DAT untrusted.

---

## One-shot recommendations (summary)

- **B-01 (draft): v1 allowlist = seven system ids in two tiers. Tier A "signature-validated" (header magic + checksum/complement checked): `gba` (.gba), `gb` (.gb), `gbc` (.gbc), `nes` (.nes, iNES/NES 2.0 `NES\x1A`), `md` (.md/.gen/.bin with `SEGA` at 0x100). Tier B "structure-validated" (no magic; layout heuristics): `snes` (.sfc/.smc, internal-header checksum⊕complement + copier-header size rule), `psx` (.cue + .bin via CUE parse; `.chd` header-only). Every other file is accepted as a blob and receipted "kept as-is, not recognized". "Supported" in the receipt means: system assigned AND format evidence ≥ `extension`; validation tier is shown as evidence, never as a verdict on the bytes.** — Reversibility: reversible (adding a system/extension is additive; the tier label is evidence, not schema).
- **B-02 (draft): Prove IMPT-04 with Redump-style PS1 CUE+BIN (multi-track). Member model: `asset_member{ordinal, role ∈ descriptor|track|primary|disc|patch|parent|companion, required bool, blob_id (nullable while missing), declared_name, export_path}`. CUE parsed as text with hard limits (≤64 KiB, ≤99 FILE/TRACK lines, `FILE ... BINARY` only, filename must be a bare relative name with no separators/`..`/controls). Missing referenced BIN → asset_set `incomplete`, receipt "incomplete set", Needs Attention "attach missing companion". M3U multi-disc and CHD parent/child are recorded as roles but not proven in Phase 2.** — Reversibility: costly (member roles/ordinals are exported in the sidecar manifest and published to the Mac client in Phase 3).
- **B-03 (draft): Recognition with no DAT is a header-evidence pipeline, not a matcher. Evidence recorded per source_file: extension, magic/structure validation result, header fields (GBA title/game code/maker/version; GB title/CGB flag; NES mapper/PRG/CHR/NES2; SNES internal title + checksum validity + copier header; MD serial/region; CUE track table), size facts (power-of-two, %1024==512), No-Intro filename parse. Outcome decision without a matcher: new asset / exact duplicate / alias (sha256 known, name differs) / incomplete set / kept-as-is-not-recognized / header-check-failed (Needs Attention) / quarantined / safely failed. "Unrecognized" = no system could be assigned. "Supported format, no reference installed" is a normal, quiet state (`recognition.status = no_reference`) that never goes to Needs Attention.** — Reversibility: reversible (evidence rows are append-only; a later matcher adds rows).
- **B-04 (draft): Definitions frozen in the receipt vocabulary: alias = same sha256 already in the library, different filename/path → new source_file, no new blob, receipt "already in your library (alias)". variant = different bytes, same logical release — Phase 2 may only say "possible variant" when a header serial (GBA/GB game code, MD serial) matches an existing item on the same system; certainty requires a reference database. patched = (a) an IPS/UPS/BPS *patch file* detected by magic (`PATCH`/`UPS1`/`BPS1`) stored as its own blob with role `patch`; (b) a patched ROM is NOT claimed in Phase 2 — receipt says "no reference installed". Header-stripped (NES without iNES, SNES copier header) and non-power-of-two size are recorded as evidence lines, never as a verdict.** — Reversibility: reversible (vocabulary is additive; codes are stable strings).
- **B-05 (draft): Phase 2 ships the `recognition` schema, the `Playstead.Recognition.Provider` behaviour, the built-in `HeaderEvidence` provider, and an admin-supplied Logiqx-XML DAT-pack importer (No-Intro/Redump format, parsed with a SAX parser, no DTD/entity expansion, size/entry caps) as the last, independently-droppable plan. Provenance per pack: `source_url, retrieved_at, upstream_version, file_sha256, license_claim (free text + enum: public_domain|cc_by_sa_4|unstated|other), transform_version`. Confidence enum: `exact` (all required members match size+sha1/crc32) | `header` | `filename` | `user`. User corrections live in a separate `recognition_overrides` row (user_id, asset_set_id, field, value, reason, audit id); evidence rows are never rewritten. Licensing (verified today): Redump states its metadata is public domain; libretro-database is CC BY-SA 4.0; No-Intro publishes no license — treat as admin-supplied only, never bundled.** — Reversibility: reversible for the importer (droppable plan); one-way for the evidence/override split (it is the audit trail).
- **B-06 (draft): Compute CRC32, MD5, SHA-1 alongside SHA-256 in the single streaming pass; store the four full-file hashes on the `blob` row (they are properties of the immutable bytes). Headerless variants for NES (skip 16), SNES copier (skip 512), and later Lynx (64)/A7800 (128) are computed in the same pass by starting a second hasher set once the header is detected in the first chunk, and stored in a `blob_fingerprints` table `{blob_id, kind, offset, crc32, md5, sha1}` — a derived sub-range fingerprint, not identity. Phase 2 computes headerless only for `nes` and `snes`.** — Reversibility: reversible (backfill job can compute missing columns; costs one re-read of the blob store).
- **B-07 (draft): Archives (detected by magic, not extension: zip `PK\x03\x04`, 7z `7z\xBC\xAF\x27\x1C`, rar, gzip, xz, zst) are accepted as opaque blobs with system unassigned, receipt code `archive_not_opened` in the "kept as-is" family; the IMPT-01 preflight states it before copy ("N archives will be kept exactly as-is but can't be played until archive support ships — extract first if you want them playable"). Needs Attention groups them as one item per import ("312 archives kept unopened") with resolutions retain-as-custom / exclude. The archive-security gate is a deferred spike (not a Phase 2 plan); Phase 2 writes its acceptance criteria into the phase context.** — Reversibility: reversible (bytes are retained; a later phase inspects them in place).
- **B-08 (draft): System assignment = extension map → header confirm (upgrade or contradict) → user override. Lives on `asset_set.system_id` plus `asset_set.system_source ∈ extension|header|reference|user`; each evidence source's opinion stays in `recognition_evidence`. Contradiction (extension says one, header says another) → Needs Attention "confirm system" with both shown. Vocabulary is a stable lowercase id registry frozen like `EntityKind`: `gba gb gbc nes snes md psx` (+ `unknown`); adapter-facing names (RetroArch core ids, ES-DE folders) are a client mapping, not server truth. User correction writes an override row + audit_log entry and sets `system_source = user`; prior values remain in evidence.** — Reversibility: one-way for the id strings (they go into export manifests and the client journal); reversible for everything else.
- **B-09 (draft): Display title = No-Intro filename parse when it succeeds (`Title (Region) (Languages) (Version) (Devstatus) (Additional) [Status]` → `display_title` + `tags`), else the sanitised filename stem; the cartridge-header title (GBA 12-char uppercase) is recorded as evidence but never preferred. Sanitising for UI: original name kept byte-exact in `source_file.original_name` (bytea-safe), display form NFC-normalised, control chars/bidi overrides/zero-width stripped, capped at 200 code points with an ellipsis, rendered only through HEEx escaping. User can set `title_override` (B-05 override row).** — Reversibility: reversible.
- **B-10 (draft): `catalogue` journal payload (entity_id = asset_set UUID) = `{id, system, status ∈ complete|incomplete, display_title, title_source, tags{region,languages,version,dev_status}, manifest_version, members:[{ordinal, role, required, sha256, size, name}], recognition{status ∈ no_reference|exact|header|filename|user, confidence, provider, provider_version, reference_name}, updated_at}`; tombstone on exclude/delete. Source paths, legacy hashes, and provenance stay out of the client payload (privacy; not needed to launch). Unknown keys are ignored by clients (D-18 additive rule).** — Reversibility: one-way (this is the client-facing catalogue contract Phase 3 builds on; additions are fine, renames are not).

---

## B1 — The v1 supported-format allowlist

### Lenses
- **Security:** Only fixed-offset reads of the first ≤ 64 KiB (and for SNES a few candidate offsets) are needed for every Tier A/B format except CUE. No decompression, no seeking beyond bounded offsets, no recursion. A "validator" that only checks magic still runs on attacker bytes; keep it pure-binary pattern matching in Elixir (no NIFs, no ports) and fuzz it (QUAL-02 wants adversarial fixtures per enabled parser).
- **Product/UX:** The first adopter has a GBA file (Phase 3) and probably a Redump PS1 set (IMPT-04). Everything else should still be *kept* ("kept as-is") without shame or noise. The receipt must not imply a file is broken because Playstead doesn't know it.
- **Elixir idiom:** One `Playstead.Formats` registry (compile-time map of system → extensions, validator module, header tier) plus per-format modules implementing a `Playstead.Formats.Validator` behaviour (`sniff/1` on the head chunk, `evidence/1`). Pattern-match binaries; return tagged tuples; never raise on bad input.
- **Durability:** Validation happens in the Oban import worker after the blob is committed to storage, in the same transaction as the receipt. A validator crash must not lose the blob — the blob write and the recognition write are separate steps with the blob step idempotent by sha256.
- **SRE:** No external tooling (`file`, `7z`) in the image; the release runs as `nobody` and must not need new binaries.
- **Data model:** `format_tier` is evidence on `recognition_evidence`, not a column on `blob` — the same bytes may be validated differently by a future validator version.
- **Preservation domain:** Signature reliability, verified 2026-08-28:
  - GBA: fixed byte `0x96` at 0xB2, complement at 0xBD over 0xA0..0xBC (init 0x19, negate), Nintendo logo 156 bytes at 0x04 (GBATEK). Homebrew without `gbafix` fails the complement while still running in mGBA — so failure is a Needs-Attention note, never a quarantine.
  - GB/GBC: logo 0x104..0x133, header checksum 0x14D over 0x134..0x14C (Pan Docs). Reliable.
  - NES: `NES\x1A` (iNES/NES 2.0; NES 2.0 when byte7 & 0x0C == 0x08) (nesdev). Reliable, but *headerless* .nes files exist and No-Intro publishes both headered and headerless DATs.
  - MD: `SEGA MEGA DRIVE`/`SEGA GENESIS` at 0x100 (TMSS requires the `SEGA` prefix) (Plutiedev). Reliable for .bin/.md; `.smd` (interleaved with 512-byte header) is NOT validated in Phase 2 — kept as-is.
  - SNES: no magic. Internal header at 0x7Fxx (LoROM) / 0xFFxx (HiROM) / 0x40FFxx (ExHiROM), checksum⊕complement == 0xFFFF; copier header when size % 1024 == 512 (RetroAchievements uses "512 more than a multiple of 8 KB"). Heuristic — mark Tier B.
  - PS1: CUE is text; BIN is raw 2352-byte sectors, MODE2/2352 first track; RetroArch identifies the system by reading the first data track for magic and the serial from SYSTEM.CNF. Phase 2 does NOT read inside the BIN (that is sector-level parsing = later); CUE structure + `.bin` size % 2352 == 0 is the Tier B check.
  - CHD: magic `MComprHD` at 0, header length/version, raw SHA-1 at 0x40, raw+meta SHA-1 at 0x54, parent SHA-1 at 0x68 (0 = no parent) for v5 (MAME `chd.h`). Header-only read is safe; hunks are never decompressed in Phase 2. Non-zero parent SHA-1 → `incomplete set` with role `parent` missing.

### Prior art
- igir detects headers for A78, LNX, iNES/NES 2.0, FDS, SMC and computes both headered and headerless checksums; SNES "SFC" and Lynx "LYX" headerless variants use different extensions (https://igir.io/roms/headers/).
- RetroAchievements hashes GB/GBC/GBA/MD as full-file MD5, skips 16 bytes for `NES\x1A`, 512 for SNES copier headers, 64 for `LYNX\0`, 128 for `\1ATARI7800`; PS1 hashes the primary executable named in SYSTEM.CNF (https://docs.retroachievements.org/developer-docs/game-identification.html).
- RetroArch's scanner uses CRC32 for cart systems and serial extraction from disc tracks for PS1/Saturn/GC/Wii; unmatched content is still playable, just missing from the Explore menu (https://docs.libretro.com/guides/roms-playlists-thumbnails/, https://deepwiki.com/libretro/RetroArch/7.5-playlists-and-database).
- RomM hashes CRC32/MD5/SHA-1 (+RA hash) and lets the first provider that recognises by hash or filename win (https://docs.romm.app/5.1.0/getting-started/first-scan/).

### Options
| Option | Pros | Cons / footguns | Who it hurts |
|---|---|---|---|
| A. Minimal: `gba` + `psx` only | Smallest fuzz surface; exactly what Phases 3/IMPT-04 need | GB/GBC/NES/MD have *stronger* signatures than PSX and cost ~30 lines each; users with a mixed folder see 5 of 7 systems "not recognized" | First adopter with a mixed handheld folder |
| B. Seven ids, two tiers (recommended) | Covers the common cartridge systems whose signatures are cheap and reliable; honest tiering | SNES and PSX are heuristics — must be labelled as such in evidence; more fixtures | Nobody materially; slightly more test surface |
| C. Broad extension map (N64, SMS, GG, PCE, …) without validators | Users see "system: N64" immediately | "Supported" would mean "we guessed from extension"; contradicts "narrow magic-byte-validated" lock; every extra system id becomes protocol vocabulary | Future phases inherit unvalidated ids |

### Adversarial pass (Option B)
- Crash mid-validation: blob already committed by sha256; receipt row missing → Oban retry re-runs validation idempotently (unique job on `source_file.id`).
- Malicious input: a file claiming `.gba` with a valid complement but garbage logo — passes (we don't verify the logo hash); that is fine because validation only assigns system, never executes. A 10-byte `.nes` file → validator must pattern-match with size guards; fuzz with truncated headers.
- Huge collection: validation is O(1) per file (head chunk). SNES candidate-offset reads need up to 3 seeks — fine.
- Slow disk: validation is done from the head chunk already read for hashing; no second open for Tier A.
- User mistake: `.bin` is ambiguous (MD ROM vs PS1 track). Rule: `.bin` with `SEGA` at 0x100 → `md`; `.bin` referenced by a CUE in the same batch → `psx` track; lone `.bin` with size % 2352 == 0 → "kept as-is; looks like a disc track without its .cue" → Needs Attention "attach missing companion (cue)".
- Future Mac client: receives `system` id + validation tier as recognition status; never needs to re-validate.
- Export/reimport: sidecar carries system id; reimport re-validates anyway and must agree — a disagreement is itself a test.

### One-shot recommendation
**B-01** as summarised. Rationale: GB/GBC/NES/MD signatures are cheap, deterministic and hardware-enforced (TMSS/boot ROM), so excluding them would make the receipt *less* honest for common files, while SNES/PSX carry an explicit "structure-validated" tier so nobody mistakes a heuristic for a signature. Builds on: narrow-allowlist lock, sha256 identity, "unknown files are accepted but marked" (TECHNICAL-RISKS). Reversibility: reversible. Claude's discretion: whether CHD header-read lands in Phase 2 or CHD is simply "kept as-is"; exact chunk size for the head read.

---

## B2 — Which multi-file format proves IMPT-04 and the member model

### Lenses
- **Security:** CUE is the only text parser in Phase 2. Threats: huge file, deeply quoted names, absolute/UNC paths, `..`, NUL/control bytes, non-UTF-8 bytes, 10,000 FILE lines, `FILE` types that imply decoding (WAVE/MP3). Mitigate with size cap, line cap, whitelist grammar (`FILE "<name>" BINARY`, `TRACK nn <mode>`, `INDEX nn mm:ss:ff`, `PREGAP/POSTGAP`, `REM`, `FLAGS`, `CATALOG`, `TITLE/PERFORMER` ignored), and reject-with-evidence on anything else.
- **Product:** A Redump PS1 rip is "one game" to the user: `Game.cue` + `Game (Track 1).bin` … `(Track 12).bin`. Dropping only the `.cue` must produce a clear "incomplete set — 12 members missing" receipt, not 1 new asset + silence. Dropping the whole folder must produce ONE asset_set and ONE receipt line ("Game — complete, 13 files").
- **Elixir idiom:** `Playstead.Formats.Cue.parse/1` returns `{:ok, %Cue{files: [%{name, type, tracks: [...]}]}} | {:error, reason}`; pure function over a binary; property-tested with StreamData.
- **Durability:** Members arrive in any order in a staged import. The asset_set is created when the descriptor is seen; members attach by `declared_name` match within the same import session; completeness is recomputed in the same transaction as each member attach. Crash between attaches leaves `incomplete` — which is the truthful state and self-heals on retry/reconcile.
- **Data model / protocol:** roles must survive into the sidecar manifest (PORT-02) and the client journal (B10). `ordinal` is the CUE FILE order (0 = descriptor). `export_path` = the declared name (validated) so export reproduces a launchable folder.
- **Preservation domain:** Redump PS1 CUEs reference one BIN per track (`FILE "X (Track 01).bin" BINARY` / `TRACK 01 MODE2/2352` / `TRACK 02 AUDIO` with INDEX 00 pregap) (binmerge README, Emulation General Wiki). Some emulators only handle single-BIN; that is a client concern. Multi-disc = M3U listing CUEs (ES-DE "directories interpreted as files" convention). CHD folds tracks into one file; parent/child via parent SHA-1 in header.

### Prior art
- putnam/binmerge documents the multi-track Redump CUE shape and why tools mis-parse it (https://github.com/putnam/binmerge).
- RetroArch's `task_database_cue.c` parses the CUE, reads the first data track for magic, then serial (https://deepwiki.com/libretro/RetroArch/7.5-playlists-and-database).
- ES-DE hides BIN entries and treats a `.m3u` directory as one game (https://emudeck.github.io/tools/steamos/es-de/).
- MAME CHD: parent SHA-1 in header; diff CHDs are unusable without the parent (https://docs.mamedev.org/tools/chdman.html).

### Options
| Option | Pros | Cons / footguns | Who it hurts |
|---|---|---|---|
| A. CUE+BIN (recommended) | Canonical ordered-members case; text descriptor is parseable safely; Redump PS1 is the realistic Mac-user set; exercises `required`, `ordinal`, `declared_name`, incomplete-set receipt | Must parse text; `.bin` ambiguity; users with merged single-BIN cues work too (1 track member) | Nobody |
| B. M3U multi-disc | Also ordered members | M3U is a playlist convention, not a format; nests CUE parsing anyway; disc order is only a list of names | Delays the real proof |
| C. CHD parent/child | Binary header only, no text parsing | Rare in personal libraries; parent/child is a dependency not an ordered manifest; hunk verification needs decompression (gate) | Proves less of IMPT-04 |

### Adversarial pass (Option A)
- Crash mid-write: descriptor blob committed, asset_set row present, zero members attached → status `incomplete`; reconcile job re-scans the session's source_files and attaches. Idempotent by `(asset_set_id, ordinal)` unique.
- Malicious: CUE with `FILE "../../etc/passwd" BINARY` → rejected as `descriptor_invalid`, blob still kept, Needs Attention. CUE naming 99 tracks each 4 GiB → we only *record* names; no reads. Two CUEs in one folder referencing the same BIN → both asset_sets reference the same blob (allowed — blobs are shared; export writes the file once per set folder).
- Huge collection: 2,000 PS1 games → 2,000 CUE parses of ≤64 KiB; trivial.
- User mistake: filename case mismatch (`track 01.bin` vs `Track 01.bin`) on a case-sensitive server → match case-insensitively with evidence "matched ignoring case"; export uses the CUE's declared name so the exported set is launchable.
- Future Mac client: member list with `role`, `required`, `sha256`, `size`, `name` is exactly what CACH-04 needs ("launch only after every required member verifies").
- Export/reimport: sidecar lists members with declared names → reimport rebuilds identical asset_set (PORT-02 "no duplicate logical records" relies on the asset_set UUID in the sidecar plus member sha256 equality).
- Household: asset_sets are per user_id; a shared blob is still deduped within the tenant only (locked).

### One-shot recommendation
**B-02** as summarised. Rationale: CUE+BIN is the only multi-file case that is simultaneously common, safely parseable as bounded text, and rich enough to exercise every IMPT-04 word (ordered, required, readiness). Builds on: manifested-asset-graph model in TECHNICAL-RISKS, exact-byte custody, export sidecar lock. Reversibility: costly. Claude's discretion: exact CUE grammar tolerance (BOM, CRLF, Latin-1 fallback), and whether `TRACK` modes beyond MODE1/2048, MODE1/2352, MODE2/2352, AUDIO are accepted or noted.

---

## B3 — Recognition pipeline with NO DAT installed

### Lenses
- **Security:** Header fields are attacker-controlled strings (GBA title 12 bytes, MD serial 14 bytes). Store as-is in evidence (bytea/escaped), render sanitised (B9). Never use header fields to build paths or queries.
- **Product:** With no DAT, the honest state for a valid GBA file is *"Game Boy Advance · header says POKEMON EMER (BPEE) · no reference database installed"*. That is not a problem to fix; it must not appear in Needs Attention. Only contradictions, failures, and incompleteness do.
- **Elixir idiom:** Providers implement `Playstead.Recognition.Provider` (`@callback recognise(blob_facts, evidence) :: {:ok, [Evidence.t()]}`); `HeaderEvidence` is the first provider; a `Null` provider is unnecessary — "no provider matched" is represented by `recognition.status = :no_reference`.
- **Durability:** Recognition rows are written in the import transaction; re-running recognition later (new provider) appends rows with a new `provider_version` and re-derives the summary.
- **Preservation domain:** Evidence available at import per format (all from fixed offsets): GBA title/game code (UTTD: type, abbreviation, region letter)/maker/version/complement OK; GB title/CGB/SGB flags/cart type/ROM size byte/header checksum OK; NES PRG/CHR sizes, mapper, mirroring, battery, trainer, NES 2.0; SNES internal title, map mode, checksum valid, copier header present; MD system name, copyright, serial `GM xxxxxxxx-xx`, region; CUE track table; size facts. No-Intro filename parse (B9) is *also* evidence, of the weakest kind.

### Prior art
- RetroArch: no DB match → still playable, no thumbnails (https://docs.libretro.com/guides/roms-playlists-thumbnails/).
- RomM: providers in priority order; first hash/filename hit wins; unmatched ROMs remain browsable (https://docs.romm.app/5.1.0/getting-started/first-scan/).
- Hasheous: online hash lookup proxy with CRC/MD5/SHA-1/SHA-256 (https://github.com/gaseous-project/hasheous) — noted, but sending hashes of a private library to a third party is off the Phase 2 path (privacy; network off the critical path).

### Outcome decision table (no matcher)
| IMPT-03 outcome | Decided by | Needs Attention? |
|---|---|---|
| new asset | sha256 not in tenant AND system assigned | no |
| exact duplicate | sha256 in tenant AND same (name, import origin) — idempotent replay/re-drop | no |
| alias | sha256 in tenant AND different name/path → new source_file | no (receipt line only) |
| variant (possible) | different sha256, same system, same header serial/game code as existing asset_set | no; receipt says "possible variant of X (same header code)"; certainty needs a reference |
| incomplete set | descriptor present, ≥1 required member missing | yes — attach companion |
| kept as-is, not recognized | no validator matched, no extension mapping, not an archive | yes, grouped per import — correct system / retain as custom / exclude |
| header check failed | extension mapped to a system but validator failed (bad complement, wrong magic) | yes — confirm system / retain as custom |
| archive, not opened | magic = archive (B7) | yes, grouped — retain / exclude |
| quarantined | policy/limit failure (size cap, zero bytes, parser crash caught) — blob retained under quarantine flag | yes — retry safe processing / exclude |
| safely failed | I/O error, disk full, hash mismatch on verify-after-copy — nothing durable created except the receipt | yes — retry |
| "supported format, no reference installed" | any assigned system with `recognition.status = no_reference` | **never** |

### Options
| Option | Pros | Cons | Who it hurts |
|---|---|---|---|
| A. Header-evidence provider + status `no_reference` (recommended) | Honest, quiet, offline; produces useful titles/codes today | "variant" and "verified" remain unavailable without B5 | Users expecting DAT verification |
| B. Route every unmatched file to Needs Attention | Nothing hidden | Floods the inbox on day one (every file); violates quiet-by-default | First adopter |
| C. Online lookup (Hasheous) as default provider | Real matches without admin DAT work | Sends private hashes off-box; network on import path; terms unclear | Privacy-minded self-hosters |

### Adversarial pass (Option A)
- Crash: evidence rows and receipt are in one transaction; partial evidence cannot exist.
- Malicious: header strings with NULs/bidi — stored raw, rendered sanitised. 200 files with identical GBA game code → "possible variant" fan-out grows O(n) per import; cap the receipt to "possible variant of N items" and list top 5.
- Huge collection: header evidence is per-file O(1).
- User mistake: user drops the same file twice → second is "exact duplicate", receipt links to the first; no new rows except a receipt.
- Future Mac client: needs only `recognition.status` + `display_title`.
- Future S3: no filesystem assumptions; validators run on the head chunk streamed during upload.

### One-shot recommendation
**B-03** as summarised. Rationale: the no-DAT case is the *default* Phase 2 experience, so the quiet path must be the honest header-evidence path, with Needs Attention reserved for contradictions and incompleteness. Builds on: "recognition is not an admission-control gate", quiet-by-default, evidence-not-rewrite. Reversibility: reversible.

---

## B4 — Definitions: alias / variant / patched / header-stripped / overdump

### Lenses
- **Product:** Users think in releases, not bytes; the receipt must not claim more than bytes can prove. "Alias" is fully decidable (sha256). "Variant" is a release-level claim → only a reference or a serial can support it. "Patched" is a claim about lineage → only a reference (base hash) supports it; patch *files* are detectable.
- **Preservation domain:** IPS begins `PATCH`, UPS `UPS1` (+ source/target CRC32 at end), BPS `BPS1` (+ source/target/patch CRC32 at end) (https://github.com/blakesmith/rombp/blob/master/docs/bps_spec.md, http://justsolve.archiveteam.org/wiki/UPS_(binary_patch_format)). A BPS/UPS patch therefore carries the *base* CRC32 — which means, with B6 legacy hashes, Phase 2 can say "this patch targets a ROM with CRC32 X" and, if such a blob exists in the library, link them as a `patch` member of a derived-set *candidate* without applying anything (no auto-patching — locked).
- **Overdump/header-stripped:** cart ROMs are normally powers of two (some MD/SNES aren't); NES without `NES\x1A` but `.nes` extension → "no iNES header (headerless)"; SNES size % 1024 == 512 → "512-byte copier header present". These are evidence lines. An "overdump" verdict needs a reference size.

### Options
| Option | Pros | Cons |
|---|---|---|
| A. Strict definitions; "possible variant" only via header serial; patches as blobs (recommended) | Honest; every claim traceable to evidence | "variant" rarely fires in Phase 2 |
| B. Treat same-parsed-title filenames as variants | Fires often | Filename is the weakest evidence; false claims on renamed files |

### Adversarial pass
- A patch file with a forged BPS trailer pointing at a random CRC32 → only creates a *candidate* link, never a derived asset; the link shows "patch says its base is CRC32 X; matching file in your library: Y" — still truthful.
- Header serial collisions across regions (GBA game code last letter is region, so `BPEE` vs `BPEP` differ) — fine; MD serial `GM 00001009-00` is shared across revisions — "possible variant" is exactly right.

### One-shot recommendation
**B-04** as summarised. Rationale: the receipt vocabulary is a promise; strict definitions keep every word provable from stored evidence and leave a clean slot for a matcher to upgrade "possible" to "verified". Builds on: receipt vocabulary lock; no auto-patching; three-layer identity. Reversibility: reversible.

---

## B5 — Matcher/provider contract & DAT-pack import

### Lenses
- **Security:** A DAT is untrusted XML. Use a SAX/streaming parser (Saxy) with no DTD/external entity processing, cap file size (e.g. 64 MiB), entries (e.g. 500k), name lengths; never eval the `header` block; strip control chars from names. ClrMamePro `.dat` (non-XML) is a second grammar — defer; accept Logiqx XML only.
- **Product:** Admin action in the console: "Add reference database (DAT file)". The user supplies the file, picks a system id (or accepts the header's), types/accepts a source URL and a license claim. From then on, imports for that system can show "verified: Pokémon - Emerald Version (USA, Europe)" with confidence `exact`. Without this, "alias or variant" and "patched" outcomes in IMPT-03 are mostly theoretical in Phase 2.
- **Elixir idiom:** `Playstead.Recognition.Provider` behaviour; providers registered in config; matching by `(size, sha1)` first, `(size, crc32)` fallback (DATs carry CRC/MD5/SHA-1, not SHA-256 — Logiqx DTD; some No-Intro DATs now include sha256 — treat as bonus).
- **Durability:** Pack import is an Oban job with progress; the pack row is written first; entries are inserted in batches with `on_conflict: :nothing` on `(pack_id, sha1, size)`; re-running recognition for existing blobs of that system is a separate reconcile job.
- **Data model:** `recognition_packs{id, user_id, system_id, name, upstream_name, upstream_version, source_url, retrieved_at, file_sha256, license_claim, license_note, transform_version, entry_count}`; `recognition_entries{pack_id, game_name, rom_name, size, crc32, md5, sha1, sha256?, status, headerless bool}`; `recognition_evidence{source_file_id/blob_id, provider, provider_version, pack_id?, entry_id?, kind, fields jsonb, confidence}`; `recognition_overrides{asset_set_id, user_id, field, value, reason, audit_entry_id}`.
- **Licensing (verified 2026-08-28):** Redump: "This information is considered public domain to be used however people see fit" (https://redump.info/about); libretro-database: CC BY-SA 4.0 with attribution + share-alike (https://github.com/libretro/libretro-database/blob/master/LICENSE); No-Intro: the site publishes anti-piracy and "informational web site" statements but no data license I could find on datomatic or the wiki (https://datomatic.no-intro.org/, https://wiki.no-intro.org/index.php?title=Database_Navigation_Guide) — record `license_claim = unstated`; never bundle; the Redump forum thread on redistribution was unreachable today (connection refused) and should be re-checked before any bundling decision.
- **Confidence model:** `exact` (size + sha1 or crc32 match, and for a set every required member matches) > `header` (serial/game code) > `filename` (No-Intro parse) > `user` (override — shown as "set by you", not as a confidence rank). Store the evidence that produced each.

### Prior art
- igir matches on CRC32 by default and adds MD5/SHA-1 only when a DAT needs them (https://github.com/emmercm/igir/issues/818); headered vs headerless DATs match different files (https://github.com/emmercm/igir/issues/281).
- RomM issue #187 asked for No-Intro DAT integration via local DAT download + hash cross-reference (https://github.com/rommapp/romm/issues/187).
- Logiqx `datafile.dtd`: `rom` has `name size crc md5 sha1 status(baddump|nodump|good|verified)` (https://github.com/Logiqx/logiqx-www/blob/master/Dats/datafile.dtd).

### Options
| Option | Pros | Cons / footguns | Who it hurts |
|---|---|---|---|
| A. Schema + behaviour + HeaderEvidence only; no DAT import | Smallest scope; nothing to license | "verified/variant/patched" untestable end-to-end in Phase 2; Phase 3 BIOS validation (PLAY-03) re-invents hash-matching | Owner testing IMPT-03 honestly |
| B. A + admin Logiqx DAT-pack import as a droppable last plan (recommended) | Makes every IMPT-03 word real; provenance/licensing recorded from day one; reuses the streaming hashes | One XML parser to fuzz; one more console screen; No-Intro license unstated | Slight scope growth |
| C. Online provider (Hasheous/libretro-db fetch) | No admin work | Network on import path; third-party sees hashes; CC BY-SA duties for libretro-db | Privacy; offline posture |

### Adversarial pass (Option B)
- Crash mid-pack-import: pack row `status = importing`; entries partially inserted; job retries idempotently; matching only uses packs with `status = ready`.
- Malicious DAT: billion-laughs → SAX with entities disabled; 10 GB file → size cap; duplicate entries → unique index; names with control chars → sanitised for display, raw kept.
- Huge collection: recognition reconcile runs per pack in batches keyed by `(size, sha1)` index; O(n log n).
- User mistake: importing a headerless NES DAT while files are headered → matches via `blob_fingerprints` headerless sha1 (B6), evidence says "matched headerless".
- Future S3: nothing touches the blob store.
- Household: packs are per user_id (no cross-user sharing of even metadata in v1; can be relaxed later).
- Export/reimport: recognition is not exported (bytes + manifest only); reimport re-derives it — deterministic given the same packs.

### One-shot recommendation
**B-05** as summarised. Rationale: the provider behaviour and evidence/override split are cheap and load-bearing; a single Logiqx importer turns IMPT-03's "verified/variant/patched" from vocabulary into demonstrable outcomes and gives Phase 3 a hash-match primitive for BIOS. Builds on: pluggable matcher decision, no bundled payload, evidence-never-rewrite. Reversibility: reversible (importer) / one-way (evidence vs override split). Claude's discretion: XML library, batch sizes, exact caps. **Owner question:** is the DAT-pack importer inside Phase 2 or explicitly deferred?

---

## B6 — Legacy hashes

### Lenses
- **Performance/SRE:** `:crypto.hash_init/update/final` for sha256/md5/sha and `:erlang.crc32/2` (incremental) run in one `File.stream!` / upload-chunk pass; SHA-256 dominates (with SHA-NI it is the fastest of the three on modern x86; without, MD5+SHA-1 add ~50–70%). Import is background Oban work; the cost is invisible for cart ROMs and acceptable for 700 MB PS1 tracks. Recomputing later means re-reading the whole blob store — on a 2 TB volume that is the expensive path.
- **Data model:** Full-file hashes are 1:1 with the immutable blob → columns on `blob` (`crc32 :integer`, `md5 :binary`, `sha1 :binary`). Headerless/sub-range fingerprints are many:1 and version-dependent → `blob_fingerprints`.
- **Preservation domain:** No-Intro publishes headered *and* headerless NES DATs; SNES DATs are headerless (.sfc); Lynx/A7800 currently headerless-only with a community push for headered (https://forum.no-intro.org/viewtopic.php?t=7652); RetroAchievements strips headers as in B1. A BIOS validator (Phase 3) needs MD5/SHA-1 because libretro BIOS docs publish MD5.
- **Durability:** Hash columns are written with the blob row in the same transaction as the receipt; the file is fsynced and renamed into `objects/sha256/ab/<hash>` before the row commits; a crash before commit leaves an orphan object that a sweeper can reclaim by sha256 (the object name is self-verifying).

### Options
| Option | Pros | Cons |
|---|---|---|
| A. All four in one pass at import; headerless for nes/snes in the same pass (recommended) | One read; DAT/BIOS ready; reimport verification can compare all four | ~1.5× CPU vs sha256-only; 3 more columns |
| B. sha256 only; compute legacy on demand when a pack is imported | Fastest import | Every DAT import re-reads the store; RA/BIOS features later pay again |
| C. Compute legacy in a separate low-priority Oban queue after import | Import latency unchanged | Two reads of every blob; more state (`hashes_pending`) |

### Adversarial pass (Option A)
- Crash after object rename, before row commit: orphan object; sweeper verifies sha256 of the file name matches content before deleting or adopting.
- Disk full mid-copy: write fails → temp file removed → receipt "safely failed"; no row.
- Slow disk: single pass is the minimum possible I/O.
- Header detection error (e.g. SNES 512-rule false positive on a genuinely odd-sized ROM): the fingerprint row says `kind = headerless_smc, offset = 512` — a later DAT match on the full-file hash still works; nothing is lost.
- S3: hashes are computed on the upload stream; multipart ETag is never used as identity (locked).

### One-shot recommendation
**B-06** as summarised. Rationale: the marginal CPU is small and paid once, while re-reading the whole store later is the expensive, disk-thrashing path; storing full-file hashes on `blob` and sub-range fingerprints separately keeps identity clean. Builds on: three-layer identity, verify-after-copy. Reversibility: reversible (backfill). Claude's discretion: chunk size, whether CRC32 is stored as integer or hex.

---

## B7 — Archive handling in Phase 2

### Lenses
- **Security:** Never open archives (locked). Detect by magic so renamed archives can't masquerade as `.gba`. Storing an archive opaque is exactly as safe as storing any other blob: no code runs on it.
- **Product:** Many users' first folder is zipped No-Intro sets. Options are: (1) turn them away at preflight; (2) keep them, be clear they aren't playable yet. The Import contract's preview step (IMPT-01) is where the honesty belongs. Needs Attention must not get one item per zip.
- **Durability/SRE:** Opaque archives consume volume space with no play value; users must be told at preflight ("this will use 3.2 GB for files that can't be played yet"). Excluding later from Needs Attention releases the blob if no other source_file references it (subject to Area-? deletion semantics).
- **Data model:** `recognition.status = archive_not_opened`, `system_id = unknown`, `format_evidence = {container: zip|7z|rar|gzip|xz|zstd}`.

### Prior art
- OWASP File Upload Cheat Sheet: validate type by content, restrict archives, bound decompression before extraction (https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html).
- igir/RomVault read inside archives by default — the very behaviour our gate exists to make safe first.
- RetroArch scans inside zips for CRC; Hasheous reads CHD signatures — both later-phase capabilities for us.

### Options
| Option | Pros | Cons / footguns | Who it hurts |
|---|---|---|---|
| A. Reject at preflight ("extract first") | Zero unplayable bytes stored; simplest | Turns away the most common first folder; "managed copy" refuses a file that is perfectly safe to keep | Zipped-set owners |
| B. Accept opaque + preflight warning + grouped Needs Attention (recommended) | Bytes safe; honest; later inspection is in place; matches the "retain archives opaque" lock | Volume use with no play value until the gate; must group inbox items | Disk-constrained self-hosters (mitigated by preflight size) |
| C. Zero-inspection quarantine bucket | Segregates them | "Quarantine" implies suspicion; violates "never call bytes bad" | Users' trust |

### The gate: discrete plan vs deferred spike
Phase 3 needs GBA files, not archives; nothing in Phase 2's success criteria requires opening one. Recommend a **deferred spike** (own phase-level flag remains), but write its acceptance criteria into 02-CONTEXT now: corpus = path traversal (`../`, absolute, Windows drive, NUL), symlink/hardlink entries, nested archives ≥ 5 deep, zip bomb (42.zip-style and overlapping-entry), 100k-entry archive, declared-size lies, CRC-mismatch entries, encrypted entries; limits = wall-clock, memory (separate BEAM node or OS process with rlimits — not just a Task), recursion 0, entry count, per-entry and total expanded size, expansion ratio; run as `nobody` in a tmpfs; every fixture must produce a receipt without touching the blob store.

### Adversarial pass (Option B)
- Crash: same as any blob.
- Malicious: a zip renamed `.gba` → magic says archive → opaque; a polyglot (valid GBA header *and* trailing zip) → GBA validator wins (head bytes), archive magic is not at offset 0 — fine, we never open it. 
- Huge collection: 5,000 zips → one grouped inbox item with counts and a "show files" disclosure.
- User mistake: user expected them playable → preflight told them; the inbox says how to fix (extract and re-import; the originals are untouched).
- Future gate: inspection runs over blobs already in custody; no re-import needed; the archive can then *also* become a `container` member of derived asset_sets (deferred idea).

### One-shot recommendation
**B-07** as summarised. Rationale: retaining bytes is the product's promise and costs nothing in safety; honesty belongs at preflight and in one grouped inbox item, not in 5,000 alerts or a refusal. Builds on: "retain archives opaque" and "Archive preservation: yes, opt-in" locks; quiet-by-default. Reversibility: reversible. **Owner question:** accept-opaque (recommended) vs reject-at-preflight — this is a visible product stance.

---

## B8 — System assignment and the system vocabulary

### Lenses
- **Data model:** `asset_set.system_id` is the working truth used by export paths, filters, and the client; `system_source` records who said so; evidence keeps every opinion. Ids are strings validated against a frozen registry module (mirror `Playstead.Sync.EntityKind`): `Playstead.Systems` with `all/0`, `valid?/1`, display names, and extension map.
- **Protocol:** Ids appear in the sidecar manifest and the catalogue journal → treat as published vocabulary (D-18 additive rule: add, never rename).
- **Product/accessibility:** Display names are full ("Game Boy Advance"), never ids; correction UI is a select with only registered systems + "Keep as custom content (no system)".
- **Preservation domain:** ES-DE folder names (`gba`, `gb`, `gbc`, `nes`, `snes`, `megadrive`/`genesis`, `psx`) and RetroArch playlist names ("Sony - PlayStation") are *mappings*; our ids should be short, unambiguous and not tied to either. `md` avoids the Genesis/Mega Drive naming split; `psx` is the near-universal id.

### Options
| Option | Pros | Cons |
|---|---|---|
| A. Registry of 7 + `unknown`; `system_id` on asset_set with `system_source` (recommended) | One place to query/filter; auditable; frozen like EntityKind | Adding a system requires a release (fine — validators do too) |
| B. System only in recognition rows, derived at read time | "Pure" evidence model | Every list query joins evidence; no clear place for user truth |

### Adversarial pass
- Contradiction: `.gba` extension, NES magic → Needs Attention "confirm system"; nothing assigned until resolved (system `unknown`, receipt "kept as-is — header check failed").
- User sets wrong system: override row + audit entry; client sees new `system` via journal upsert; export path changes deterministically (export layout is generated, not preserved — locked).
- Reimport of an export whose sidecar says `system: gba` but header says NES → header wins over sidecar, contradiction flagged; sidecar is optimisation only (locked).

### One-shot recommendation
**B-08** as summarised. Reversibility: one-way for id strings, reversible otherwise. Claude's discretion: display-name table, whether `unknown` is NULL or a literal id (recommend literal for export stability).

---

## B9 — Display title derivation and filename safety

### Lenses
- **Security:** Filenames are attacker bytes: invalid UTF-8, bidi overrides (`U+202E` makes `exe.gba` read as `abg.exe`), zero-width joiners, 4 KiB names, NUL. Keep raw bytes for provenance; derive a display form; never log the raw name (QUAL-03).
- **Product/accessibility:** Screen readers should hear "Pokémon Emerald Version, USA, Europe" not "Pokemon_-_Emerald_Version_(USA,_Europe).gba". Tags become filter chips (LIBR-02 later).
- **Preservation domain:** No-Intro grammar: `[BIOS] Title (Region) (Languages) (Version) (Devstatus) (Additional) (Special) (License) [Status]`, Title+Region mandatory (https://wiki.no-intro.org/index.php?title=Naming_Convention). bunkai (SnowflakePowered) is a non-regex parser for No-Intro/TOSEC/GoodTools worth mirroring in Elixir with a hand-written tokenizer, not a regex (https://github.com/SnowflakePowered/bunkai).

### Options
| Option | Pros | Cons |
|---|---|---|
| A. Parse No-Intro tags → title + tags; fallback to sanitised stem (recommended) | Best default titles for the majority of curated sets; tags for free | Parser must be tolerant; wrong parses are still evidence (fixable via override) |
| B. Raw stem always | Zero risk of wrong parse | Ugly; no tags; users retype everything |
| C. Prefer header title | Comes from the bytes | 12-char uppercase `POKEMON EMER` is worse than the filename |

### Adversarial pass
- 4 KiB filename with nested parentheses: tokenizer bounded by length; unbalanced → treat as plain stem.
- Non-UTF-8 name from a Linux drop: store bytes, display with replacement chars and a note "filename contains characters that can't be displayed".
- Two files parse to the same title: fine — titles are not identity.

### One-shot recommendation
**B-09** as summarised. Reversibility: reversible. Claude's discretion: exact sanitiser list beyond C0/C1/bidi/zero-width; the 200-code-point cap.

---

## B10 — Recognition/identity fields published to the Phase 3 client via `catalogue`

### Lenses
- **Protocol:** `Playstead.Sync.EntityKind` already freezes `catalogue`; `Entry.payload` is a map; `Snapshot` adds a materialisation branch per domain. The payload shape is therefore the only new contract, and it must be additive-only after Phase 2.
- **Client needs (Phase 3 CACH-04/PLAY-02/LIBR-01/02):** what to show (title, system, tags, recognition status/confidence), what to download and verify (member sha256 + size + role + required + ordinal + name for on-disk materialisation), whether the set is launchable at all (`status`), and change detection (`updated_at`, tombstones).
- **Privacy:** never publish source paths, original filenames beyond the sanitised member `name`, or legacy hashes (unneeded; sha256 suffices for download and verification).
- **Durability:** journal upsert is written in the same transaction as the asset_set change (import, member attach, override, exclude); tombstone on exclude/delete.

### Payload
```json
{"id":"<uuidv7>","system":"psx","status":"complete","display_title":"Example Game","title_source":"filename",
 "tags":{"region":["USA"],"languages":["En"],"version":"Rev 1","dev_status":null},
 "manifest_version":1,
 "members":[{"ordinal":0,"role":"descriptor","required":true,"sha256":"…","size":1234,"name":"Example Game (USA).cue"},
            {"ordinal":1,"role":"track","required":true,"sha256":"…","size":734003200,"name":"Example Game (USA) (Track 01).bin"}],
 "recognition":{"status":"no_reference","confidence":null,"provider":"header","provider_version":"1","reference_name":null},
 "updated_at":"2026-08-28T12:00:00Z"}
```

### Adversarial pass
- Reshaping later: renaming `members[].name` would break every client → hence one-way; adding `members[].export_path` later is fine.
- Incomplete set: `status: incomplete` with `blob_available: false`? — not needed: a missing member has no `sha256` (null) and `required: true`; client derives "cannot launch". Keep nulls explicit.
- Household: entries are per user_id already (journal is per tenant).
- Snapshot page size: PS1 sets with 30 members are still small; a 2,000-set library is ~10 pages of 200 — acceptable.

### One-shot recommendation
**B-10** as summarised. Rationale: it is exactly the minimum the Mac client needs to browse, download, verify, and judge launchability, and it exposes nothing private. Builds on: D-18 additive rule, D-21 journal/tombstones, frozen `catalogue` kind. Reversibility: one-way.

---

## Deferred ideas surfaced
- Archive-security gate spike (corpus + isolated worker with rlimits) and, after it passes, treating an inspected archive as a `container` member of derived asset_sets.
- M3U multi-disc sets and CHD parent/child resolution (roles exist; proof deferred).
- Reading inside PS1 BIN (SYSTEM.CNF serial, first-track magic) — sector-level parsing belongs after the parser-fuzz gate.
- ClrMamePro `.dat` (non-XML) and TOSEC naming parser.
- Online providers (Hasheous, libretro-database fetch) with per-provider privacy consent — META-01 (v2).
- BIOS validation reusing `recognition_entries` hash-match (Phase 3 PLAY-03).
- RetroAchievements-compatible hash as an extra `blob_fingerprints.kind` (ACHV-01, v2).
- `.smd` interleaved Mega Drive, Lynx/A7800 headered handling, N64 byte-order variants (.z64/.v64/.n64).
- Derived asset_sets from BPS/UPS patches (explicit client action, never auto-apply).
- Sharing reference packs across household users.
- "Possible overdump" verdicts once a reference size is known.

## Sources
- GBATEK GBA cartridge header — https://problemkaputt.de/gbatek-gba-cartridge-header.htm
- Pan Docs, Game Boy cartridge header — https://gbdev.io/pandocs/The_Cartridge_Header.html
- nesdev iNES header — https://www.nesdev.org/wiki/INES
- SNESdev ROM header — https://snes.nesdev.org/wiki/ROM_header
- Plutiedev Mega Drive ROM header — https://plutiedev.com/rom-header
- MAME `chd.h` / chdman — https://github.com/mamedev/mame/blob/master/src/lib/util/chd.h , https://docs.mamedev.org/tools/chdman.html
- RetroAchievements game identification — https://docs.retroachievements.org/developer-docs/game-identification.html
- igir ROM headers / matching / patching — https://igir.io/roms/headers/ , https://github.com/emmercm/igir/issues/281 , https://github.com/emmercm/igir/issues/818 , https://igir.io/roms/patching/
- RetroArch playlists & database — https://docs.libretro.com/guides/roms-playlists-thumbnails/ , https://deepwiki.com/libretro/RetroArch/7.5-playlists-and-database
- RomM first scan / No-Intro issue — https://docs.romm.app/5.1.0/getting-started/first-scan/ , https://github.com/rommapp/romm/issues/187
- Hasheous — https://github.com/gaseous-project/hasheous
- binmerge (Redump multi-track CUE) — https://github.com/putnam/binmerge
- Cue sheet — https://en.wikipedia.org/wiki/Cue_sheet_(computing) , https://emulation.gametechwiki.com/index.php/Cue_sheet_(.cue)
- ES-DE multi-disc — https://emudeck.github.io/tools/steamos/es-de/
- Logiqx datafile DTD — https://github.com/Logiqx/logiqx-www/blob/master/Dats/datafile.dtd
- No-Intro naming convention / navigation / Lynx-7800 headers — https://wiki.no-intro.org/index.php?title=Naming_Convention , https://wiki.no-intro.org/index.php?title=Database_Navigation_Guide , https://forum.no-intro.org/viewtopic.php?t=7652 , https://datomatic.no-intro.org/
- bunkai parser — https://github.com/SnowflakePowered/bunkai
- Redump about (public domain statement) — https://redump.info/about (forum thread http://forum.redump.org/topic/18562/redistributing-dat-files/ unreachable 2026-08-28)
- libretro-database LICENSE (CC BY-SA 4.0) — https://github.com/libretro/libretro-database/blob/master/LICENSE
- BPS spec / UPS format — https://github.com/blakesmith/rombp/blob/master/docs/bps_spec.md , http://justsolve.archiveteam.org/wiki/UPS_(binary_patch_format)
- OWASP File Upload Cheat Sheet — https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html
- Erlang crypto (hash_init/update/final) — https://www.erlang.org/doc/apps/crypto/crypto.html
