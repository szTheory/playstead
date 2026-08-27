# Technical, Protocol, Data, BIOS, Storage, and Product-Risk Research

**Project:** Playstead
**Scope:** self-hosted ROM-library and save-sync server; polished Mac reference client; future multi-platform adapters  
**Researched:** 2026-08-26  
**Overall confidence:** MEDIUM — primary project, standards, cloud, security, and U.S. Copyright Office sources were checked. This is technical/product research, **not legal advice**; jurisdiction, facts, and product design matter.

## Executive decision

Build v1 as a **private, user-supplied-content personal-library system**: the server stores opaque content objects and manifests, never distributes a catalogue of ROMs/BIOSes, and exposes a versioned sync API. Make the Mac client own its local emulator integration. Do not make the server an emulator, scraper, ROM acquisition product, public sharing service, or an archive extractor by default.

Use a three-layer identity model: (1) immutable byte-object identity (`sha256` of the exact stored bytes) for storage/deduplication; (2) media/component fingerprints (size + CRC32/MD5/SHA-1 where an upstream DAT defines them) for recognition and BIOS validation; and (3) a stable server UUID for a logical library item/release. `sha256` is the security and object-addressing key; legacy hashes are compatibility evidence, never the security boundary. A filename, archive checksum, or S3 ETag is not a durable content identity.

Treat a playable title as a **manifested asset graph**, not a ROM file: a PS1 release can require a CUE descriptor plus ordered tracks; multi-disc content has several discs; a CHD can depend on a parent; arcade content can depend on a BIOS set; and save/state files are scoped to a title, emulator/core build, platform, and configuration. This preserves safe export, avoids bad dedupe, and creates an honest compatibility UI.

## V1 technical contract

### Content and metadata model

| Entity | Required fields | Rules |
|---|---|---|
| `blob` | `sha256`, byte size, storage key, MIME/format evidence, availability, scan state | Exact uploaded bytes; immutable; server-generated key such as `objects/sha256/ab/<hash>`; no user filename in storage path. |
| `source_file` | original display path/name, import session, blob ID, observed container/format | Provenance only; preserve it for export/audit, never use as identity. |
| `asset_set` | UUID, system family, manifest version, status, ordered members | A launchable/importable unit. Members may be primary media, descriptor, tracks, BIOS dependency, patch, or parent dependency. |
| `asset_member` | asset-set ID, blob ID, role, ordinal, expected relative export path | Supports multi-track/multi-disc sets and repeatable ordinary-folder export. |
| `recognition` | matcher source/version, matched release ID, hash type/value, confidence, result | A match is evidence, not a rewrite of user data. Preserve unknown/ambiguous results. |
| `save_artifact` | logical game ID or asset set, save kind, blob ID, adapter fingerprint, base revision, vector/revision, device ID | Save kind is `battery/firmware-card`, `state`, `memory-card`, `config`, or `replay`, never a generic “save”. |
| `bios_asset` | system/core scope, expected filename, exact hash/size, user blob ID, validation state | Private user asset; never bundled or acquired by the product. |

**Canonicalization recommendation.** Store **original bytes unchanged**. Compute container-level SHA-256 immediately. Optionally inspect a bounded/sandboxed copy to identify member hashes, disc serials, headers and format. Do not silently unzip, rezip, trim headers, patch, normalize line endings, rename, or transcode canonical storage. Those transformations destroy round-trip guarantees and make DAT matches ambiguous. Generate a canonical *display* title from a versioned match source, while retaining original filename, exact manifest, matcher version, and user override.

**Dirty, patched, overdumped, and unknown files.** A clean DAT match can be labelled “verified” only when exact required members match. Everything else remains first-class: `known-patched`, `known-variant`, `suspect-overdump`, `duplicate-bytes`, `unrecognized`, or `malformed`. Never delete or rewrite it automatically. A patch is a separate user-provided blob plus declared base hash and output hash; applying it is an explicit client action that creates a new derived asset set. “Bad” means “does not match selected reference data,” not “unplayable” or unlawful.

### Database roles, provenance, and licensing

No-Intro conventions provide structured canonical names and DAT-oriented verification vocabulary. Redump and TOSEC are useful **reference datasets**, while Libretro’s database is a practical integration source for RetroArch-style cataloguing. Libretro documents CRC as a common key for small media and embedded serials for larger disc media, but keeps stronger hashes for interoperability. Its repository license is CC BY-SA 4.0. [S01–S03]

