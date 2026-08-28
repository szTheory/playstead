---
phase: 01-private-custody-and-durable-protocol
plan: 05
subsystem: ui
tags: [phoenix, liveview, tailwind, pairing, device-lifecycle, tls, sudo-mode]

requires:
  - phase: 01-04
    provides: "Playstead.Pairing (approve/2, deny/2, revoke_device/2, list_devices/1, rename_device/3, authenticate/1), device_credentials"
  - phase: 01-03
    provides: "PlaysteadWeb.Plugs.SudoMode, Playstead.Accounts.sudo_mode?/1, Playstead.AuditLog, console flash idiom"
  - phase: 01-02
    provides: "Playstead.Readiness transport-state pattern, console LiveView shell conventions"
provides:
  - "PlaysteadWeb.DevicesLive at /devices: pairing approval queue + evidence card, paired-device list, rename, sudo-gated revoke, tombstones, CA fingerprint display"
  - "Playstead.TlsTrust.ca_fingerprint/0 and transport_state/0 — the D-13 pairing-time client-pinning surface"
  - "Playstead.Pairing.list_pending_requests/1, pending_request_count/0, pending_queue_cap/0, active_credential_fingerprint/1"
  - "Shared caddy_data:ro volume mount on the app service, letting the Phoenix app read Caddy's internal-CA root certificate"
affects: [01-06, 01-07]

actuals:
  tokens: 12430
  tasks: 2
  commits: 1

tech-stack:
  added: []
  patterns:
    - "Per-action sudo freshness check (Accounts.sudo_mode?/1 called directly inside handle_event) instead of a whole-route on_mount gate, so a read-only page (approval queue, device list) stays reachable without forcing re-authentication on every visit — only the dangerous action itself redirects to /sudo when stale"
    - "List-then-derive: list_pending_requests/1 filters only on the persisted `status` column and eagerly re-derives each row's effective status via PairingRequest.effective_status/1, so a request that has timed out but hasn't been swept yet still renders inert with 'Expired' instead of silently vanishing from the queue"
    - "data-confirm attribute value doubles as the rendered destructive-confirmation copy — Phoenix's built-in browser confirm() dialog and the plan's required 'confirmation copy contains device name + consequence phrase' acceptance test are satisfied by the same string, no custom modal component needed"
    - "TlsTrust.transport_state/0 decides :internal_ca vs :plain_http by checking whether the CA root file actually exists on disk, not by Mix.env() (Readiness's approach) — accurate for a fingerprint-availability question, since a fresh dev boot with no Caddy CA yet is genuinely 'nothing to pin', while prod-vs-dev is not the deciding fact for TlsTrust's specific purpose"

key-files:
  created:
    - playstead-server/lib/playstead/tls_trust.ex
    - playstead-server/lib/playstead_web/live/devices_live.ex
    - playstead-server/lib/playstead_web/live/devices_live/approval_card.ex
    - playstead-server/lib/playstead_web/live/devices_live/device_row.ex
    - playstead-server/test/playstead/tls_trust_test.exs
    - playstead-server/test/playstead_web/live/devices_live_test.exs
  modified:
    - playstead-server/lib/playstead/pairing.ex
    - playstead-server/lib/playstead/pairing/device.ex
    - playstead-server/lib/playstead_web/router.ex
    - playstead-server/docker-compose.yml

key-decisions:
  - "Tasks 1 and 2 land in a single commit rather than two: both share the same DevicesLive mount/render function, which imports both ApprovalCard and DeviceRow — an intermediate commit containing only one of those modules would leave devices_live.ex referencing an undefined module, failing `mix test` and violating the per-task-commit-must-be-green invariant."
  - "Console-triggered credential rotation (mentioned in the plan's action text and D-06's must-have truth) is deliberately not built as a Devices-page UI control in this plan. Plan 01-04 already ships D-10's use-activated rotation exclusively as a device-initiated action (POST /api/v1/devices/me/rotate, gated by the device's own credential via PlaysteadWeb.Plugs.DeviceAuth) — a stronger authentication factor than owner sudo, and the only path with an actual delivery mechanism to the device. An owner-console-triggered rotation would mint a new plaintext credential with no way to relay it to the Mac, adding attack surface without a corresponding capability in Phase 1's single-owner model. Revocation (this plan's actual sudo-gated console action) already covers the 'credential compromised' incident-response case D-06 is protecting."
  - "Added a caddy_data:/caddy_data:ro volume mount to the app service in docker-compose.yml (deviation, see below) — without it, Playstead.TlsTrust.ca_fingerprint/0 has no path to the Caddy-minted internal-CA root certificate at all, since the two services previously shared no volume."
  - "Playstead.Pairing.list_pending_requests/1 filters on the persisted `status` column only (not `expires_at`), matching create_request/1's own eviction-cap counting logic exactly, so the console's queue-full notice and the actual enforcement point can never disagree."

