# Phase 2: Explainable Import and Exact Export - Research

**Researched:** 2026-08-28
**Domain:** Streaming file custody (Phoenix/Elixir), content-addressed blob storage, durable Oban work, binary format sniffing, BagIt-shaped filesystem export
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

Forty decisions (D-01–D-40) covering ingestion surfaces, durable staged-collection work, the write path and storage seam, formats/manifests/recognition, receipts/outcomes/Needs Attention, and export/reimport identity — the full text is normative in `02-CONTEXT.md ## Implementation Decisions` and is not reproduced verbatim here to avoid drift between two copies. This RESEARCH.md's every section is written to be consistent with, and additive to, that decision record; where this document proposes an implementation detail not covered by a D-xx (e.g., which stdlib function computes CRC32), it is explicitly marked as this document's own recommendation, not a locked decision.

Load-bearing decisions the planner must not re-derive or contradict: three ingestion surfaces with a read-only inbox bind mount (D-01); RFC 9530 `Repr-Digest` + mandatory `Idempotency-Key` on API upload (D-02); split 4 GiB/8 GiB upload ceilings (D-03); Oban OSS-only session worker, unique per `session_id`, cooperative per-file pause (D-05, D-06); cancel keeps completed copies, never removes (D-07); hybrid reconcile by fingerprint (D-08); D-10's exact limit/error-code table; D-11's temp→hash→fsync→read-back-verify→atomic-rename→one-transaction write path; `Playstead.Blobs.Store` behaviour (D-12); blobs are global, everything else user-scoped (D-13); seven-system-id allowlist with Tier A/B validators, pure Elixir, no NIFs (D-14); `asset_member` roles for multi-file sets (D-15); header-evidence recognition without a DAT (D-16); frozen alias/variant/patched definitions (D-17); `saxy`-based admin-supplied Logiqx DAT-pack importer as the last droppable plan (D-18); system-assignment precedence extension→header→user (D-19); CRC32/MD5/SHA-1 alongside SHA-256 plus headerless-offset fingerprints (D-20); archives accepted opaque, never quarantined merely for being archives (D-21); No-Intro filename-parse display titles (D-22); frozen `catalogue` journal payload shape (D-23); two-table receipt/session model (D-24); nine frozen outcome codes (D-25); Needs-Attention in/out rules (D-26); five audited reversible resolutions, no byte deletion (D-27); quarantine as processing state not a second store (D-28); "failed safely" five-class guarantee (D-29); journal/API mapping (D-30); inbox ergonomics (D-31); code-keyed microcopy (D-32); server-side operator-mounted export, no browser zip in Phase 2 (D-33); BagIt RFC 8493 layout (D-34); sidecar schema (D-35); write-then-verify export (D-36); hybrid hash-set-first reimport identity via `member_fingerprint` (D-37); export scope/job model reuse (D-38); reserved-for-Phase-4 fields (D-39); export vocabulary and durable `exports` row (D-40).

### Claude's Discretion

