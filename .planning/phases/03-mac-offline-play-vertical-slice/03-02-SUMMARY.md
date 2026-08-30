---
phase: 03-mac-offline-play-vertical-slice
plan: 02
subsystem: api
tags: [range-requests, http-206, http-416, etag, if-range, head, capability-negotiation, elixir, phoenix]

# Dependency graph
requires:
  - phase: 01-private-custody-and-durable-protocol
    provides: device_auth pipeline, capability negotiation envelope, RFC 9457 problem+json
  - phase: 02-explainable-import-and-exact-export
    provides: Playstead.Blobs / Blobs.Store storage seam, SourceFile ownership model
provides:
  - "Frozen Range/If-Range/206/416/HEAD contract on GET /api/v1/blobs/:sha256, published client protocol for D-19"
  - "Playstead.Blobs.Store.byte_size_of/1 seam callback"
  - "Bounded positional-read range clause in LocalDisk.build_stream/2 (no whole-object File.read!)"
  - "transfer capability namespace advertises range-resume via version 1.1.0"
affects: [03-07-mac-download-engine, 03-mac-offline-play-vertical-slice]

actuals:
  tokens: 8441
  tasks: 3
  commits: 5

tech-stack:
  added: []
  patterns:
    - "Positional streaming reads via Stream.resource/3 + :file.pread/3 instead of File.read! + binary_part for range serving"
    - "Endpoint-level stash_original_method plug to recover the pre-Plug.Head HTTP method for a controller that needs to distinguish real HEAD from GET"
    - "Capability version bump within an existing namespace (@namespace_ranges override map) instead of adding a new envelope key"

key-files:
  created:
    - playstead-server/test/playstead/blobs/store/local_disk_test.exs
  modified:
    - playstead-server/lib/playstead_web/controllers/api/v1/blobs_controller.ex
    - playstead-server/lib/playstead/blobs/store/local_disk.ex
    - playstead-server/lib/playstead/blobs/store.ex
    - playstead-server/lib/playstead/blobs.ex
    - playstead-server/lib/playstead_web/error_codes.ex
    - playstead-server/lib/playstead_web/router.ex
    - playstead-server/lib/playstead_web/endpoint.ex
    - playstead-server/lib/playstead/protocol/capabilities.ex
    - playstead-server/test/playstead_web/controllers/api/v1/blobs_controller_test.exs
    - playstead-server/test/playstead_web/controllers/api/v1/capabilities_controller_test.exs
    - playstead-server/test/playstead/protocol/negotiation_test.exs
    - playstead-server/test/playstead/import/session_worker_test.exs

key-decisions:
  - "ETag is the sha256 wrapped in double quotes (was unquoted) — this is the exact value the Mac download engine will echo back as If-Range in plan 03-07"
  - "Multi-range, malformed, suffix-range, and foreign-unit Range headers all collapse to the full 200 body rather than raising, deliberately narrowing the frozen contract to one shape a client must implement"
  - "transfer capability advertises range-resume by version (max 1.1.0 within the existing namespace), never by adding a key to the frozen /api/v1/capabilities envelope"
  - "Plug.Head rewrites HEAD to GET before the router, so an endpoint-level stash_original_method plug preserves the pre-rewrite method for BlobsController to emit an explicit Content-Length on a true HEAD instead of chunked transfer-encoding"

requirements-completed: [CACH-01]