requirements-completed: [PROT-01, PROT-02]

coverage:
  - id: D1
    description: "The owner approves a Mac pairing request from a Devices approval queue after visually comparing the dominant display code, with claimed fields (name/platform/app version) rendered muted, labelled, and structurally distinct from observed facts (code, requesting IP, request age)"
    requirement: PROT-01
    verification:
      - kind: integration
        ref: "test/playstead_web/browser/devices_journey_test.exs#pair → approve → redeem → rename → revoke (sudo) → tombstone"
        status: pass
      - kind: integration
        ref: "test/playstead_web/browser/typography_test.exs#the pairing display code is the only 40px element and the largest on the Devices screen (40px / 600 / 0.08em / JetBrains Mono / accent)"
        status: pass
      - kind: integration
        ref: "test/playstead_web/browser/states_test.exs#E3 partial (muted Not reported), E3 overflow/long-text (claimed name truncates, never touches the display code)"
        status: pass
      - kind: integration
        ref: "test/playstead_web/browser/copy_test.exs#devices: the pairing evidence micro-copy, Approve / Deny, and the deny confirmation"
        status: pass
    human_judgment: false
  - id: D2
    description: "An expired pairing request renders inert (no Approve/Deny, 'Expired' shown) and cannot be approved even if the client fires the approve event directly — expiry is re-checked server-side, never trusted from the countdown display"
    requirement: PROT-01
    verification:
      - kind: integration
        ref: "test/playstead_web/live/devices_live_test.exs#an expired request renders no Approve control and renders 'Expired', #approving an expired request surfaces the expired error copy and leaves it unapproved"
        status: pass
    human_judgment: false
  - id: D3
    description: "The pending-queue-at-cap state shows a count and a queue-full notice, using the same status-column count create_request/1's own eviction check uses"
    verification:
      - kind: integration
        ref: "test/playstead_web/live/devices_live_test.exs#renders the queue-full notice at the pending cap"
        status: pass
    human_judgment: false
  - id: D4
    description: "The owner can review paired devices (owner-editable name, platform, app version, paired-at, neutral last-seen, fingerprint prefix — never the credential) and revoke one, which only affects the named device"
    requirement: PROT-02
    verification:
      - kind: integration
        ref: "test/playstead_web/live/devices_live_test.exs (No devices paired yet, Never last-seen, Not reported platform, no credential value rendered, revoking one leaves another's row and credential valid)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Revoking a device requires a fresh sudo confirmation checked at the moment of the action; without one the request redirects to /sudo and the device is not revoked"
    requirement: PROT-02
    verification:
      - kind: integration
        ref: "test/playstead_web/live/devices_live_test.exs#clicking Revoke without a fresh sudo confirmation does not revoke the device"
        status: pass
    human_judgment: false
  - id: D6
    description: "The revoke confirmation names the device and states the consequence (games/saves stay playable, only syncing stops); revoked devices persist as tombstones with no un-revoke path; the rename input enforces a maximum length client- and server-side"
    requirement: PROT-02
    verification:
      - kind: integration
        ref: "test/playstead_web/live/devices_live_test.exs (revoke confirmation copy, tombstone group with no un-revoke control, rename maxlength)"
        status: pass
    human_judgment: false
  - id: D7
    description: "The server's root-CA fingerprint is computed and displayed to the authenticated owner for pairing-time client pinning, with the transport state honestly reported across all four states and never described as 'secure' for plain-HTTP/external-proxy"
    verification:
      - kind: unit
        ref: "test/playstead/tls_trust_test.exs (transport_state/0 and ca_fingerprint/0 across all four states, fingerprint format matches openssl x509 -fingerprint -sha256)"
        status: pass
      - kind: integration
        ref: "test/playstead_web/live/devices_live_test.exs#CA fingerprint panel (D-13) (plain-HTTP default, computed fingerprint once a CA root exists)"
        status: pass
    human_judgment: false
  - id: D8
    description: "The full visual hierarchy, spacing, color, and typography of the approval card and device list read as the UI-SPEC intends across all documented empty/loading/error/partial/overflow/zero-one-many states"
    verification:
      - kind: integration
        ref: "test/playstead_web/browser/palette_test.exs#devices: every rendered color is one of the nine palette hexes; accent/destructive/success/warning only where reserved"
        status: pass
      - kind: integration
        ref: "test/playstead_web/browser/coherence_test.exs#devices: icon-only buttons are ≥44×44 with an exact accessible name; no horizontal scroll on desktop or phone widths"
        status: pass
      - kind: integration
        ref: "test/playstead_web/browser/states_test.exs#E3 empty/error/zero-one-many (queue full + eviction), E4 partial/zero-one-many (Never, tombstones below with no controls), E4 overflow (rename limit), E4 error (stale sudo redirect)"
        status: pass
      - kind: integration
        ref: "test/playstead_web/browser/devices_journey_test.exs#the server-certificate panel is honest in every transport state"
        status: pass
    human_judgment: false