Exact table/column names, Ecto schema layout, migration ordering (forward-only, backward-compatible per P1 D-17), and LiveView component structure. Chunk size tuning, `Task.async_stream` timeouts, Oban Lifeline `rescue_after`, PubSub topic naming. `system-slug` display names for the seven ids, `_unsorted`/`_quarantined` folder names, and the import/inbox/export console information architecture (a UI-SPEC pass should refine these LiveView surfaces). Whether `precheck` accepts a batch of hashes or one per call. Exact No-Intro filename grammar coverage beyond the documented tag groups. The BagIt profile JSON contents and README.txt prose (within D-40's vocabulary rules).

### Deferred Ideas (OUT OF SCOPE)

Inbox auto-watch (inotify/polling); tus/S3 multipart resumable upload (TRAN-01, v2); periodic blob scrub/"Verify library" (Phase 5); per-user inbox sub-folders (v2); browser folder pick; container memory limits in compose (Phase 5 docs). Archive-security gate spike and inspected-archive derived asset sets; M3U multi-disc and CHD parent/child proof; sector-level PS1 BIN reading; ClrMamePro/TOSEC parsers; `.smd`/Lynx/A7800/N64 header variants; online metadata providers (META-01, v2); BIOS validation reuse (Phase 3 PLAY-03); RetroAchievements hash fingerprint (ACHV-01, v2); derived asset sets from patches; reference-pack sharing across household users. Physical reclaim (Phase 5); auto-resolution rules (v2); malware-scanner adapter (hosted-tier prerequisite); Mac client inbox UI (Phase 3+); bulk companion-attach, receipt CSV export, inspector re-run (Phase 5 preflight). Saves in export and Mac-side export writer (Phase 4 PORT-01); signed manifests; browser zip download; scheduled re-verification (Phase 5); S3 export destinations and reference-in-place mode (v2); igir-style tokenised output paths.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-------------------|
| IMPT-01 | A user can select one supported file and see before confirmation that Playstead will copy it into managed storage, leave the source untouched, and consume a stated amount of storage. | D-01/D-04 preview rules; Pattern 2 (`UploadWriter`) and the `:ro` inbox mount (Anti-Patterns) enforce "leave the source untouched" at both app and OS level |
| IMPT-02 | After import, a user can verify the SHA-256 and byte size of the exact original bytes and inspect their source provenance. | D-11 write path + Pattern 1 (streaming multi-digest hash) produce the trust-bearing SHA-256; D-24 receipt schema carries provenance |
| IMPT-03 | A user receives a durable import receipt that distinguishes new/duplicate/alias/variant/incomplete/unrecognized/patched/quarantined/failed-safely content. | D-24/D-25 frozen nine-code taxonomy; Validation Architecture maps IMPT-03 to `test/playstead/import/outcome_test.exs` |
| IMPT-04 | A user can import a supported multi-file game as an ordered asset manifest whose required members and readiness remain explicit. | D-15 `asset_member` roles/ordinals; Pitfall 5 (path sanitization for CUE-referenced names); Validation Architecture maps to `psx_cue_test.exs` with adversarial fixtures |
| IMPT-05 | A user can stage a large collection import, observe bounded progress, pause/resume it, retry interrupted work, and reconcile without duplicating unchanged content. | D-05/D-06/D-08/D-09; Pattern 3 (`ImportSessionWorker`) and Pitfall 3 (TOCTOU on free-space) |
| IMPT-06 | A user can resolve a Needs Attention item via evidence-backed correct/attach/retain/exclude/retry actions. | D-26/D-27/D-28; Don't-Hand-Roll row reusing `Playstead.AuditLog` for every resolution |
| PORT-02 | A user can verify an export and reimport it without byte changes, lost relationships, or duplicate logical records. | D-33 through D-40; Pattern 4 (write-then-verify) and Pitfall 5 (export path sanitization); Validation Architecture maps to `round_trip_test.exs` covering the five contract assertions in `02-CONTEXT.md <specifics>` |
</phase_requirements>

## Summary

Phase 2's 40 decisions (D-01–D-40) were already produced by `/gsd-discuss-phase` through four parallel multi-lens research fan-outs with adversarial passes, and are locked in `02-CONTEXT.md`. This RESEARCH.md does **not** re-litigate those decisions — it verifies the technical substrate they depend on (package versions actually installed, library APIs those decisions name, and the wider Elixir/Oban/Phoenix idiom for durable-file-custody systems), and adds the sections `02-CONTEXT.md` does not carry: verified Standard Stack versions, a Package Legitimacy Audit, concrete code skeletons for the write path and Oban session worker, a Don't-Hand-Roll table, a Common Pitfalls catalogue tuned to this phase's five threat classes, Validation Architecture, and the Security Domain threat model input.

Every reusable Phase 1 module this phase builds on (`Playstead.Idempotency`, `Playstead.Sync.EntityKind`, `Playstead.AuditLog`, `Playstead.RateLimiter`, `Playstead.Readiness`, `Playstead.CommandId`) was opened and read this session — their real function signatures are quoted below, not paraphrased from memory, because Phase 2's plan tasks will call them directly.

**Primary recommendation:** Build the write path exactly as D-11 specifies (temp-on-same-volume → chunked SHA-256+CRC32+MD5+SHA-1 in one pass → fsync → mandatory read-back re-hash → atomic rename into CAS → one DB transaction), using only Erlang/Elixir stdlib (`:crypto`, `File`, `:file.sync`) for the hot path — no new hex dependency is needed for hashing, chunked I/O, or CUE/BagIt text parsing. The **one** new hex dependency this phase should add is `saxy` (SAX XML, DTD-skipping by default) for the Logiqx DAT-pack importer (D-18); every other capability composes from what's already in `mix.lock` (`Oban` 2.24, `Phoenix.LiveView` 1.2.11's `UploadWriter` behaviour, `Req` for nothing new here, `Ecto.Multi`, `Hammer`).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Browser single-file upload (hash-while-stream) | Frontend Server (SSR/LiveView) | — | `Phoenix.LiveView.UploadWriter` runs in the LiveView process on the server; there is no separate client-side hashing (D-01a) |
| Inbox scan / stage-a-collection | API/Backend (Oban worker) | Frontend Server (trigger only) | Filesystem scan of a bind-mounted host path must run server-side; LiveView only triggers and observes (D-01b, D-05) |
| API streaming upload + precheck | API/Backend | — | `PUT /api/v1/imports/uploads/{command_id}`, `POST /api/v1/imports/precheck` — Mac client is the caller, server is sole writer (D-01c, D-02) |
| Blob write, hash, CAS commit | API/Backend (`Playstead.Blobs.Store`) | Database/Storage (Postgres row + filesystem) | The custody promise is made at commit time inside one Ecto transaction spanning DB row + renamed file (D-11, D-12) |
| Format/system recognition | API/Backend (`Playstead.Recognition.Provider`) | — | Pure binary pattern matching, no NIFs/ports (D-14); must not touch DB store directly, evidence rows only |
| Needs Attention inbox + resolutions | Frontend Server (LiveView) + API/Backend (REST) | — | Console renders it; Mac client consumes the same context functions via REST (D-26, D-30) |
| Staged-collection progress/control | API/Backend (Oban `ImportSessionWorker`) | Frontend Server (PubSub subscriber) | Durable cursor lives in `source_file` rows in Postgres; LiveView only subscribes to throttled ticks (D-05, D-09) |
| Export write + verify | API/Backend (Oban `Export.Worker`) | Database/Storage (`PLAYSTEAD_EXPORT_PATH` volume) | Same job/progress/control model as import; writes to an operator-mounted directory, not browser-downloaded (D-33, D-38) |
| Blob byte-serving for export contract test | API/Backend | CDN/Static (not applicable — no CDN in this deployment shape) | `GET /api/v1/blobs/:sha256` proves API-written and server-written exports are byte-identical (D-33) |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `oban` | 2.24.0 `[VERIFIED: playstead-server/mix.lock]` | Durable session worker, per-file cursor, pause/resume/retry, export worker | Already the app's only job-queue library (Phase 1: `Pairing.ExpireStaleRequestsWorker`, `Idempotency.PruneExpiredWorker`, `Sync.CompactionWorker`); Postgres-backed durability matches the no-Redis/no-Kafka constraint (PROJECT.md) |
| `phoenix_live_view` | 1.2.11 `[VERIFIED: playstead-server/mix.lock]` | `Phoenix.LiveView.UploadWriter` custom writer for streaming-hash browser uploads | Ships the exact hook D-01a names; no external upload library needed |
| `ecto_sql` | 3.14.0 `[VERIFIED: playstead-server/mix.lock]` | `Ecto.Multi` transactional writes for blob+source_file+receipt+journal | Already the app's only ORM/transaction layer |
| `:crypto` (Erlang/OTP stdlib) | OTP 28 `[VERIFIED: elixir --version / erlang shell]` | Streaming SHA-256, CRC32, MD5, SHA-1 in one chunked pass (D-20) | No hex dependency needed — `:crypto.hash_init/1`, `:crypto.hash_update/2`, `:crypto.hash_final/1` cover all four digests; CRC32 is `:erlang.crc32/1` incrementally via `:erlang.crc32/2` |
| `saxy` | 1.6.1 `[VERIFIED: mix hex.info saxy]` | SAX XML parser for Logiqx DAT-pack import (D-18) | Skips DTD by default and does not expand external entity references — the exact "no DTD/entities" property D-18 requires `[CITED: https://hexdocs.pm/saxy/readme.html]`; pure Elixir, no NIF/port, 9.1M all-time hex downloads, actively released (1.6.1, 2026-07-10) |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `hammer` | 7.4.0 `[VERIFIED: playstead-server/mix.lock]` | Per-device upload concurrency (≤2), per-IP staging-action limits (D-10) | Already the app's rate limiter (`Playstead.RateLimiter`, `use Hammer, backend: :ets`); reuse, do not add a second limiter |
| `jason` | present `[VERIFIED: playstead-server/mix.exs]` | Canonical JSON for `playstead-manifest.json` / `playstead-set.json` sidecars (D-35) | Standard JSON encode/decode already used for idempotency receipt bodies |
| Erlang stdlib `File`, `:file.sync/1`, `:filelib` | OTP 28 | Temp-write, fsync, atomic rename write path (D-11), directory-fsync on export (D-36) | No wrapper library needed; `File.rename/2` is atomic within the same filesystem/volume, which is why D-11 requires `tmp/` and `objects/` share one volume |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `saxy` (SAX) | `:xmerl` (Erlang stdlib DOM/SAX) | `:xmerl` ships free but its DTD/entity-expansion defaults are the classic Erlang XXE footgun `[CITED: https://vuln.be/post/xxe-in-erlang-and-elixir/]` — every historical Erlang XXE advisory traces to `:xmerl` misconfiguration; `saxy` is safe-by-default and avoids needing to remember to disable DTD processing per call site |
| Pure-Elixir Tier A/B validators | A NIF-based magic-byte library (`file_info`, libmagic bindings) | D-14 explicitly rejects NIFs/ports for validators — a malformed input crashing a NIF takes the whole BEAM node down; pure pattern matching on binaries degrades to a normal Elixir exception, catchable per D-14's "never raise" requirement |
| Oban OSS unique-job cursor | Oban Pro's Batch/Chain plugins | D-05 explicitly locks OSS-only; Pro's batch primitives would simplify session fan-out but are a paid add-on outside this project's dependency posture |