coverage:
  - id: D1
    description: "GET /api/v1/blobs/:sha256 serves a single satisfiable Range as 206 with quoted ETag, Accept-Ranges, and Content-Range; LocalDisk's range clause reads positionally instead of loading the whole object"
    requirement: "CACH-01"
    verification:
      - kind: integration
        ref: "test/playstead_web/controllers/api/v1/blobs_controller_test.exs#GET /api/v1/blobs/:sha256 with Range: bytes=N-"
        status: pass
      - kind: unit
        ref: "test/playstead/blobs/store/local_disk_test.exs#a range on an object larger than the chunk size returns only the requested extent, in bounded reads"
        status: pass
    human_judgment: false
  - id: D2
    description: "Frozen Range contract complete: If-Range match/mismatch, 416 with Content-Range and registered problem+json code, HEAD mirrors GET headers with no body, multi-range/malformed/suffix/foreign-unit headers collapse to full 200, single-byte edge range and clamped over-long range both correct, zero-length blob handled"
    requirement: "CACH-01"
    verification:
      - kind: integration
        ref: "test/playstead_web/controllers/api/v1/blobs_controller_test.exs#GET /api/v1/blobs/:sha256 — frozen Range/If-Range/416/HEAD contract"
        status: pass
      - kind: integration
        ref: "test/playstead_web/controllers/api/v1/blobs_controller_test.exs#GET /api/v1/blobs/:sha256 — zero-length blob"
        status: pass
    human_judgment: false
  - id: D3
    description: "transfer capability namespace advertises range-resume via max version 1.1.0, with the frozen /api/v1/capabilities envelope shape provably unchanged and version-skew negotiation degrading to compatible_with_limits, never incompatible"
    requirement: "CACH-01"
    verification:
      - kind: unit
        ref: "test/playstead_web/controllers/api/v1/capabilities_controller_test.exs#D-19: transfer advertises max 1.1.0, every other namespace stays at 1.0.0"
        status: pass
      - kind: unit
        ref: "test/playstead/protocol/negotiation_test.exs#D-19: a client declaring transfer 1.0.0 still overlaps the server's 1.0.0-1.1.0 range and is never incompatible on transfer alone"
        status: pass
    human_judgment: false

duration: 13min
completed: 2026-08-30
status: complete
---

# Phase 3 Plan 02: Frozen Blob Range/If-Range/206/416/HEAD Contract Summary

**`GET`/`HEAD /api/v1/blobs/:sha256` now speaks the full published Range-resume contract — quoted ETag, `206`/`416`/`Accept-Ranges`, `If-Range`, and bounded positional reads instead of a whole-object `File.read!` — with `transfer` capability version 1.1.0 advertising it.**

## Performance

- **Duration:** 13 min (commit span 17:57:57–18:10:49 local)
- **Tasks:** 3
- **Files modified:** 13 (1 created, 12 modified)
- **Commits:** 5 (2 TDD RED/GREEN pairs + 1 plain feature commit for the capability advertisement)

## Accomplishments

- `GET /api/v1/blobs/:sha256` serves a single satisfiable Range (`bytes=first-` or `bytes=first-last`) as `206` with `Content-Range`/`Content-Length`, and an unranged request gets `Accept-Ranges: bytes` plus a quoted ETag (`"<sha256>"`).
- `Playstead.Blobs.Store.LocalDisk`'s range clause no longer calls `File.read!` — it reads positionally via `Stream.resource/3` over `:file.pread/3`, bounded by its existing chunk size, verified against a fixture object larger than that chunk size.
- The frozen contract's edge cases are all correct and tested: single-byte range at the exact lower edge (`bytes=0-0`), an out-of-range first position (`416` with `Content-Range: bytes */N`), an over-long last position clamped to the final byte, multi-range and malformed/suffix/foreign-unit headers collapsing to the full `200` body rather than raising, `If-Range` match/mismatch, a zero-length blob (`416` with any Range, `200` empty without one), and `HEAD` mirroring `GET`'s status/ETag/Accept-Ranges/Content-Length with no body — gated by the same `authorized?/2`/`playable?/2` ownership and quarantine checks as the unranged path.
- `range_not_satisfiable` (416) is a registered `PlaysteadWeb.ErrorCodes` entry rendered through `PlaysteadWeb.Problem.send_problem/4`, never a hand-built body.
- `transfer` capability namespace advertises range-resume by version (`max: "1.1.0"`) within the existing namespace, with the frozen `/api/v1/capabilities` envelope's key shape provably unchanged and a client declaring an older transfer version still negotiating `compatible_with_limits`, never `incompatible`.