**Decision:** in v1, ship no third-party DAT payload or thumbnails. Implement a pluggable `matcher` import format and let the administrator import a local DAT pack after accepting/recording its source and license. Store `source URL`, retrieved date, source revision/hash, license claim, and transform version. A later `emu-curated-metadata` package may redistribute only material whose rights, attribution, ShareAlike/other downstream duties, and packaging implications have been reviewed. Do not assume one project’s license applies to its upstream inputs, and do not use a DAT match to imply rights in a ROM.

### Import, dedupe, quarantine, and export semantics

| Mode | V1? | Semantics |
|---|---:|---|
| Managed copy | **Yes** | Copy bytes into content-addressed storage; source remains untouched; safest for multi-device sync. |
| Managed move | No | Dangerous failure/rollback semantics and violates source expectations; possibly add later as explicit staged operation. |
| Reference folder | No (spike only) | Makes local-library UX attractive but breaks remote availability, dedupe lifecycle, permissions, and offline portability. |
| Archive preservation | Yes, opt-in | Store an archive opaque and optionally index only under strict limits; do not use it as the normal launch representation. |

Deduplicate exact `sha256` blobs globally *within a tenant*, but retain many source-file records and manifests pointing at the blob. Do not dedupe by CRC/filename/metadata. Quarantine files that fail format policy, limits, malware/scan policy, or parse checks; retain a recoverable diagnostic and a deletion/retention policy. An unknown file may be accepted but marked unrecognized—recognition is not an admission control gate.

**Ordinary-folder export guarantee:** export a manifest to a chosen empty directory using recorded relative paths and exact original bytes; write a sidecar manifest with asset-set UUID, manifest version, SHA-256s, and source provenance. Verify hashes after export. On re-import, the sidecar is an optimization only: re-hash and validate every blob. Do not promise export-import folder *layout* preservation if a user has manually changed it; promise byte preservation and a deterministic generated layout.

### Object storage and transfer protocol

**Storage:** implement a local-filesystem object-store adapter first and make the S3 API adapter the production remote target. That covers MinIO, AWS S3, and Cloudflare R2 without creating an R2-only protocol. R2 documents S3-compatible multipart uploads, 5 MiB–5 GiB parts, up to 10,000 parts, and automatic abort of incomplete uploads by default after seven days. [S07] Keep object-store credentials server-side; issue short-lived, scope-limited upload/download authorizations where direct client object transfers are later adopted.

**Upload:** begin with server-proxied streamed upload for a small-file MVP (bounded length, SHA-256 computed while streaming). Spike either **tus 1.0** or S3 multipart before multi-GB/remote client support—do not invent a partial-PUT protocol. tus defines discoverable resumable-upload behavior; S3 multipart has established completion and checksum semantics. Persist upload session, expected byte length, uploaded offset/part list, expiry, user/tenant, and target content intent. Verify the finished full byte-stream SHA-256 independently. Never use multipart ETag as an object MD5: AWS and R2 explicitly document multipart-specific ETag construction. [S04–S08]

**Download/offline cache:** support HTTP `Range`, `If-None-Match`/`ETag`, and explicit immutable blob URLs or IDs. RFC 9110 defines byte ranges for interrupted transfers. Pin a client cache entry by `(blob.sha256, byte_size)` and make eviction LRU with a user-set capacity. Launch requires all blobs in its manifest to be present; prefetch is an explicit state with progress. Cache may be purged safely because metadata/manifests remain separate.

### Save synchronization

Battery-backed saves, memory cards, firmware/NVRAM, save states, emulator configurations, and replay movies have different portability. Libretro says serialization/save-state support is optional at the core boundary; its UI/docs also separate save and save-state directories and core-specific system dependencies. [S09–S12] Therefore:

1. **V1 syncs only explicit adapter-declared persistent saves** (normally battery/NVRAM and, where proven, memory cards). Adapter declares exact path discovery, stable game identity, format identity, and safe flush behavior.
2. Store each upload as an immutable revision, then advance a small mutable “head.” Require `base_revision`; conflicting concurrent writes create two heads and require user choice—never last-write-wins silently.
3. Save states are **opt-in experimental artifacts** keyed by emulator ID + core name/version/build + platform/architecture + content SHA-256 + core options fingerprint. Default is local-only. No cross-core, cross-version, or cross-platform compatibility promise.
4. Provide retention (e.g., latest 30 revisions plus pinned), restore-as-new-revision, conflict preview where a format-specific adapter permits it, and checksummed downloads. Treat any client crash/close as uncertain: sync after adapter-provided safe flush or stable-file debounce, never continuous blind upload.

### Protocol and adapter boundary

Use HTTPS JSON/CBOR APIs plus OAuth/device-token authentication; version the **wire contract** at `/api/v1` and include a mandatory client hello:

```json
{"protocol":{"major":1,"minor":0},"client":{"id":"mac-reference","version":"1.0.0"},"capabilities":["range-download","save-revisions","managed-import"]}
```

The server returns its supported ranges, feature flags, upload modes, and capability limits. Major mismatch fails with an actionable upgrade message; additions are optional/ignored; removals or semantic changes require a new major version. Publish schemas and a compatibility matrix, use idempotency keys for mutation, and expose deprecation/sunset dates. This follows the practical principle documented by GitHub: additive changes may be non-breaking; removed/renamed/required changes need a version boundary and published support window. [S16]

**Emulator adapters are client-side plugins**, never server modules: `discover → identify → materialize manifest → launch → observe save → flush → collect controls`. The common server model must not contain emulator paths, core options, or a giant capability matrix. Each adapter publishes a fingerprint and supported save classes. Start with one Mac adapter (likely a controlled RetroArch integration) and one system family, then prove a second adapter before declaring protocol portability.

**Controller profiles:** retain raw platform profile separately from a semantic, user-editable `logical_control` mapping (`dpad`, face buttons by semantic position, shoulders, sticks, menu). Store vendor/product ID, transport, OS/input-driver, profile schema version, mapping, dead zones/calibration, hotkey mapping, and adapter scope. Libretro auto-config profiles differ across Android/udev/linuxraw/SDL2 and can require vendor/product IDs; do not assume one hardware profile is portable. [S14]

### BIOS and lawful UX

BIOS is user-supplied content. Libretro describes BIOS as copied system software, says it does not distribute copyrighted system files or game content, and core docs validate correct location/name/hash. [S09–S11] V1 should provide an **auditor**, not a downloader: “This adapter needs `filename`, SHA/MD5/size, and destination layout; select a local file to validate.” Keep BIOS blobs in a private, separately permissioned namespace and materialize them only into the local client’s emulator system directory. Never display “get BIOS,” link to sources, bundle proprietary BIOS, or bypass access controls.

Open replacements/HLE are system- and core-specific compatibility choices, not generic “BIOS alternatives.” Permit adapters to declare `open-replacement` only with the upstream license, source/revision, known compatibility caveat, and a visible distinction from verified original firmware. This needs a per-system legal/technical review before any distribution. Some emulation still requires proprietary firmware; a missing-BIOS state must be a clean, non-judgmental setup screen.

## Security and operational threat model

| Threat | V1 control | Defer/validate |
|---|---|---|
| Parser exploit / malicious archive | Accept a narrow allowlist; detect magic bytes; opaque-store first; inspect/extract only in unprivileged sandbox with CPU, memory, recursion, member-count, compressed and declared/uncompressed-size caps. | Fuzz parsers and build corpus before enabling ZIP/7z parsing. |
| ZIP/decompression bomb | No recursive archive extraction; preflight size/count; hard quotas; cancellation; never trust archive metadata alone. OWASP warns decompression size must be bounded before extraction. [S17–S18] | Test adversarial corpus in CI. |
| Traversal/symlink overwrite | Generate storage keys; reject absolute, `..`, NUL/control paths; normalize and verify containment; do not preserve symlinks from archives. | OS-specific extraction test matrix. |
| Malware / unsafe download | Tenant-private authorization; never execute uploads; scan on ingest when exposed to others; quarantine before materialization; signed client releases. Do **not** upload private ROMs to public multi-engine scanners without explicit consent. | Assess scanner privacy/cost for hosted tier. |
| Remote exposure / account abuse | Private-by-default server, TLS, strong authentication, CSRF protection for browser sessions, rate/byte/concurrency quotas, audit log, secure defaults, no unauthenticated LAN discovery. | Threat model reverse proxy, device pairing, token recovery. |
| Storage loss/corruption | Blob SHA-256 verification, transactional metadata before visibility, immutable revisions, backup/restore drills, object lifecycle monitoring for orphaned multipart uploads. | S3 eventual/error behavior and restore runbook. |
| Content confidentiality | Per-tenant authorization enforced at manifest and blob endpoints; no predictable shared URLs; encryption in transit and documented at-rest posture; minimize logs (no filenames/hashes in telemetry by default). | Key-management model for hosted service. |

OWASP’s upload guidance supports generated filenames, non-webroot/segregated storage, authorization, type/size checks, scanning, and restrictive handling of archives. [S17] Treat all filenames, archive headers, DAT text, core metadata, and emulator output as untrusted input.

## Legal/product posture

**Self-hosted:** the project can honestly position itself as software for organizing user-supplied files. That does not decide whether a user’s copy, dump, circumvention, jurisdiction, or use is lawful. Keep defaults private, do not ship copyrighted game/BIOS content, do not provide acquisition workflows, and avoid “verified ownership” claims that hashes cannot prove.