**Installation:**
```elixir
# mix.exs — the only new line this phase needs
{:saxy, "~> 1.6"}
```

**Version verification:** Confirmed via `mix hex.info saxy` (interactive session, hex.pm registry — no auth required for public package metadata) and cross-checked against the GitHub source (`qcam/saxy`, the currently-maintained fork; the older `peburrows/saxy` repository is superseded). All other libraries this phase touches (`oban`, `phoenix_live_view`, `ecto_sql`, `hammer`) were confirmed already present and pinned in `~/projects/playstead/playstead-server/mix.lock` — no version bump required.

## Package Legitimacy Audit

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| `saxy` | hex.pm | first release 2020-06-02, latest 1.6.1 on 2026-07-10 (6 years, actively maintained) | 9,127,100 all-time / 48,508 last 7 days | github.com/qcam/saxy | OK | Approved |

**Packages removed due to `[SLOP]` verdict:** none.
**Packages flagged as suspicious `[SUS]`:** none.

*Note: the project's `gsd-tools package-legitimacy check` seam supports `npm|pypi|crates` ecosystems only — hex.pm is not covered by the automated gate. The verdict above was produced manually via `mix hex.info saxy` (registry metadata: release history, download counts) cross-checked against the GitHub source repository and its hexdocs README, following the same signal set (age, downloads, source-repo existence, active maintenance) the automated gate uses for other ecosystems. Because this check was not run through the automated seam, treat the `saxy` recommendation as `[ASSUMED]`-adjacent for planning purposes: the planner should still gate its `mix.exs` addition behind a `checkpoint:human-verify` task per the package-legitimacy protocol's spirit, even though the verdict itself is OK.**

Every other package this phase relies on (`oban`, `phoenix_live_view`, `ecto_sql`, `hammer`, `jason`) is **already installed and running in production code** (Phase 1) — no legitimacy check is needed for packages already vetted and shipped.

## Architecture Patterns

### System Architecture Diagram

```
                    ┌─────────────────────────────────────────────────────┐
                    │                   Ingestion Surfaces                  │
                    │  (a) LiveView single-file upload (UploadWriter)       │
                    │  (b) Host inbox bind-mount, explicit "Stage" scan     │
                    │  (c) API PUT /imports/uploads/{cmd_id} + /precheck    │
                    └───────────────┬─────────────────┬─────────────────────┘
                                    │                 │
                     single file    │                 │ staged collection (many files)
                                    ▼                 ▼
                    ┌───────────────────────┐  ┌─────────────────────────────┐
                    │ inline request-scoped  │  │ Oban ImportSessionWorker    │
                    │ hash + write (no job)  │  │ (unique session_id,         │
                    │                        │  │  queue :import, conc 1)     │
                    │                        │  │ iterates source_file rows   │
                    │                        │  │ as durable cursor;          │
                    │                        │  │ Task.async_stream(conc 2)   │
                    └───────────┬────────────┘  └──────────────┬───────────────┘
                                │                               │
                                ▼                               ▼
                    ┌─────────────────────────────────────────────────────┐
                    │            Playstead.Blobs.Store (behaviour)         │
                    │  open_write → write_chunk (1 MiB, sha256+crc32+      │
                    │  md5+sha1 in one pass) → :file.sync → read-back      │
                    │  re-hash (default on) → File.rename into             │
                    │  objects/sha256/ab/cd/<hash>                         │
                    └───────────────────────┬───────────────────────────────┘
                                            │  one Ecto.Multi transaction
                                            ▼
                    ┌─────────────────────────────────────────────────────┐
                    │  blob row · source_file row · import_receipt row ·   │
                    │  change-journal `catalogue`/`job` entries ·          │
                    │  recognition evidence rows (HeaderEvidence provider) │
                    └───────────────┬───────────────────────┬───────────────┘
                                    │                       │
                     clean outcome  │        needs-decision │
                                    ▼                       ▼
                    ┌───────────────────────┐  ┌─────────────────────────────┐
                    │ library (quiet state,  │  │ Needs Attention inbox        │
                    │ "Not yet identified"   │  │ (5 audited resolutions:      │
                    │ badge if applicable)   │  │ correct/attach/retain/       │
                    │                        │  │ exclude/retry)               │
                    └───────────────────────┘  └─────────────────────────────┘

                    ┌─────────────────────────────────────────────────────┐
                    │  Export path: Playstead.Export.Worker (same job/     │
                    │  progress/control model) → write-then-verify each    │
                    │  file to .playstead-tmp-* → fsync → rename → dir     │
                    │  sync → second pass re-hash vs DB → BagIt layout     │
                    │  under PLAYSTEAD_EXPORT_PATH                          │
                    └───────────────────────┬───────────────────────────────┘
                                            │
                                            ▼
                    ┌─────────────────────────────────────────────────────┐
                    │  Reimport identity: member_fingerprint = sha256 over │
                    │  sorted (role, sha256) pairs → alias / incomplete /  │
                    │  variant / fresh-set-reusing-sidecar-UUID            │
                    └─────────────────────────────────────────────────────┘
```