## Task Commits

Each task followed RED → GREEN (tasks 1 and 2 are `tdd="true"`); task 3 is a plain feature commit:

1. **Task 1: End-to-end single-range GET**
   - `c58ed1a` test(03-02): add failing Range/ETag/Accept-Ranges tests for blobs GET (RED)
   - `b9ceb16` feat(03-02): serve single-range GET with quoted ETag and bounded positional reads (GREEN)
2. **Task 2: Complete the frozen contract — If-Range, 416, HEAD, multi-range collapse, edge extents**
   - `de2647f` test(03-02): add failing tests for the frozen Range/If-Range/416/HEAD contract (RED)
   - `632576d` feat(03-02): complete the frozen Range/If-Range/416/HEAD contract (GREEN)
3. **Task 3: Advertise range-resume in the transfer capability namespace**
   - `49b55b0` feat(03-02): advertise transfer 1.1.0 range-resume without unfreezing the capabilities envelope

**Plan metadata:** committed alongside this SUMMARY (worktree mode — orchestrator commits STATE.md/ROADMAP.md centrally after wave merge).

## Files Created/Modified

- `playstead-server/lib/playstead_web/controllers/api/v1/blobs_controller.ex` — Range/If-Range/HEAD-aware `show/2`, `head_show/2`, and the private `parse_range/2`, `single_range/2`, `send_range/4`, `send_not_satisfiable/2`, `etag_for/1`, `range_decision/3` helpers
- `playstead-server/lib/playstead/blobs/store/local_disk.ex` — bounded positional-read range clause (`Stream.resource/3` + `:file.pread/3`), `byte_size_of/1`
- `playstead-server/lib/playstead/blobs/store.ex` — new `byte_size_of/1` behaviour callback
- `playstead-server/lib/playstead/blobs.ex` — `byte_size_of/1` facade delegate
- `playstead-server/lib/playstead_web/error_codes.ex` — `range_not_satisfiable: {416, "Range Not Satisfiable"}`
- `playstead-server/lib/playstead_web/router.ex` — `head "/:sha256", BlobsController, :head_show`
- `playstead-server/lib/playstead_web/endpoint.ex` — `stash_original_method` plug ahead of `Plug.Head`, preserving the pre-rewrite HTTP method
- `playstead-server/lib/playstead/protocol/capabilities.ex` — `@namespace_ranges` override map, `transfer` at `{"1.0.0", "1.1.0"}`, moduledoc documents the 1.1.0 meaning
- `playstead-server/test/playstead_web/controllers/api/v1/blobs_controller_test.exs` — the frozen Range contract test suite (200/206/416/HEAD/multi-range/malformed/If-Range/zero-length/kill-and-resume reassembly)
- `playstead-server/test/playstead/blobs/store/local_disk_test.exs` — bounded-read range test module (new file)
- `playstead-server/test/playstead_web/controllers/api/v1/capabilities_controller_test.exs` — transfer 1.1.0 assertion
- `playstead-server/test/playstead/protocol/negotiation_test.exs` — transfer version-skew negotiation test
- `playstead-server/test/playstead/import/session_worker_test.exs` — `InsufficientSpaceStore` test double gained `byte_size_of/1` (deviation, see below)

## Decisions Made