**Hosted:** a hosted sync/storage service is storing material at users’ direction and has a qualitatively larger operational risk. In the U.S., 17 U.S.C. §512’s limitations are conditional; the Copyright Office notes obligations including a designated agent, notice-and-takedown process, repeat-infringer policy, and accommodation of qualifying standard technical measures. It is not immunity or product clearance. [S19–S21] A hosted launch requires counsel, jurisdiction/terms/privacy analysis, copyright-agent/takedown operations where applicable, abuse response, a meaningful storage/access policy, and vendor terms review. Do not launch hosting merely by adding S3 credentials to the self-hosted product.

Emulator software and content distribution are separate questions. *Sony v. Connectix* held that intermediate BIOS copying in that particular reverse-engineering record was fair use, but that case does not authorize distributing BIOS/ROM content, evading all technical measures, or establish worldwide rules. 17 U.S.C. §1201 generally restricts circumvention, with narrowly defined temporary exemptions. [S22–S24] Do not rely on this report as legal advice; retain specialist counsel before commercialization or any firmware/replacement-BIOS feature.

## Roadmap: build, spike, wait

### V1 — build

- Private self-hosted deployment; local disk object store; tenant/user model; no public sharing.
- Managed-copy importer for a **small initial format allowlist**, streaming SHA-256, exact-byte store, source provenance, manifest asset sets, exact dedupe, and recoverable quarantine.
- Deterministic ordinary-folder export with sidecar manifest and hash verification.
- Versioned API, capability hello, device pairing/token rotation, HTTP range downloads, local offline cache.
- One Mac client + one explicitly documented emulator adapter + one or two systems; battery/NVRAM save revision sync with manual conflict choice/history.
- BIOS auditor and missing-dependency UX only; no BIOS distribution.
- Baseline security controls and backup/restore test.

### Required spikes before commitment

1. **Adapter spike:** prove one RetroArch/target-emulator adapter can identify content, configure paths, flush/save deterministically, and relaunch after device handoff. Measure failure cases.
2. **Disc/manifest spike:** import/export representative CUE+multi-track, multi-disc, arcade+BIOS, and an unknown/patched set without byte changes or broken paths.
3. **Transfer spike:** compare server-proxied stream + Range against tus and S3 multipart for a dropped/resumed transfer; prove final SHA-256, cancellation, and cleanup.
4. **Archive security spike:** fuzz/budget bounded inspection using traversal, symlink, nested, and decompression-bomb fixtures in an isolated container.
5. **Save compatibility spike:** test battery save versus state across core upgrade, different core, and Mac/second platform. Document supported matrix, not aspirations.
6. **Licensing review spike:** inventory exact No-Intro/Redump/TOSEC/DAT source terms and whether any shipped derivative has attribution/ShareAlike/database-right obligations.

### Wait / anti-features

- Public ROM or BIOS catalogue, search across users, sharing links, community uploads, “ownership verification,” acquisition help, or circumvention features.
- General-purpose folder reference mode, managed move, auto-delete of nonmatches, automatic patch application, and destructive “fix ROM” normalization.
- Broad platform promise (PSP/Vita/Steam Deck/Windows/Linux) before two adapters prove the protocol boundary.
- Cross-emulator/cross-version save-state sync, automatic conflict merge, achievements/netplay/cloud execution, recommendation engine, streaming, and public metadata scraping.
- R2-specific logic, a custom binary transport, custom resumable upload semantics, or ETag-as-hash identity.

## Architecture implications

```
Mac client / future client
  ├─ Emulator adapter (local paths, launch, saves, controllers, BIOS materialization)
  ├─ Offline cache (blob sha256 + manifest cache)
  └─ Versioned sync API ───────────────┐
                                     API / policy layer
                                         ├─ Postgres: users, manifests, recognition, revisions
                                         ├─ Object-store interface: local disk | S3-compatible
                                         └─ bounded workers: hash, inspect, validate, quarantine
```

The server must make no decision that requires loading untrusted game code. Inspect bytes and metadata in a bounded worker; the client launches content only after an explicit user action. Postgres tracks logical ownership/revisions; the object store holds immutable bytes. This supports Elixir supervision without treating supervision as a substitute for process isolation, quotas, or idempotency.

## Unresolved questions