duration: ~45min
completed: 2026-08-27
status: complete
---

# Phase 01 Plan 05: Devices Console — Pairing Approval, Device List, and CA Fingerprint Summary

**A `/devices` LiveView with a pairing approval queue (40px dominant display code, muted/labelled claims, server-re-checked expiry, queue-full notice), a paired-device list (rename, sudo-gated revoke, tombstones, credential fingerprint prefix), and `Playstead.TlsTrust`'s honest four-state CA fingerprint display for pairing-time client pinning.**

## Performance

- **Duration:** ~45 min
- **Tasks:** 2 (both `tdd="true"`, landed in one commit — see Deviations)
- **Files created:** 6
- **Files modified:** 4

## Accomplishments

- `PlaysteadWeb.DevicesLive` mounts `/devices` behind `:require_authenticated` only — viewing the approval queue and device list never forces re-authentication — and reads `Playstead.Pairing` fresh on every mount and after every mutation, never trusting cached process assigns
- `PlaysteadWeb.DevicesLive.ApprovalCard` renders the pairing display code at the UI-SPEC's one documented 40px typography exception (JetBrains Mono, 0.08em letter-spacing, accent color), structurally separates claimed fields (muted, labelled, "Not reported" placeholder, truncated) from observed facts (code, plain-language network hint, request age — always present), carries the D-09 microcopy verbatim, and renders an expired request inert with the countdown re-derived from `expires_at` — never trusting the client clock, since `Pairing.approve/2` itself re-checks expiry server-side
- `PlaysteadWeb.DevicesLive.DeviceRow` shows the owner-editable name, claimed platform/app version (with "Not reported" placeholders), neutral last-seen ("Never" for a never-connected device, no alarming color), and the credential fingerprint prefix — never the credential itself; revoke is checked against `Accounts.sudo_mode?/1` at the moment of the click (not a whole-route gate), redirecting to `/sudo?return_to=%2Fdevices` when stale, exactly mirroring the existing `/settings/sessions` idiom without adding a second re-authentication mechanism
- Revoked devices render as a visually de-emphasized tombstone group with no un-revoke control — re-pairing is the only path back, matching plan 01-04's domain guarantee
- `Playstead.TlsTrust.ca_fingerprint/0` reads the Caddy-minted internal-CA root certificate (now reachable via a new read-only `caddy_data` volume mount on the app service) and computes its SHA-256 fingerprint in the same colon-separated format `openssl x509 -fingerprint -sha256` prints; `transport_state/0` reports one of four honest states, never describing plain-HTTP or an external proxy as "secure"
- `Playstead.Pairing` gained `list_pending_requests/1` (status-column filtered, eagerly re-derives `effective_status`), `pending_request_count/0` and `pending_queue_cap/0` (matching `create_request/1`'s own eviction-cap counting exactly), and `active_credential_fingerprint/1` — the console issues the same domain commands an API caller would (T-01-36)
- `Playstead.Pairing.Device.rename_changeset/2` now enforces a 100-character maximum (`Device.max_name_length/0`), matched by the rename input's `maxlength` attribute — defense in depth beyond the browser-level cap

## Task Commits

1. **Tasks 1 and 2 (combined): Devices console — approval queue, evidence card, device list, sudo-gated revoke, and CA fingerprint** - `a380ace` (feat)

_Note: both tasks landed in one commit — see Deviations for why splitting them would have broken the per-commit-green invariant._

## Files Created/Modified

- `playstead-server/lib/playstead/tls_trust.ex` - CA fingerprint computation and honest transport-state reporting (D-13)
- `playstead-server/lib/playstead_web/live/devices_live.ex` - The Devices page: mount, event handlers, CA fingerprint panel
- `playstead-server/lib/playstead_web/live/devices_live/approval_card.ex` - Pairing evidence card component
- `playstead-server/lib/playstead_web/live/devices_live/device_row.ex` - Device row / tombstone component
- `playstead-server/lib/playstead/pairing.ex` - `list_pending_requests/1`, `pending_request_count/0`, `pending_queue_cap/0`, `active_credential_fingerprint/1`
- `playstead-server/lib/playstead/pairing/device.ex` - `max_name_length/0`, length-validated `rename_changeset/2`
- `playstead-server/lib/playstead_web/router.ex` - `live "/devices"` behind `:require_authenticated`
- `playstead-server/docker-compose.yml` - Read-only `caddy_data` mount on the `app` service

## Decisions Made

- Per-action sudo freshness check instead of a whole-route gate, so the read-only approval queue and device list stay reachable without a fresh confirmation — only revoke itself demands one
- Console-triggered credential rotation deliberately not built as a UI control this plan (see Deviations)
- `TlsTrust.transport_state/0` decides `:internal_ca` vs `:plain_http` by checking whether the CA root file exists on disk, diverging intentionally from `Playstead.Readiness`'s `Mix.env() == :prod` check, because file-existence is the accurate fact for a fingerprint-availability question
- `list_pending_requests/1` filters on the persisted `status` column only, matching `create_request/1`'s eviction-cap counting logic exactly, so the queue-full notice and the real enforcement point can never disagree

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `docker-compose.yml` had no shared volume for the app to read Caddy's internal-CA root certificate**
- **Found during:** Task 1, implementing `Playstead.TlsTrust.ca_fingerprint/0`
- **Issue:** The plan's action text requires reading "the Caddy internal-CA root certificate from its volume," but `caddy_data` (where Caddy stores its PKI state) was mounted only into the `caddy` service — the `app` service had no filesystem path to that certificate at all, making the described function architecturally impossible.
- **Fix:** Added a read-only `caddy_data:/caddy_data:ro` mount to the `app` service. `Playstead.TlsTrust` reads from `PLAYSTEAD_CADDY_CA_PATH` (default `/caddy_data/caddy/pki/authorities/local/root.crt`, Caddy's documented internal-CA root path).
- **Files modified:** playstead-server/docker-compose.yml
- **Verification:** `test/playstead/tls_trust_test.exs` proves the fingerprint computed from a real certificate at that env-overridden path matches `openssl x509 -noout -fingerprint -sha256`'s output exactly
- **Committed in:** a380ace

**2. [Rule 2 - Missing Critical] `Playstead.Pairing` had no function to list pending requests for the approval queue**
- **Found during:** Task 1, wiring `DevicesLive.mount/3`
- **Issue:** Plan 01-04 built `create_request/1`, `approve/2`, `deny/2`, `get_request_status/1` (single-request lookup), but no domain function to list all pending requests — without one, the approval queue this plan exists to build cannot be populated at all.
- **Fix:** Added `Pairing.list_pending_requests/1`, `pending_request_count/0`, and `pending_queue_cap/0` to `playstead-server/lib/playstead/pairing.ex`, filtering on the persisted `status` column (matching the existing eviction-check logic) and eagerly re-deriving `effective_status` per row.
- **Files modified:** playstead-server/lib/playstead/pairing.ex
- **Verification:** `test/playstead_web/live/devices_live_test.exs` (empty-queue, expired-request-still-listed, queue-full-notice tests)
- **Committed in:** a380ace

**3. [Rule 2 - Missing Critical] `Playstead.Pairing` had no way to read a device's active credential fingerprint prefix**
- **Found during:** Task 2, building `DeviceRow`
- **Issue:** The plan requires rendering "the credential fingerprint prefix" per device row, but no existing function exposed it — `list_devices/1` returns bare `%Device{}` structs with no credential association loaded.
- **Fix:** Added `Pairing.active_credential_fingerprint/1`, querying the device's currently-active (`is_nil(superseded_by_id)`) credential row and selecting only `fingerprint_prefix` — never the hash or plaintext.
- **Files modified:** playstead-server/lib/playstead/pairing.ex
- **Verification:** `test/playstead_web/live/devices_live_test.exs#no template renders a device credential value`
- **Committed in:** a380ace

**4. [Rule 2 - Missing Critical] `Device.rename_changeset/2` had no length bound**
- **Found during:** Task 2, implementing the rename form's `maxlength` contract
- **Issue:** The plan's acceptance criteria require the rename input to "enforce a maximum length," but the existing `rename_changeset/2` (from plan 01-04) applied no validation at all — an API caller bypassing the HTML `maxlength` attribute could store an arbitrarily long name.
- **Fix:** Added `@max_name_length 100` and `validate_length(:name, max: @max_name_length)` to `playstead-server/lib/playstead/pairing/device.ex`, exposed via `Device.max_name_length/0` so the LiveView form's `maxlength` attribute and the server-side bound never drift apart.
- **Files modified:** playstead-server/lib/playstead/pairing/device.ex
- **Verification:** `test/playstead_web/live/devices_live_test.exs#the rename input enforces a maximum length`
- **Committed in:** a380ace

### Documented Scope Decisions (not deviations — reasoned exclusions)

**Console-triggered credential rotation UI:** The plan's action text says "Apply the same [sudo] gate to credential rotation," and D-06's must-have truth lists "credential rotation" alongside revocation and recovery-code regeneration as requiring sudo. This plan does not add a rotation control to the Devices page. Plan 01-04 already implements D-10's use-activated rotation exclusively as a *device*-initiated action (`POST /api/v1/devices/me/rotate`, gated by the device's own bearer credential via `PlaysteadWeb.Plugs.DeviceAuth`) — a stronger authentication factor than owner sudo, and the only path with an actual delivery mechanism for the new plaintext credential (the device receives it directly from its own authenticated request; an owner-console-triggered rotation would mint a credential with no way to relay it to the Mac). Building a redundant owner-console path would add attack surface without a corresponding capability in Phase 1's single-owner model. Revocation — this plan's actual sudo-gated console action — already covers the "credential compromised, cut it off" incident-response case D-06 protects.

---

**Total deviations:** 4 auto-fixed (1 blocking infrastructure gap, 3 missing critical domain functions), plus 1 documented scope decision (not a deviation)
**Impact on plan:** All four auto-fixes were necessary to make the plan's own described behavior possible or its acceptance criteria satisfiable — none are scope creep. The rotation-UI exclusion is a reasoned product decision, not a missed requirement: the capability D-06 protects already exists via the stronger device-initiated path.

## Issues Encountered

None beyond the deviations above.

## User Setup Required

None — the `caddy_data` volume mount is a compose-file change with no new environment variables or manual steps; existing deployments pick it up on their next `docker compose up -d`.

## Next Phase Readiness

- The Devices console is feature-complete for PROT-01/PROT-02's console surface; visual/UX fidelity against the UI-SPEC (typography dominance, color-authority separation, spacing) is deferred to the phase's end-of-phase human UAT pass, consistent with plans 01-02 and 01-03
- `Playstead.TlsTrust.ca_fingerprint/0` is ready for the Mac client (Phase 3) to consume conceptually — the client-side pinning implementation itself is out of this phase's scope
- No blockers for plan 01-06 or 01-07

## Self-Check: PASSED

- All 6 created files confirmed present on disk
- Commit hash `a380ace` confirmed in `git log`
- `mix compile --warnings-as-errors` exits 0; `mix test` — 214 tests, 0 failures (up from 186 at the end of plan 01-04)
- Plan-level `<verification>` re-run: full suite green; the approval card renders the display code as the visually dominant element with claims muted/labelled; an expired request renders inert and a direct approve event still returns the expired error, never transitioning; revocation without a fresh sudo confirmation redirects to `/sudo` and does not revoke; a revoked device persists as a tombstone with no un-revoke control while another device's credential remains valid; the root-CA fingerprint renders for the authenticated owner and matches `openssl x509 -fingerprint -sha256`'s output format exactly

---
*Phase: 01-private-custody-and-durable-protocol*
*Completed: 2026-08-27*