### Recommended Project Structure
```
lib/playstead/
├── blobs/
│   ├── store.ex              # behaviour: open_write/1, write_chunk/2, commit/2, abort/1, exists?/1, stat/1, stream/2, free_bytes/0, writable?/0
│   └── store/
│       └── local_disk.ex     # sole adapter in v1
├── blobs.ex                  # Playstead.Blobs context — only caller of the Store adapter
├── import/
│   ├── session.ex            # import_sessions schema
│   ├── receipt.ex            # import_receipts schema (immutable, D-24/D-25)
│   ├── session_worker.ex     # Oban worker, D-05/D-06
│   ├── writer.ex             # Phoenix.LiveView.UploadWriter impl, D-01a
│   └── outcome.ex            # frozen 9-code enum + reason attributes, D-25
├── recognition/
│   ├── provider.ex           # behaviour
│   ├── header_evidence.ex    # built-in provider, D-16
│   └── dat_pack_importer.ex  # saxy-based Logiqx XML importer, D-18
├── formats/
│   └── validators/           # Tier A/B pure-binary validators, D-14 (gba.ex, gb.ex, nes.ex, snes.ex, md.ex, psx_cue.ex)
├── attention/
│   ├── item.ex
│   └── resolutions.ex        # 5 audited commands, D-27
└── export/
    ├── export.ex             # exports schema, D-38/D-40
    ├── worker.ex             # Playstead.Export.Worker, reuses session job model
    └── bagit_writer.ex       # layout + sidecars, D-34/D-35
```

### Pattern 1: Streaming multi-digest hash in one pass (D-20)
**What:** Compute SHA-256, CRC32, MD5, SHA-1 — and headerless-offset variants for NES/SNES — from a single read of the bytes, never re-reading the source.
**When to use:** Every write-path chunk, in `write_chunk/2` of both the Store adapter and the `UploadWriter`.
**Example:**
```elixir
# Source: Erlang/OTP :crypto stdlib docs (erlang.org/doc/man/crypto.html) — no external package
defmodule Playstead.Blobs.MultiHash do
  # Accumulator carries four running digest contexts plus the CRC32
  # accumulator (:erlang.crc32/2 takes the previous CRC and new data).
  def init do
    %{
      sha256: :crypto.hash_init(:sha256),
      sha1: :crypto.hash_init(:sha),
      md5: :crypto.hash_init(:md5),
      crc32: 0
    }
  end

  def update(acc, chunk) do
    %{
      sha256: :crypto.hash_update(acc.sha256, chunk),
      sha1: :crypto.hash_update(acc.sha1, chunk),
      md5: :crypto.hash_update(acc.md5, chunk),
      crc32: :erlang.crc32(acc.crc32, chunk)
    }
  end

  def finalize(acc) do
    %{
      sha256: :crypto.hash_final(acc.sha256) |> Base.encode16(case: :lower),
      sha1: :crypto.hash_final(acc.sha1) |> Base.encode16(case: :lower),
      md5: :crypto.hash_final(acc.md5) |> Base.encode16(case: :lower),
      crc32: acc.crc32 |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(8, "0")
    }
  end
end
```

### Pattern 2: `Phoenix.LiveView.UploadWriter` for stream-while-hash browser upload (D-01a)
**What:** A custom writer replaces LiveView's default temp-file writer so each chunk both hashes and writes to `PLAYSTEAD_BLOB_PATH/tmp/`.
**When to use:** The single-file browser upload path only (D-01a); the API and inbox paths do not go through LiveView uploads at all.
**Example:**
```elixir
# Source: Phoenix.LiveView.UploadWriter behaviour (hexdocs.pm/phoenix_live_view/Phoenix.LiveView.UploadWriter.html)
defmodule PlaysteadWeb.Import.HashingWriter do
  @behaviour Phoenix.LiveView.UploadWriter

  @impl true
  def init(_opts) do
    path = Path.join(System.fetch_env!("PLAYSTEAD_BLOB_PATH"), "tmp/#{Playstead.CommandId.generate_temp_name()}.partial")
    case File.open(path, [:write, :binary]) do
      {:ok, file} -> {:ok, %{file: file, path: path, hash: Playstead.Blobs.MultiHash.init()}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def meta(state), do: %{path: state.path}

  @impl true
  def write_chunk(chunk, state) do
    case IO.binwrite(state.file, chunk) do
      :ok -> {:ok, %{state | hash: Playstead.Blobs.MultiHash.update(state.hash, chunk)}}
      {:error, reason} -> {:error, reason, state}
    end
  end

  @impl true
  def close(state, :done) do
    :ok = :file.sync(state.file)
    :ok = File.close(state.file)
    {:ok, %{path: state.path, digests: Playstead.Blobs.MultiHash.finalize(state.hash)}}
  end

  def close(state, _reason) do
    File.close(state.file)
    File.rm(state.path)
    :ok
  end
end
```

### Pattern 3: `ImportSessionWorker` cooperative pause/resume (D-05, D-06)
**What:** One Oban job per staged session, unique on `session_id`, iterates `source_file` rows as a durable cursor; pause is checked between files, never via `Oban.pause_queue` (which is runtime-only and global).
**When to use:** Every staged-collection import (inbox scan) and every export.
**Example:**
```elixir
# Pattern derived from Oban unique_jobs + queue-concurrency docs
# (hexdocs.pm/oban/unique_jobs.html, hexdocs.pm/oban/Oban.html) — no
# code lifted verbatim; this is the shape D-05/D-06 describe.
defmodule Playstead.Import.SessionWorker do
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
end
```

### Pattern 4: Write-then-verify export with a directory marker (D-36)
**What:** Each payload/tag file writes to a `.playstead-tmp-*` sibling, fsyncs, renames, then the parent directory itself is fsynced (POSIX durability for the rename to survive a crash); a second full pass re-opens and re-hashes every file against the DB before the `exports` row moves to `verified`.
**When to use:** `Export.Worker`, one file at a time, same control-checked loop as Pattern 3.

