---
phase: 01-private-custody-and-durable-protocol
plan: 04
subsystem: auth
tags: [phoenix, ecto, rfc8628, pairing, device-credentials, hammer, audit-log]

requires:
  - phase: 01-03
    provides: "Playstead.AuditLog.record/3, PlaysteadWeb.Plugs.Throttle, PlaysteadWeb.Plugs.SudoMode, Playstead.RateLimiter"
provides:
  - "Playstead.Pairing: the full pairing state machine (create_request/1, get_request_status/1, approve/2, deny/2, redeem/2, authenticate/1, rotate_credential/1, revoke_device/2, list_devices/1, rename_device/3, expire_stale_requests/0)"
  - "Playstead.Pairing.DisplayCode: RFC 8628-shaped human display code (Base-20 consonant alphabet, XXXX-XXXX)"
  - "pairing_requests, devices, device_credentials tables — separate device identity and credential rows"
  - "POST/GET /api/v1/device-pairing/requests, POST .../requests/:id/redeem (unauthenticated)"
  - "GET /api/v1/devices/me, POST /api/v1/devices/me/rotate (device-auth gated) — PlaysteadWeb.Plugs.DeviceAuth"
  - "PlaysteadWeb.Plugs.ClientIp: trusted-proxy-hop requesting IP"
  - "New error codes: pairing_request_not_approved, slow_down (plus the already-registered pairing_request_expired, pairing_request_already_redeemed, device_revoked)"
affects: [01-05, 01-06, 01-07]