- Which exact first system(s), emulator(s), and Mac distribution model are in scope? That determines viable save and BIOS contracts.
- Is “private self-hosted” single household, single user, or multi-user? Tenant/share semantics determine dedupe and privacy design.
- What license/policy will govern third-party metadata, and whether it is distributed at all?
- Is direct-to-S3/R2 upload required for the first remote demo, or is server-proxied streaming acceptable?
- Does macOS sandboxing/notarization constrain the chosen emulator integration and local directory materialization path? Validate in the adapter spike.

## Sources Ledger

All sources were accessed 2026-08-26. Confidence is **MEDIUM** unless noted because findings were cross-checked through official/primary materials but must be revisited at implementation and with counsel for legal claims.

| ID | Title | Publisher | URL | Supports |
|---|---|---|---|---|
| S01 | Libretro Database README | Libretro | https://github.com/libretro/libretro-database/blob/master/README.md | DAT provenance; CRC/serial matching; canonical names; metadata role. |
| S02 | libretro-database LICENSE | Libretro | https://github.com/libretro/libretro-database/blob/master/LICENSE | CC BY-SA 4.0 license for this repository. |
| S03 | Official No-Intro Convention | No-Intro | https://datomatic.no-intro.org/stuff/The%20Official%20No-Intro%20Convention%20%2820071030%29.pdf | Structured canonical naming fields. |
| S04 | Resumable Upload Protocol 1.0.x | tus.io | https://tus.io/protocols/resumable-upload | Standard resumable-upload protocol. |
| S05 | RFC 9110: HTTP Semantics | IETF | https://www.rfc-editor.org/rfc/rfc9110.html | Range/Content-Range for resumable download. |
| S06 | Checking object integrity for data uploads in Amazon S3 | AWS | https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity-upload.html | Multipart checksum and ETag limitations. |
| S07 | Upload objects | Cloudflare | https://developers.cloudflare.com/r2/objects/upload-objects/ | R2 multipart constraints/lifecycle/ETag behavior. |
| S08 | Multipart upload overview | AWS | https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpuoverview.html | Multipart completion/checksum operations. |
| S09 | What is BIOS? | Libretro | https://docs.libretro.com/guides/bios/ | User-supplied BIOS/legal posture and core needs. |
| S10 | BIOS Information Hub | Libretro | https://docs.libretro.com/library/bios/ | BIOS name/location/hash validation. |
| S11 | Directory Configuration | Libretro | https://docs.libretro.com/guides/change-directories/ | Distinct system/save/state paths. |
| S12 | Core Development Overview | Libretro | https://docs.libretro.com/development/cores/developing-cores/ | Optional core serialization and state behavior. |
| S13 | Quick Menu | Libretro | https://docs.libretro.com/guides/quick-menu/ | Core-specific options, states, remapping, disc control. |
| S14 | Controller Auto-Configuration | Libretro | https://docs.libretro.com/guides/controller-autoconfiguration/ | Driver/platform dependent controller profiles. |
| S15 | MAME Documentation | MAMEDev | https://docs.mamedev.org/_files/MAME.pdf | CHD parent/delta and software-list complexity. |
| S16 | API Versions | GitHub Docs | https://docs.github.com/en/rest/about-the-rest-api/api-versions | Additive vs breaking API changes, deprecation model. |
| S17 | File Upload Cheat Sheet | OWASP | https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html | Upload validation, segregation, scanning, archive risks. |
| S18 | WSTG: Testing for malicious files | OWASP | https://owasp.org/www-project-web-security-testing-guide/latest/4-Web_Application_Security_Testing/10-Business_Logic_Testing/09-Test_Upload_of_Malicious_Files | Decompression-bomb/symlink extraction risk. |
| S19 | 17 U.S.C. §512 | Cornell LII (U.S. Code) | https://www.law.cornell.edu/uscode/text/17/512 | Conditional U.S. online-service-provider limitations. |
| S20 | Section 512 resources | U.S. Copyright Office | https://www.copyright.gov/512/ | Hosting-at-user-direction, repeat-infringer and notice requirements. |
| S21 | Online Service Providers | U.S. Copyright Office | https://www.copyright.gov/onlinesp/ | Designated-agent requirement for §512(c) posture. |
| S22 | Sony Computer Entertainment v. Connectix | U.S. Court of Appeals, Ninth Circuit (via FindLaw) | https://caselaw.findlaw.com/court/us-9th-circuit/1452245.html | Case-specific fair-use holding for intermediate BIOS copying. |
| S23 | DMCA / Section 1201 | U.S. Copyright Office | https://www.copyright.gov/dmca/ | DMCA overview and designated-agent notice. |
| S24 | Ninth Triennial Section 1201 Proceeding | U.S. Copyright Office | https://www.copyright.gov/1201/2024/ | General anti-circumvention rule and limited exemptions. |