### Anti-Patterns to Avoid
- **Hashing after the write instead of during it:** re-reading a multi-GB file a second time to compute SHA-256 after `File.rename` doubles I/O and re-opens a TOCTOU window between "wrote" and "hashed." D-11's read-back re-hash is a *second, deliberate* pass for verification — not a substitute for streaming hash-while-write.
- **Deleting the source or moving instead of copying:** IMPT-01 and PROJECT.md's exact-byte custody promise are violated by any code path that unlinks, moves, or truncates the original inbox/browser file. The inbox mount is `:ro` specifically so this class of bug is caught at the OS level, not just in application code.
- **Trusting `Content-Length` or archive-declared entry sizes without a cap:** the archive-security gate (deferred) exists precisely because declared sizes lie; even the opaque-archive acceptance path (D-21) must cap the bytes it reads for magic-byte sniffing (first ≤64 KiB per D-14) rather than reading declared-length metadata from inside the archive.
- **Using `Oban.pause_queue/2` for per-session pause:** it is a global, runtime-only queue control — pausing one user's session would pause every other session's import/export jobs sharing the `:import` queue. D-06 correctly routes pause through `import_sessions.state` + `requested_control`, checked cooperatively between files.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| XML DAT-pack parsing with XXE resistance | A custom regex/string-scanning XML reader, or raw `:xmerl` with default options | `saxy` (DTD-skipping by default) | Hand-rolled XML parsing on untrusted admin-supplied files reliably reintroduces the exact XXE class D-18 explicitly rules out; `:xmerl`'s defaults are a known Erlang XXE footgun that require explicit `{:allow_dtd, false}`-equivalent hardening most examples online omit |
| Content-addressed storage sharding/lookup | A custom hash-prefix directory scheme with in-memory caching | The `objects/sha256/ab/cd/<hash>` two-level prefix D-11 already specifies, backed by filesystem `stat`/`exists?` calls through `Playstead.Blobs.Store` | This is the exact git-object-store layout (well-understood collision/lookup characteristics at scale); reinventing prefix depth or caching adds bugs with no benefit over the filesystem's own directory-entry lookup |
| BagIt manifest generation / `sha256sum -c` compatible checksum files | A custom manifest format "close enough" to sha256sum | GNU `coreutils` `sha256sum -c` line format (`<hex>  <relative-path>\n`, two spaces, POSIX-safe path encoding) exactly, per RFC 8493 §2.1.3 | D-34 locks this format specifically so a self-hoster can `sha256sum -c manifest-sha256.txt` with zero Playstead tooling as an independent verification path — any deviation (one space, different hash order, CRLF) breaks that promise silently |
| Idempotent mutation replay | A new idempotency mechanism for import/attention/export endpoints | `Playstead.Idempotency.fetch/3` + `execute/4` (already reads `Repo.get_by(Receipt, device_id:, idempotency_key:)` and wraps the effect in one `Ecto.Multi`) `[VERIFIED: playstead-server/lib/playstead/idempotency.ex:58-118]` | The exact fingerprint-mismatch/in-flight/replay state machine this module implements is what D-02/D-30's `Idempotency-Key` requirements assume already exists; a parallel implementation for import endpoints would diverge from PROT-04's frozen contract |
| Rate limiting for upload concurrency | A new token-bucket or GenServer-based limiter | `Playstead.RateLimiter`, `use Hammer, backend: :ets` `[VERIFIED: playstead-server/lib/playstead/rate_limiter.ex]` | Already the app's sole rate limiter (`PlaysteadWeb.Plugs.Throttle` is its only caller per the module's own moduledoc); D-10's `≤2 concurrent API uploads per device` is exactly this library's use case |

**Key insight:** Every "don't hand-roll" item above has a locked decision in `02-CONTEXT.md` that already names the correct primitive — the risk in this phase is not *discovering* the right tool, it is a task plan quietly reimplementing a piece of it (e.g., a bespoke XML scanner "for just this one DAT format," or a second idempotency check inside the export controller) under time pressure. The planner should treat every context reuse table row in `02-CONTEXT.md <code_context>` as a hard constraint, not a suggestion.

## Common Pitfalls

### Pitfall 1: Chunk-boundary digest state lost across `Task.async_stream` workers
**What goes wrong:** If per-file hashing is naively parallelized inside a single file's chunk stream (rather than parallelizing across *files*), each `Task.async_stream` worker gets an independent chunk with no access to the running `:crypto` hash context from the previous chunk, silently producing a wrong hash that only fails at the read-back verification step (or worse, if `PLAYSTEAD_IMPORT_VERIFY=false`, ships silently wrong).
**Why it happens:** D-05's `Task.async_stream(max_concurrency: 2)` parallelizes across *files in a session*, not across chunks *within* one file — but this distinction is easy to blur when writing the worker.
**How to avoid:** One `MultiHash` accumulator per file, threaded sequentially through that file's own chunk loop; `Task.async_stream` operates on the list of `source_file` structs, each task owning its own private accumulator.
**Warning signs:** Hash mismatches that only appear on files above a certain size (i.e., only files with more than one chunk).

### Pitfall 2: `File.rename/2` across filesystems is not atomic
**What goes wrong:** D-11's atomicity guarantee (`tmp/<uuid>.partial` → `objects/sha256/ab/cd/<hash>`) depends on both paths being on the *same* mounted filesystem. If `PLAYSTEAD_BLOB_PATH`'s `tmp/` subdirectory is ever placed on a different volume/bind-mount than `objects/` (e.g., a well-meaning ops change putting temp files on faster local disk), `File.rename/2` silently falls back to copy+delete on some platforms/filesystems, reopening the exact partial-write window D-11 exists to close.
**Why it happens:** Nothing in the schema enforces "tmp and objects share a volume" — it's a deployment-time invariant, not a code-time one.
**How to avoid:** `Playstead.Readiness` (already extended per `<code_context>`) should assert `tmp/` and `objects/` resolve to the same device/mount at boot, the same technique `volumes_check/1` already uses via `/proc/self/mountinfo` `[VERIFIED: playstead-server/lib/playstead/readiness.ex:67-142]` (`@anonymous_volume_id` regex against mountinfo lines).
**Warning signs:** Import throughput drops sharply under load with no CPU/hash-rate explanation (copy+delete is far slower than rename).