actuals:
  tokens: 17868
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Guarded UPDATE ... WHERE status = 'approved' inside a transaction (same once-only pattern as plan 01-02's setup-token claim) makes concurrent redemption safe via Postgres row-level locking — no explicit SELECT FOR UPDATE needed"
    - "utc_datetime_usec (not the app-wide utc_datetime default) on pairing_requests, since second-precision inserted_at ties under any real request burst make 'oldest pending' ambiguous for eviction"
    - "Credential rows are never physically deleted on revocation — only device.revoked_at is set. Since the stored value is an irreversible SHA-256 hash (no recoverable secret), keeping the row is what lets authenticate/1 distinguish device_revoked from a generic, oracle-free unauthorized on the revoked device's next request"
    - "Device credentials use is_nil(activated_at) as the use-activation signal: a freshly rotated credential activates (and deletes whichever row it superseded) on its own first successful authenticate/1 call, never on a timer"

key-files:
  created:
    - playstead-server/lib/playstead/pairing.ex
    - playstead-server/lib/playstead/pairing/pairing_request.ex
    - playstead-server/lib/playstead/pairing/display_code.ex
    - playstead-server/lib/playstead/pairing/device.ex
    - playstead-server/lib/playstead/pairing/device_credential.ex
    - playstead-server/lib/playstead/pairing/expire_stale_requests_worker.ex
    - playstead-server/lib/playstead_web/controllers/api/v1/pairing_controller.ex
    - playstead-server/lib/playstead_web/controllers/api/v1/devices_controller.ex
    - playstead-server/lib/playstead_web/plugs/client_ip.ex
    - playstead-server/lib/playstead_web/plugs/device_auth.ex
    - playstead-server/priv/repo/migrations/20260827180000_create_pairing_requests.exs
    - playstead-server/priv/repo/migrations/20260827180001_create_devices_and_credentials.exs
    - playstead-server/test/support/fixtures/pairing_fixtures.ex
    - playstead-server/test/playstead/pairing/display_code_test.exs
    - playstead-server/test/playstead/pairing_test.exs
    - playstead-server/test/playstead_web/controllers/api/v1/pairing_controller_test.exs
    - playstead-server/test/playstead_web/controllers/api/v1/devices_controller_test.exs
    - playstead-server/test/playstead_web/plugs/device_auth_test.exs
  modified:
    - playstead-server/config/config.exs
    - playstead-server/lib/playstead/audit_log.ex
    - playstead-server/lib/playstead_web/error_codes.ex
    - playstead-server/lib/playstead_web/router.ex

key-decisions:
  - "revoke_device/2 does not physically delete device_credentials rows, despite that being the plan's literal wording — it only sets the devices.revoked_at tombstone. Deleting the row would make the revoked device's subsequent request indistinguishable from a never-existed credential (generic unauthorized), breaking the plan's own load-bearing PROT-02 isolation proof, which requires the distinct device_revoked code. Since the stored value is only an irreversible SHA-256 hash, retaining it carries no meaningful security cost."
  - "pairing_requests uses utc_datetime_usec instead of the app-wide utc_datetime default, since second-precision timestamps tie under any fast sequence of request creations, making the pending-queue eviction's 'oldest' selection nondeterministic"
  - "Both the initial redemption-issued credential and every rotated credential start with activated_at: nil; the very first successful authenticate/1 call is what activates a credential and deletes whatever it superseded. This uniform mechanism means pairing-time issuance needs no special case distinct from rotation's handoff"
  - "PlaysteadWeb.Plugs.ClientIp trusts x-forwarded-for unconditionally, relying on D-15's network-topology guarantee (only Caddy publishes host ports, so the app can only ever be reached through Caddy) rather than an explicit trusted-proxy allowlist"

requirements-completed: [PROT-01, PROT-02]

coverage:
  - id: D1
    description: "A Mac POSTs a pairing request and receives both a private single-use device_code (client-generated, only its hash stored) and a human-readable display code; the owner approves from a scope-bound action with no auto-approval path; the Mac polls plain HTTPS and honors slow_down"
    requirement: PROT-01
    verification:
      - kind: unit
        ref: "test/playstead/pairing_test.exs (create_request/1, get_request_status/1, approve/2 describe blocks)"
        status: pass
      - kind: integration
        ref: "test/playstead_web/controllers/api/v1/pairing_controller_test.exs (POST/GET /device-pairing/requests, rate-limited and slow_down cases)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Redemption is two-code: the display code is never an authorization input, redemption requires the separate device_code, and a wrong device_code is indistinguishable in response shape from a not-yet-approved request"
    requirement: PROT-01
    verification:
      - kind: integration
        ref: "test/playstead_web/controllers/api/v1/pairing_controller_test.exs#POST .../redeem (correct redemption, wrong device_code, pending-request cases)"
        status: pass
    human_judgment: false
  - id: D3
    description: "A second redemption of an already-redeemed request is rejected (409) with no second credential issued, and two concurrent redemptions of the same approved request produce exactly one credential row"
    requirement: PROT-01
    verification:
      - kind: integration
        ref: "test/playstead_web/controllers/api/v1/pairing_controller_test.exs#a second redemption... and #two concurrent redemptions..."
        status: pass
    human_judgment: false
  - id: D4
    description: "The device credential is delivered exactly once, stored hashed, and accepted only from the Authorization header — a query-parameter credential is rejected"
    requirement: PROT-01
    verification:
      - kind: unit
        ref: "test/playstead_web/plugs/device_auth_test.exs (header accepted, query param rejected, unknown credential rejected)"
        status: pass
      - kind: integration
        ref: "test/playstead_web/controllers/api/v1/devices_controller_test.exs#GET /api/v1/devices/me"
        status: pass
    human_judgment: false
  - id: D5
    description: "Use-activated rotation: the old credential keeps authenticating until the new one is first used, at which point the old one stops"
    requirement: PROT-01
    verification:
      - kind: unit
        ref: "test/playstead_web/plugs/device_auth_test.exs#rotation handoff (D-10)"
        status: pass
      - kind: integration
        ref: "test/playstead_web/controllers/api/v1/devices_controller_test.exs#POST /api/v1/devices/me/rotate"
        status: pass
    human_judgment: false
  - id: D6
    description: "Revoking one device stops that device's next request (401 device_revoked) while every other device's credential keeps working, proven by a single isolation contract test; re-pairing after revocation always creates a new device row and the revoked row survives as a tombstone"
    requirement: PROT-02
    verification:
      - kind: integration
        ref: "test/playstead_web/controllers/api/v1/devices_controller_test.exs#PROT-02 isolation contract"
        status: pass
      - kind: unit
        ref: "test/playstead/pairing_test.exs#revoke_device/2, list_devices/1, rename_device/3"
        status: pass
    human_judgment: false
  - id: D7
    description: "Every pairing lifecycle event (requested, evicted, approved, denied, redeemed, revoked) is written to the append-only audit log, and every error path renders through PlaysteadWeb.Problem with a stable machine code"
    verification:
      - kind: unit
        ref: "test/playstead/pairing_test.exs (audit assertions across create_request/1, approve/2, revoke_device/2)"
        status: pass
    human_judgment: false

duration: 55min
completed: 2026-08-27
status: complete
---

# Phase 01 Plan 04: Pairing Ceremony and Device Credentials Summary

**RFC 8628-shaped two-code pairing ceremony (display code + private device_code) with one-time device credential issuance guarded by a concurrency-safe redeem transaction, header-only Authorization-based device auth, use-activated rotation, and revocation whose tombstone semantics are proven by a single PROT-02 isolation contract test.**

## Performance

- **Duration:** ~55 min
- **Tasks:** 3 (all `tdd="true"`)
- **Files created:** 18
- **Files modified:** 4

## Accomplishments

- `Playstead.Pairing.DisplayCode.generate/0` produces an 8-character, Base-20-consonant, `XXXX-XXXX` display code via crypto-strong rejection sampling — visual-comparison-only, never an authorization input (D-07/D-08); a 1000-iteration property test proves the alphabet and shape hold
- `Playstead.Pairing` implements the full persisted state machine: `create_request/1` (hashes the client's `device_code`, mints a display code, sets a 10-minute expiry, and evicts the oldest pending request — audited as `pairing_request_evicted` — once the fixed pending-queue cap is hit), `get_request_status/1` (re-derives `expired` from `expires_at` on every call, no background-job dependency), `approve/2`/`deny/2` (both hard-require a `%Scope{}` — there is no code path around it, so D-07's "never auto-approve" is structurally enforced, not just documented)
- `redeem/2` runs the once-only redemption inside a guarded `UPDATE ... WHERE status = 'approved'` (the same pattern plan 01-02 proved for setup-token claiming), verified with a real two-`Task.async` concurrency test: exactly one credential row survives, the loser gets `pairing_request_already_redeemed` (409); a wrong `device_code` on an approved request returns the identical error shape as a not-yet-approved request, giving no oracle
- Device identity (`devices`) and credential (`device_credentials`) are separate tables; `PlaysteadWeb.Plugs.DeviceAuth` reads the bearer credential only from the `Authorization` header (a query-parameter credential is silently ignored, not fallen back to) and rejects a revoked device with the distinct `device_revoked` code
- `rotate_credential/1` implements the use-activated handoff via a uniform `is_nil(activated_at)` signal: a new credential (whether from initial redemption or rotation) activates — and deletes whatever it superseded — on its own first successful `authenticate/1` call, never on a timer; proven end to end (old token works immediately after rotation, new token's first use retires the old one)
- `revoke_device/2` sets a permanent `revoked_at` tombstone and audits `device_revoked`; `list_devices/1` and `rename_device/3` are scope-bound (`rename_device/3` never touches `claimed_name`); re-pairing after revocation always produces a brand-new device row while the revoked row survives, queryable, forever
- The PROT-02 isolation contract test — explicitly called out in the plan as the load-bearing proof — pairs two devices, revokes one, and asserts within a single test that the revoked device gets `device_revoked` (401) while the other gets 200
- `PlaysteadWeb.Plugs.ClientIp` derives the requesting IP from the trusted Caddy hop (D-09); the pending-request creation endpoint is per-IP rate-limited via the existing `PlaysteadWeb.Plugs.Throttle`

## Task Commits

1. **Task 1: Pairing domain, display code, and the request/poll endpoints** - `b13fc61` (feat, tdd)
2. **Task 2: One-time credential issuance, header-only device authentication, and use-activated rotation** - `529e8ca` (feat, tdd)
3. **Task 3: Revocation, tombstones, and the PROT-02 isolation contract tests** - `8fe1774` (feat, tdd)

## Files Created/Modified

- `playstead-server/lib/playstead/pairing.ex` - The full pairing/device/credential domain module
- `playstead-server/lib/playstead/pairing/pairing_request.ex` - Persisted request schema, expiry re-derivation
- `playstead-server/lib/playstead/pairing/display_code.ex` - Base-20 consonant display code
- `playstead-server/lib/playstead/pairing/device.ex`, `device_credential.ex` - Separate identity/credential schemas
- `playstead-server/lib/playstead/pairing/expire_stale_requests_worker.ex` - Housekeeping-only Oban job
- `playstead-server/lib/playstead_web/controllers/api/v1/pairing_controller.ex` - create/show/redeem actions
- `playstead-server/lib/playstead_web/controllers/api/v1/devices_controller.ex` - me/rotate actions
- `playstead-server/lib/playstead_web/plugs/client_ip.ex` - Trusted-proxy-hop requesting IP
- `playstead-server/lib/playstead_web/plugs/device_auth.ex` - Header-only device credential auth
- `playstead-server/priv/repo/migrations/20260827180000_create_pairing_requests.exs`, `20260827180001_create_devices_and_credentials.exs`
- `playstead-server/config/config.exs` - Oban Cron for the housekeeping worker; `filter_parameters` now discards `device_code`/`credential`
- `playstead-server/lib/playstead/audit_log.ex` - Added `list_by_subject/1`
- `playstead-server/lib/playstead_web/error_codes.ex` - Added `pairing_request_not_approved`, `slow_down`
- `playstead-server/lib/playstead_web/router.ex` - `/device-pairing/*` and `/devices/*` routes and pipelines

## Decisions Made

- `revoke_device/2` intentionally does not physically delete `device_credentials` rows (see Deviations below)
- `pairing_requests` uses `utc_datetime_usec` instead of the app-wide `utc_datetime` default so pending-queue eviction's "oldest" selection is deterministic under a fast request burst
- Both initial and rotated credentials start with `activated_at: nil`; the first successful `authenticate/1` call is the single activation mechanism, avoiding a special case for pairing-time issuance
- `PlaysteadWeb.Plugs.ClientIp` trusts `x-forwarded-for` unconditionally, relying on D-15's network-topology guarantee that only Caddy can reach the app directly

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `revoke_device/2` does not delete `device_credentials` rows, despite the plan's literal wording**
- **Found during:** Task 3, writing the PROT-02 isolation contract test
- **Issue:** The plan's action text says revocation "deletes every `device_credentials` row for that device." Implemented literally, a revoked device's subsequent authentication attempt finds no credential row at all and returns a generic `unauthorized` — indistinguishable from a credential that never existed. This directly contradicts the plan's own must-have truth and load-bearing acceptance criterion: "A revoked device's next request returns 401 with the machine code `device_revoked`."
- **Fix:** `revoke_device/2` sets only the `devices.revoked_at` tombstone and leaves credential rows in place. `authenticate/1`'s existing `device.revoked_at` check is what produces the distinct `device_revoked` code. Since the stored value is an irreversible SHA-256 hash (never the plaintext credential), retaining it carries no recoverable-secret risk — D-10's own storage model already accepted this for every non-revoked credential.
- **Files modified:** playstead-server/lib/playstead/pairing.ex
- **Verification:** `test/playstead_web/controllers/api/v1/devices_controller_test.exs#PROT-02 isolation contract` and `test/playstead/pairing_test.exs#revoke_device/2...` both assert the revoked device gets `device_revoked`, not a generic `unauthorized`
- **Committed in:** 8fe1774 (Task 3 commit)

**2. [Rule 1 - Bug] `pairing_requests.inserted_at` needed microsecond precision for deterministic eviction**
- **Found during:** Task 1, writing the pending-queue-cap eviction test
- **Issue:** The app-wide `generators: [timestamp_type: :utc_datetime]` truncates to whole seconds. Twenty rapid fixture inserts in the same test landed in the same second, making `ORDER BY inserted_at ASC LIMIT 1` pick an arbitrary tied row rather than the genuinely oldest pending request — the eviction test failed intermittently depending on UUID-driven physical row order.
- **Fix:** Overrode `timestamps(type: :utc_datetime_usec)` on the `pairing_requests` migration and schema specifically (not the app-wide default).
- **Files modified:** playstead-server/priv/repo/migrations/20260827180000_create_pairing_requests.exs, playstead-server/lib/playstead/pairing/pairing_request.ex
- **Verification:** `test/playstead/pairing_test.exs#create_request/1 filling the pending queue to its cap...` passes deterministically across repeated runs
- **Committed in:** b13fc61 (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 — bugs surfaced by actually writing and running the plan's own load-bearing tests)
**Impact on plan:** Deviation 1 is a direct, necessary correction to keep the plan's own must-have truth and acceptance criterion satisfiable; deviation 2 is a one-line precision fix with no behavioral change beyond making eviction deterministic. No scope creep.

## Issues Encountered

None beyond the two deviations above.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `Playstead.Pairing.authenticate/1` and `PlaysteadWeb.Plugs.DeviceAuth` are the credential-verification path every future authenticated `/api/v1` endpoint (plans 01-06, 01-07) attaches to via the `:device_auth` router pipeline
- `Playstead.AuditLog`'s pairing event names (`pairing_requested`, `pairing_request_evicted`, `pairing_approved`, `pairing_denied`, `pairing_redeemed`, `device_revoked`) are established for any later console-side pairing UI to read
- Visual/UX design of an owner-facing Devices approval queue and list page (LiveView console) is out of this plan's scope — the domain functions (`list_devices/1`, `rename_device/3`, `revoke_device/2`, `approve/2`, `deny/2`) are ready for plan 01-05 or a later console plan to build a UI on top of
- No blockers for the next plan in this phase

## Self-Check: PASSED

- All 18 created files confirmed present on disk
- All 3 task commit hashes (`b13fc61`, `529e8ca`, `8fe1774`) confirmed in `git log`
- `mix compile --warnings-as-errors` exits 0; `mix test` — 186 tests, 0 failures
- Plan-level `<verification>` re-run: full suite green; a pairing request yields a display code and a private device code where only the latter redeems; a second redemption returns 409 and issues no credential; two concurrent redemptions yield exactly one credential row; revoking one device returns 401 `device_revoked` for it and 200 for another device in the same test; re-pairing produces a new device row and the revoked tombstone remains

---
*Phase: 01-private-custody-and-durable-protocol*
*Completed: 2026-08-27*