See `key-decisions` in frontmatter. The most consequential: quoting the ETag and collapsing multi-range/malformed headers to full-200 are one-way protocol freezes per D-19 (already owner-approved in discuss-phase per the plan's `<reversibility>` note) — every future client's transfer engine builds on these exact header shapes.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Implemented the new `Store.byte_size_of/1` callback in a test double**
- **Found during:** Task 3's full-suite verification (`mix test`)
- **Issue:** Adding `byte_size_of/1` to the `Playstead.Blobs.Store` behaviour (task 1) left `Playstead.Import.SessionWorkerTest.InsufficientSpaceStore` — a `@behaviour Playstead.Blobs.Store` test double — without an implementation, producing a compile warning (`function byte_size_of/1 required by behaviour ... is not implemented`).
- **Fix:** Added `def byte_size_of(_sha256), do: {:error, :not_found}` alongside the double's existing `stat/1` stub.
- **Files modified:** `playstead-server/test/playstead/import/session_worker_test.exs`
- **Verification:** `MIX_ENV=test mix compile --force --warnings-as-errors` is clean; full `mix test` run is 782 tests, 0 failures.
- **Committed in:** `49b55b0` (Task 3 commit)

**2. [Rule 1 - Bug] Fixed a test's use of `assert_problem/3` against a true HEAD response**
- **Found during:** Task 2 GREEN verification
- **Issue:** A HEAD response carries no body by the time it reaches the test — Plug's test adapter (`Plug.Adapters.Test.Conn`) strips the body for any request whose *original* method was `HEAD`, independent of the endpoint's `Plug.Head` rewriting `conn.method` to `"GET"` before the router. The initial test assertion called `assert_problem/3`, which decodes a JSON body — failing with `Jason.DecodeError` on the (correctly) empty body.
- **Fix:** Rewrote the assertion to check status, empty body, and the `content-type` header directly rather than decoding JSON — this also surfaced (and is the reason for) the `stash_original_method` plug, since without it the controller had no way to tell a real HEAD apart from a GET after `Plug.Head`'s rewrite, and so could not emit the case-correct `Content-Length` header the acceptance criteria require.
- **Files modified:** `playstead-server/test/playstead_web/controllers/api/v1/blobs_controller_test.exs`, `playstead-server/lib/playstead_web/endpoint.ex`, `playstead-server/lib/playstead_web/controllers/api/v1/blobs_controller.ex`
- **Verification:** `mix test test/playstead_web/controllers/api/v1/blobs_controller_test.exs` green (21 tests).
- **Committed in:** `632576d` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 missing critical, 1 bug). **Impact on plan:** Both were necessary to make the HEAD path correct and to keep the full suite warning-free; no scope creep beyond what the plan's tasks already required.

## Issues Encountered

- `playstead-server/deps` did not exist in this worktree (only the main checkout had them fetched). Ran `mix deps.get` and `MIX_ENV=test mix compile` once at the start of execution — routine worktree setup, not a plan deviation.
- The plan's task 2 mentions a store-level test at `test/playstead/blobs/store/local_disk_test.exs`; the project's existing convention for this module was `test/playstead/blobs/store_local_disk_test.exs` (flat, not nested). Created the new file at the plan's stated nested path as instructed — both files now coexist; no conflict since they cover different concerns (existing CAS write-path tests vs. new range-read tests).

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- The Range/ETag/If-Range wire contract is frozen and ready for `playstead-mac`'s `DownloadEngine.swift` (plan 03-07) to implement against — the exact header shapes (quoted ETag echoed as `If-Range`, `206`/`Content-Range`, `416`/`Content-Range: bytes */N`) are proven server-side with a byte-identical kill-and-resume reassembly test.
- `transfer` capability max `1.1.0` is discoverable via the existing `/api/v1/capabilities` negotiation path with no envelope shape change, so a client can gate its resume behavior on it without a new protocol path major.
- No blockers for downstream plans in this phase.

## Self-Check: PASSED

- All `key-files` (created and modified) verified present on disk with `[ -f ]`.
- `git log --oneline --all --grep="03-02"` returns 6 commits (2 RED/2 GREEN for tasks 1–2, 1 feat for task 3, 1 docs for this SUMMARY).
- TDD gate sequence confirmed: `test(03-02)` commits precede their matching `feat(03-02)` commits for both `tdd="true"` tasks.
- Re-ran all task-level `<acceptance_criteria>` and the plan-level `<verification>`: `mix test` is 782 tests, 0 failures, no compile warnings (`MIX_ENV=test mix compile --force --warnings-as-errors` clean).

---
*Phase: 03-mac-offline-play-vertical-slice*
*Completed: 2026-08-30*