### Pitfall 3: TOCTOU between free-space preflight and the actual write
**What goes wrong:** D-10's `free-space preflight bytes + max(1 GiB, 5%)` is checked once before a session starts, but a 250k-file, multi-hour session (D-10's session cap) can exhaust disk space mid-session even though the initial check passed, especially with concurrent sessions or export jobs sharing the same volume.
**Why it happens:** `free_bytes/0` is a point-in-time syscall; nothing prevents another process (another user's session, an export, the DB itself if co-located) from consuming the margin between the check and the write.
**How to avoid:** D-10/D-29 already require re-checking "before every write," not just at session start — the `Store.writer/1` open call, not just the session-start preflight, must re-verify `free_bytes/0` against the specific file's declared size before opening `tmp/<uuid>.partial`; a mid-session disk-full write failure must degrade to `failed_safely{disk_full}` per D-25, pause the whole session per D-29, not merely fail one file.
**Warning signs:** `disk_full` receipts clustering near the end of long sessions rather than being evenly distributed — a sign the preflight is being trusted for the whole session instead of re-checked per write.

### Pitfall 4: CAS commit race — two source files with identical bytes committing concurrently
**What goes wrong:** Two import paths (e.g., a staged session and a concurrent single-file browser upload) hash to the same SHA-256 and both attempt to claim the CAS path `objects/sha256/ab/cd/<hash>`. D-11 already documents the resolution (path exists with a DB row → trust hash+size, no byte compare; path exists without a row → re-hash and adopt), but the *unique constraint* enforcing this must be a DB-level constraint on `blobs.sha256`, not an application-level `exists?` check, or the race window between `exists?` and `commit` reintroduces a duplicate-write bug.
**Why it happens:** `exists?/1` + conditional `write` is a classic check-then-act race under concurrency.
**How to avoid:** `commit/2` (per D-12's signature `commit(writer, sha256) → {:ok, :stored | :existing}`) must attempt the `File.rename` and the DB insert-or-catch-unique-violation together, treating a Postgres unique-constraint violation on `blobs.sha256` as the authoritative "already exists" signal rather than a prior `exists?/1` read.
**Warning signs:** Orphaned `.partial` temp files that never got swept, or two `blob` rows differing only in `id` for the same `sha256` (should be schema-impossible with a correct unique index, but is the symptom to grep for if the constraint is missing).

### Pitfall 5: Untrusted filename/path strings reaching `File.rename`/`Path.join` in export and CUE-companion attachment
**What goes wrong:** D-15's CUE parsing already caps bare relative names and forbids `..`/separators/control chars — but the *export* path (D-34) constructs `data/<system-slug>/<set folder>/<member files>` from `declared_name`/`original_name` values that, for imported content, originated as attacker/user-controlled strings (an uploaded file's client-supplied filename). Any `Path.join` call that does not first pass the name through the same sanitize function D-34 specifies is a path-traversal primitive on export (writing outside `PLAYSTEAD_EXPORT_PATH`).
**Why it happens:** Import-side sanitization (D-22's display-title stripping) and export-side sanitization (D-34's cross-platform-unsafe-character rule) are two different code paths guarding two different fields (`display_title` vs `original_name`/`exported_as`) — it is easy to sanitize one and forget the other feeds into a filesystem write.
**How to avoid:** A single `Playstead.Export.Sanitize` module used at every `Path.join` call site in `bagit_writer.ex`, with a property/fuzz test (see Validation Architecture) asserting the sanitized output never contains `..`, a leading `/`, a NUL byte, or resolves outside the target root via `Path.expand/2` comparison.
**Warning signs:** Any export test fixture whose member filename came from a No-Intro-style parse failure (raw unsanitized original name) producing a file outside the expected `data/` subtree.

## Code Examples

Verified patterns from official sources:

### Streaming SHA-256 (Erlang/OTP `:crypto`, no dependency)
```elixir
# Source: erlang.org/doc/apps/crypto/crypto.html — :crypto.hash_init/1, hash_update/2, hash_final/1
ctx = :crypto.hash_init(:sha256)
ctx = :crypto.hash_update(ctx, chunk1)
ctx = :crypto.hash_update(ctx, chunk2)
digest = :crypto.hash_final(ctx) |> Base.encode16(case: :lower)
```

### RFC 9530 `Repr-Digest` header format (D-02)
```
Repr-Digest: sha-256=:<base64-of-raw-32-byte-digest>:
```
`[CITED: RFC 9530 §3 — the value is the *structured field byte sequence* form, base64 of the raw digest bytes wrapped in colons, not hex]`. The server-side comparison in D-02 must decode this base64 form and compare against the raw digest bytes computed via `:crypto.hash_final/1` — comparing against the hex-encoded string (used everywhere else in this phase, e.g. CAS paths) is a format mismatch that will always fail even for correct uploads if not handled explicitly.

### BagIt `manifest-sha256.txt` line format (D-34, RFC 8493 §2.1.3)
```
<64-hex-char-sha256>  <relative-path-from-bag-root>
```
Two spaces between hash and path (GNU `sha256sum -c` compatible); relative paths use `/` regardless of host OS.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| `peburrows/saxy` (original repo) | `qcam/saxy` (actively maintained fork, same package name on hex.pm) | Ongoing since ~2022 | `mix hex.info saxy` and hexdocs both point to `qcam/saxy` as of the 1.6.x line researched this session; the planner should link to `github.com/qcam/saxy`, not the older repo, in any code comments |
| tus/chunked resumable upload as a default expectation | Single streaming `PUT` with full-body re-send on interruption | This project's own decision (D-02), not an industry shift | v2's `TRAN-01` is the deferred resumable-upload work; Phase 2 explicitly does not build it — do not let a plan task "future-proof" by half-implementing chunking |

**Deprecated/outdated:** None specific to this phase's stack — `oban` 2.24, `phoenix_live_view` 1.2.11, and `ecto_sql` 3.14 are all current major-version lines with no announced deprecation affecting the APIs this phase uses.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `saxy`'s hex.pm package legitimacy (manual check, since the automated `package-legitimacy` seam does not cover the `hex` ecosystem) | Package Legitimacy Audit | Low — the package is 6 years old with 9.1M downloads and a public GitHub source; the risk is procedural (bypassing the automated gate) rather than substantive. Planner should still gate the `mix.exs` addition behind `checkpoint:human-verify` |
| A2 | Exact `Ecto.Multi`/unique-constraint mechanics for CAS commit races (Pitfall 4) — described from Ecto/Postgres general knowledge, not verified against a written test in this codebase (no `blobs` schema exists yet to inspect) | Common Pitfalls, Pitfall 4 | Medium — if the eventual `blobs.sha256` unique index is missing or the commit path doesn't catch the constraint violation correctly, duplicate-blob races are possible under concurrent import; the plan-checker should verify the migration includes `unique_index(:blobs, [:sha256])` |
| A3 | `:erlang.crc32/2` incremental accumulator signature — from Erlang/OTP `erts` documentation training knowledge, not re-verified via a live `erl` shell this session | Pattern 1 code example | Low — CRC32 is a supporting fingerprint (D-20), not the trust-bearing SHA-256; a signature mismatch would fail at compile/dialyzer time, not silently corrupt data |

**If this table is empty:** N/A — see rows above.

## Open Questions

1. **Exact `blobs` table unique-constraint and migration shape for CAS commit races**
   - What we know: D-11/D-12 describe the desired behavior (trust hash+size on collision, no byte compare) and D-13 describes the `blobs` table has no `user_id`.
   - What's unclear: No migration or schema file exists yet in the repo for `blobs`/`source_file`/`import_receipts` (this phase is greenfield for those tables) — the exact index/constraint names are Claude's Discretion per `02-CONTEXT.md`.
   - Recommendation: Planner should include a migration task with an explicit `unique_index(:blobs, [:sha256])` and a test asserting concurrent `commit/2` calls for the same bytes converge to one row (property test recommended, see Validation Architecture).

2. **`Repr-Digest` base64-vs-hex encoding mismatch handling**
   - What we know: RFC 9530 specifies base64 of raw digest bytes; the rest of this phase's protocol (CAS paths, receipts, DAT hashes) uses lowercase hex throughout.
   - What's unclear: Whether `PlaysteadWeb.Plugs` already has a Digest-field parser from Phase 1's protocol work (none was found in the reusable-assets list in `02-CONTEXT.md <code_context>`), or whether this phase must build the first one.
   - Recommendation: Treat as new work; add an explicit contract test asserting the encode/decode round-trip since a base64/hex mix-up would make every legitimate upload fail `422 import_digest_mismatch`.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Docker | Compose deploy target for `PLAYSTEAD_INBOX_PATH`/`PLAYSTEAD_EXPORT_PATH` bind mounts | ✓ `[VERIFIED: docker --version]` | 29.5.2 | — |
| Erlang/OTP | `:crypto`, `:erlang.crc32/2` stdlib hashing | ✓ `[VERIFIED: elixir --version]` | OTP 28, erts-16.3 | — |
| Elixir / Mix | Application build/test | ✓ `[VERIFIED: mix --version]` | 1.19.5 | — |
| `saxy` (hex) | Logiqx DAT-pack SAX import (D-18) | Not yet installed — new dependency this phase adds | 1.6.1 confirmed on hex.pm | None needed; `mix deps.get` after `mix.exs` edit |
| `/proc/self/mountinfo` | `Playstead.Readiness` same-volume assertion for `tmp/`↔`objects/` (Pitfall 2) | Linux-container-only; not present on macOS host — but this app runs exclusively inside the Linux release container per Phase 1's Docker Compose deploy path `[VERIFIED: playstead-server/lib/playstead/readiness.ex:76-142 already assumes container runtime]` | — | Existing `:unknown` fallback branch in `anonymous_volume?/1` already handles absence gracefully |

**Missing dependencies with no fallback:** none — `saxy` is a simple `mix deps.get` addition with no system-level prerequisite.
**Missing dependencies with fallback:** none blocking.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | ExUnit (Elixir stdlib) `[VERIFIED: playstead-server/config/test.exs — Ecto.Adapters.SQL.Sandbox pool config present]`; Wallaby 0.31.0 for the browser suite `[VERIFIED: playstead-server/mix.lock]` |
| Config file | `playstead-server/config/test.exs`, `playstead-server/test/support/` |
| Quick run command | `mix test test/playstead/import/ test/playstead/export/ --max-failures 1` |
| Full suite command | `mix precommit` (already defined: `compile --warnings-as-errors`, `deps.unlock --unused`, `format --check-formatted`, `test`) `[VERIFIED: playstead-server/mix.exs aliases]` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|--------------------|-------------|
| IMPT-01 | Preflight preview shows copy/untouched/storage-use before import | LiveView (`Phoenix.LiveViewTest`) | `mix test test/playstead_web/live/import_live_test.exs` | ❌ Wave 0 |
| IMPT-02 | Post-import SHA-256/size/provenance inspection | contract (controller + schema) | `mix test test/playstead_web/controllers/api/v1/imports_controller_test.exs` | ❌ Wave 0 |
| IMPT-03 | Nine-code receipt taxonomy | unit (pure function over outcome classification) | `mix test test/playstead/import/outcome_test.exs` | ❌ Wave 0 |
| IMPT-04 | Ordered multi-file manifest, required members, CUE parse | unit + adversarial fixture (QUAL-02 spirit) | `mix test test/playstead/formats/validators/psx_cue_test.exs` | ❌ Wave 0 |
| IMPT-05 | Staged collection: pause/resume/retry/reconcile | integration (Oban `Oban.Testing` manual mode) | `mix test test/playstead/import/session_worker_test.exs` | ❌ Wave 0 |
| IMPT-06 | Needs Attention resolutions (5 audited commands) | LiveView + unit (`Playstead.AuditLog` entry assertion) | `mix test test/playstead_web/live/attention_live_test.exs` | ❌ Wave 0 |
| PORT-02 | Export write-then-verify, reimport identity round-trip | contract (the 5 round-trip assertions in `02-CONTEXT.md <specifics>`) | `mix test test/playstead/export/round_trip_test.exs` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** the quick-run scoped `mix test` command above for the module(s) touched
- **Per wave merge:** `mix precommit` (full suite: compile-warnings-as-errors, format check, complete `mix test`)
- **Phase gate:** Full suite green before `/gsd-verify-work`; additionally, the archive-security adversarial corpus (deferred spike, not this phase's gate) must not be conflated with this phase's own parser adversarial fixtures for Tier A/B validators and the DAT-pack SAX importer, which **are** in scope now

### Wave 0 Gaps
- [ ] `test/playstead/import/`, `test/playstead/export/`, `test/playstead/formats/validators/`, `test/playstead/recognition/`, `test/playstead/attention/` — no test directories exist yet for this phase's contexts (confirmed via `find test/playstead -maxdepth 2 -type d` this session; only `pairing/`, `protocol/`, `sync/` exist)
- [ ] `test/playstead_web/live/import_live_test.exs`, `attention_live_test.exs`, `export_live_test.exs` — no LiveView test files exist for import/export yet
- [ ] Framework addition: `{:stream_data, "~> 1.1", only: [:test]}` — **not currently a dependency** `[VERIFIED: grep of playstead-server/mix.lock found no stream_data/propcheck entry]`. Recommended for property-based fuzzing of the Tier A/B binary validators (D-14), the CUE parser (D-15), and the sanitize function (Pitfall 5) — QUAL-02's "adversarial fixtures for every enabled parser" requirement, though formally a Phase 5 gate, directly names the parsers this phase introduces. Adding `stream_data` now (test-only, zero runtime cost) lets the plan-checker require property tests for every parser this phase ships rather than deferring adversarial coverage to Phase 5.
- [ ] `test/support/fixtures/roms/` — a fixtures directory for magic-byte-valid and adversarially-malformed sample files (GBA/GB/GBC/NES/SNES/MD headers, valid and truncated/corrupted; CUE files with `..`, absolute paths, oversized entry counts) does not yet exist; each Tier A/B validator task should add its own fixture set here

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-------------------|
| V2 Authentication | yes (inherited) | Phase 1's device-credential header auth on every `/api/v1` route this phase adds (`:device_auth` pipeline per `02-CONTEXT.md <code_context>` integration points) |
| V3 Session Management | yes (inherited) | Phase 1 sudo-mode gate for console mutations; no new session mechanism this phase |
| V4 Access Control | yes | Every new schema (`source_file`, `import_sessions`, `import_receipts`, `asset_set`, `attention`, `exports`) carries `user_id` and is scoped through Phoenix Scopes (D-13) — `blobs` is the deliberate global exception, and cross-user duplicate disclosure is explicitly forbidden (D-13) |
| V5 Input Validation | yes | Pure binary pattern-match validators (D-14), CUE hard caps (D-15: ≤64 KiB, ≤99 entries, no `..`/separators/control chars), sanitized display titles (D-22: NFC, bidi/zero-width stripped, 200 code-point cap), sanitized export filenames (D-34) |
| V6 Cryptography | yes | SHA-256 as the trust-bearing digest throughout (`:crypto` stdlib, never hand-rolled); no encryption-at-rest claim made or needed in this phase |
| V12 File and Resources | yes | This is the phase's primary domain: upload size ceilings (D-03/D-10), free-space preflight (D-10), atomic write-then-commit (D-11), read-only inbox mount (D-01), quarantine-not-delete (D-28/D-29), archive-opaque-only until the deferred security-gate spike passes (D-21) |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|----------------------|
| Path traversal via crafted filename (uploaded original name, CUE-referenced BIN filename, DAT-pack entry name) reaching `Path.join`/`File.rename` on export or companion-attach | Tampering | D-15's bare-relative-name-only CUE rule (no `..`/separators/control chars); D-34's export sanitize-on-cross-platform-unsafe-char rule; a single shared sanitize module per Pitfall 5, with `Path.expand/2`-against-root verification before every write |
| Zip bomb / decompression-ratio attack via any code path that opens an archive's internal structure | Denial of Service | Not applicable to this phase's shipped surface — D-21 keeps every archive (zip/7z/rar/gzip/xz/zstd, detected by magic bytes) fully opaque; the archive-security gate (isolated CPU/memory/path/recursion/expanded-size limits, adversarial corpus) is an explicit *pre-condition* for any future phase that opens archive internals, not something this phase's code touches |
| Symlink/hardlink escape from a scanned inbox directory | Spoofing / Information Disclosure | The inbox mount is `:ro` at the Docker level (D-01 owner ruling) — a symlink inside the inbox pointing outside the mount would, if followed, read host-filesystem content the container should never see; the inbox scan must use `File.lstat/1` (not `File.stat/1`, which follows symlinks) and skip/quarantine symlink entries rather than following them, since D-01's `:ro` guarantee is only as strong as the scanner's symlink handling |
| Zip-bomb-adjacent CUE/DAT declared-size lies (a CUE `INDEX`/track declaring an implausible size, or a DAT `<rom size="...">` far exceeding realistic ROM sizes) | Denial of Service | D-15's hard caps (≤64 KiB CUE text, ≤99 entries) bound the *parse* cost regardless of declared sizes; the DAT-pack importer (D-18) similarly needs size/entry caps on the XML itself (already specified: "size/entry caps, fuzzed") — declared per-entry byte sizes inside a DAT are metadata compared against actually-hashed bytes, never trusted to allocate buffers |
| XXE / external entity expansion in the Logiqx XML DAT-pack import | Information Disclosure / DoS | `saxy`'s default DTD-skip behavior (verified this session) plus D-18's explicit "SAX, no DTD/entities" requirement — the importer must not override `saxy`'s default entity-reference handler to expand external entities |
| Hash collision / mismatch between client-declared and server-computed digest on API upload | Tampering | D-02's mandatory server re-hash-and-compare against the `Repr-Digest` header, `422 import_digest_mismatch` on mismatch with nothing stored — client-declared hashes (Digest header, precheck calls) are never trusted for CAS placement, only for the up-front dedupe hint |
| Partial/torn writes surviving a crash and being served as if complete | Tampering / DoS | D-11's temp-then-atomic-rename write path plus D-29's "failure before commit deletes the temp; no partial blob is ever visible" guarantee, backed by a boot-time and session-start orphan-temp sweep |
| TOCTOU between free-space preflight and actual write (multi-hour sessions) | Denial of Service | See Common Pitfalls, Pitfall 3 — re-check `free_bytes/0` per write, not just per session |
| CAS commit race producing divergent rows for identical bytes | Tampering (data integrity) | See Common Pitfalls, Pitfall 4 — DB-level unique constraint on `blobs.sha256`, constraint-violation-as-signal rather than check-then-act |

## Sources

### Primary (HIGH confidence)
- `~/projects/playstead/playstead-server/mix.lock` — read directly this session; confirms exact pinned versions of `oban` (2.24.0), `phoenix_live_view` (1.2.11), `ecto_sql` (3.14.0), `hammer` (7.4.0), `bandit` (1.12.5)
- `~/projects/playstead/playstead-server/lib/playstead/idempotency.ex`, `readiness.ex`, `sync.ex`, `command_id.ex`, `rate_limiter.ex`, `audit_log.ex` — read directly this session; function signatures quoted verbatim above
- `.planning/phases/02-explainable-import-and-exact-export/02-CONTEXT.md` — the authoritative, already-adversarially-reviewed decision record for this phase (D-01–D-40)
- `mix hex.info saxy` (interactive session output) — release history, download counts, source-repo pointer

### Secondary (MEDIUM confidence)
- Saxy README/hexdocs (`hexdocs.pm/saxy/readme.html`) via WebSearch — DTD-skip and external-entity-handling default behavior
- RFC 9530 (Digest Fields) and RFC 8493 (BagIt) — cited by `02-CONTEXT.md` decisions and cross-checked via general knowledge of the `Repr-Digest` structured-field encoding and `sha256sum -c` line format
- Oban unique-jobs and queue-concurrency documentation (`hexdocs.pm/oban/unique_jobs.html`, `hexdocs.pm/oban/Oban.html`) via WebSearch — confirms `Oban.pause_queue` is runtime/global-only, supporting D-06's rejection of it
- Phoenix.LiveView.UploadWriter behaviour documentation via WebSearch — confirms the four-callback shape (`init/1`, `meta/1`, `write_chunk/2`, `close/2`)

### Tertiary (LOW confidence)
- `:erlang.crc32/2` incremental-accumulator signature in the CRC32 code example — from training knowledge, not re-verified via a live shell this session (flagged as Assumption A3)
- Erlang XXE footgun claim re: `:xmerl` defaults — WebSearch result summary only, not independently read against the `:xmerl` source in this session

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every package's exact installed version was read directly from `mix.lock`/`mix.exs`; the one new package (`saxy`) was confirmed via live `mix hex.info` plus a corroborating web search of its official docs
- Architecture: HIGH — Phase 2's architecture is already the product of four parallel multi-lens research fan-outs with an owner-reviewed adversarial pass, recorded in `02-CONTEXT.md`; this document adds implementation-level code skeletons and verifies the Phase 1 reuse surface by reading the actual source
- Pitfalls: MEDIUM — the five pitfalls above are derived from applying general Elixir/OTP/Postgres concurrency and filesystem-durability knowledge to this phase's specific decisions (D-11, D-12, D-20, D-34); none were independently reproduced as failing tests in this session, since no code for this phase exists yet

**Research date:** 2026-08-28
**Valid until:** 2026-09-27 (30 days — this is a stable-stack phase; the `saxy` recommendation and hex.lock-verified versions should be re-checked if planning is delayed past that window)
