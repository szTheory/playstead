---
phase: "03"
slug: "mac-offline-play-vertical-slice"
status: secured
# threats_open counts only OPEN threats at or above workflow.security_block_on.
threats_open: 0
asvs_level: 1
block_on: high
created: "2026-09-19"
register_authored_at_plan_time: true
threats_total: 78
threats_closed: 75
---

# Phase 03 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

All 16 plans were inspected. The register below contains every threat from every
parseable `<threat_model>` block. Mitigations were checked against implementation
at ASVS L1; plan-authored `accept` dispositions are transcribed into the accepted
risks log rather than being treated as implicit closure.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|---|---|---|
| User-controlled game/BIOS/emulator inputs → Mac client | Local files and third-party executables must not bypass identity, provenance, quarantine, or path controls. | Executables, archives, ROM/BIOS bytes, filenames |
| Mac client → server API | Device-authenticated reports, curation commands, catalogue state, and byte requests cross an authorization boundary. | Credentials, identifiers, availability and curation data |
| Server storage → Mac cache → emulator work area | Exact bytes move through independently trusted stores; corruption must not become launchable content or mutate canonical cache bytes. | Game and adapter bytes, digests, range responses |
| Emulator process → host Mac | A third-party process receives materialized files and controller input and may write to its working directory. | Processes, game bytes, local paths |
| Build/notary/CI tools → committed evidence | Tool output can contain paths or secrets and must be bound, sanitized, and non-vacuous before it becomes evidence. | Logs, signatures, notarization records, test results |
| Device-reported state → LiveView convenience view | Untrusted device reports may influence presentation but must never become launch authority. | Availability facts and percentages |

---

## Threat Register

### Closed by verified mitigation

| Threat IDs | Status | Evidence |
|---|---|---|
| T-03-01, T-03-02, T-03-03, T-03-04, T-03-05, T-03-06 | closed | Emulator acquisition/quarantine, operator-input minimization, blob authorization, bounded streaming, and range parsing verified in `playstead-mac/spike/scripts/` and `playstead-server/lib/playstead_web/controllers/api/v1/blobs_controller.ex`. |
| T-03-08, T-03-09, T-03-10 | closed | Digest-gated download commit, inode-distinct launch materialization, and live emulator rehash verified in `Playstead/Cache/DownloadEngine.swift`, `LaunchMaterializer.swift`, and `AdapterHost.swift`. |
| T-03-11, T-03-12, T-03-13, T-03-14, T-03-15, T-03-16 | closed | User scoping, curation caps, user-inclusive keys, sanitized/tombstoned display data, scoped LiveView handlers, and escaped HEEx paths verified in server contexts, migrations, and LiveViews. |
| T-03-17, T-03-18, T-03-19, T-03-20, T-03-21, T-03-22, T-03-23 | closed | Transaction-before-cursor ordering, bound SQLite parameters, digest-gated coordination, quota floor, explicit reclaim confirmation, stable idempotency keys, and minimal session records verified in Mac sync/cache/curation sources. |
| T-03-24, T-03-25, T-03-26, T-03-28, T-03-29 | closed | Adapter archive verification, safe BIOS copy/hash, launch preflight, hardened notarized build checks, and bounded process cleanup verified in adapter/readiness sources and release scripts. |
| T-03-11-01, T-03-11-02, T-03-11-03, T-03-11-04, T-03-11-05 | closed | BIOS provenance, production reference, pin parity, stale-temp cleanup, and symlink/path refusal verified against `03-BIOS-PIN.json`, `BiosStore.swift`, tests, and the provenance guard. |
| T-03-12-01, T-03-12-02, T-03-12-05, T-03-12-06 | closed | Signing identity/profile, Gatekeeper source, entitlement/runtime/nested-app constraints, and Keychain-resident signing credentials verified in notarization scripts. |
| T-03-13-01, T-03-13-02, T-03-13-04, T-03-13-05, T-03-13-06, T-03-13-07 | closed | Frozen vocabulary, ownership filtering, 5,000-entry/range limits, transactional replacement, report timestamps, and device-auth/idempotency verified in availability modules, router, and tests. |
| T-03-14-01, T-03-14-04, T-03-14-05, T-03-14-06, T-03-14-07 | closed | Nonthrowing reporter placement, local launch authority, independent grading history, strict UAT tally, and non-vacuous required-test registration verified in app code, scripts, and commits `6eccf32`/`413d4c5`. |
| T-03-15-01, T-03-15-05, T-03-15-06 | closed | Nonthrowing outbox production, shared-fixture/real-endpoint parity, and required-test discovery verified in reporter, e2e test, and verification harness. |
| T-03-16-01, T-03-16-03, T-03-16-05, T-03-16-06, T-03-16-07, T-03-16-08 | closed | Request-shape guard, entry changesets, transactional supersession, exhaustive intent scoping, independent grading, and non-vacuous Mac/server gates verified in controller, outbox, intent, tests, scripts, and commit `413d4c5`. |
| T-03-12-03 | closed | Full mode defines the raw proof only as internal `run_full_proof` (`verify-notarized-release.sh:104-173`) and unconditionally passes it to the sourced capture primitive at line 181. `capture-notarization-evidence.sh:41-105` privately captures, sanitizes, validates, and atomically publishes only sanitized bytes. Legacy and structurally conforming caller-supplied capability variables are inert; executable regressions cover the prior bypasses. |

### Closed by documented acceptance

| Threat ID | Category | Severity | Disposition | Status |
|---|---|---:|---|---|
| T-03-07 | Information Disclosure | low | accept | closed — AR-03-01 |
| T-03-11-06 | Information Disclosure | low | accept | closed — AR-03-02 |
| T-03-11-07 | Denial of Service | low | accept | closed — AR-03-03 |
| T-03-11-SC | Tampering | low | accept | closed — AR-03-04 |
| T-03-12-07 | Denial of Service | low | accept | closed — AR-03-05 |
| T-03-12-SC | Tampering | low | accept | closed — AR-03-06 |
| T-03-13-03 | Spoofing | medium | accept | closed — AR-03-07 |
| T-03-13-SC | Tampering | low | accept | closed — AR-03-08 |
| T-03-14-03 | Tampering | medium | accept | closed — AR-03-09 |
| T-03-14-SC | Tampering | low | accept | closed — AR-03-10 |
| T-03-15-02 | Spoofing | medium | accept | closed — AR-03-11 |
| T-03-15-03 | Tampering | low | accept | closed — AR-03-12 |
| T-03-15-04 | Information Disclosure | low | accept | closed — AR-03-13 |
| T-03-15-07 | Elevation of Privilege | low | accept | closed — AR-03-14 |
| T-03-15-SC | Tampering | low | accept | closed — AR-03-15 |
| T-03-16-02 | Denial of Service | medium | accept | closed — AR-03-16 |
| T-03-16-04 | Tampering | low | accept | closed — AR-03-17 |
| T-03-16-SC | Tampering | low | accept | closed — AR-03-18 |

### Open threats

| Threat ID | Category | Component | Severity | Disposition | Mitigation expected | Status |
|---|---|---|---:|---|---|---|
| T-03-27 | Spoofing | selected emulator installation | medium | mitigate | Digest-compare the selected installation to the pin and mark mismatch unverified. `AdapterInstaller.swift:183-210` does not compare it and persists `verified: true`; the UI only labels provenance as unverified. | open — below high threshold (non-blocking) |
| T-03-12-04 | Repudiation | notarization evidence record | medium | mitigate | Preserve verbatim tool output without handwritten summary. `03-NOTARIZATION-EVIDENCE.md` includes handwritten metadata, interpretation, and assertions outside tool-output blocks. | open — below high threshold (non-blocking) |
| T-03-14-02 | Information Disclosure | availability report body | medium | mitigate | Send only asset-set identifiers and boolean facts. The implemented wire entry also carries `download_percent`. | open — below high threshold (non-blocking) |

*All remaining open threats are below the high blocking threshold, so `threats_open` is zero.*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---|---|---|---|---|
| AR-03-01 | T-03-07 | Object size in a 416 response is already known to a caller that proved ownership. | Phase 03 plan decision | plan-authored |
| AR-03-02 | T-03-11-06 | Publishing a reference digest identifies expected BIOS bytes but distributes no proprietary bytes and supports exact local validation. | Phase 03 plan decision | plan-authored |
| AR-03-03 | T-03-11-07 | Dropped BIOS files are locally selected; existing exact-size validation bounds the supported path and pathological local input is accepted at this severity. | Phase 03 plan decision | plan-authored |
| AR-03-04 | T-03-11-SC | The plan adds no package-manager install or new dependency. | Phase 03 plan decision | plan-authored |
| AR-03-05 | T-03-12-07 | External notary-service availability may delay release but cannot weaken local verification or runtime safety. | Phase 03 plan decision | plan-authored |
| AR-03-06 | T-03-12-SC | The plan adds no package-manager install or new dependency. | Phase 03 plan decision | plan-authored |
| AR-03-07 | T-03-13-03 | Device-reported availability is a convenience view only; local readiness remains launch authority. | Phase 03 plan decision | plan-authored |
| AR-03-08 | T-03-13-SC | The plan adds no package-manager install or new dependency. | Phase 03 plan decision | plan-authored |
| AR-03-09 | T-03-14-03 | Per-device full replacement can temporarily be stale, but reports are timestamped and never become launch authority. | Phase 03 plan decision | plan-authored |
| AR-03-10 | T-03-14-SC | The plan adds no package-manager install or new dependency. | Phase 03 plan decision | plan-authored |
| AR-03-11 | T-03-15-02 | Server availability remains a convenience projection; local state is authoritative for launch. | Phase 03 plan decision | plan-authored |
| AR-03-12 | T-03-15-03 | Existing user/device scope filters are reused rather than duplicated in the reporting layer. | Phase 03 plan decision | plan-authored |
| AR-03-13 | T-03-15-04 | The report exposes bounded readiness facts needed for the private owner console and no paths or content bytes. | Phase 03 plan decision | plan-authored |
| AR-03-14 | T-03-15-07 | Frozen binary membership prevents client strings from creating atoms; no new string-to-atom path exists. | Phase 03 plan decision | plan-authored |
| AR-03-15 | T-03-15-SC | The plan adds no package-manager install or new dependency. | Phase 03 plan decision | plan-authored |
| AR-03-16 | T-03-16-02 | The existing 5,000-entry cap remains the accepted bound; the plan changes request-shape handling, not capacity. | Phase 03 plan decision | plan-authored |
| AR-03-17 | T-03-16-04 | Existing ownership filters remain the enforcement point; the plan introduces no alternate lookup path. | Phase 03 plan decision | plan-authored |
| AR-03-18 | T-03-16-SC | The plan adds no package-manager install or new dependency. | Phase 03 plan decision | plan-authored |

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Blocking Open | Run By |
|---|---:|---:|---:|---:|---|
| 2026-09-19 | 78 | 74 | 4 | 1 | gsd-security-auditor / gsd-secure-phase |
| 2026-09-19 | 78 | 75 | 3 | 0 | gsd-security-auditor / gsd-secure-phase after quick task `260919-eui` |

### Audit notes

- No unregistered implementation flags were found. Summaries 03-13 through 03-16 explicitly report no flags outside their registers; earlier summaries have no `## Threat Flags` section.
- T-03-12-03 was closed after two adversarial audit loops found and removed caller-forgeable re-entry designs. Final commit `6c80db3` uses an internal proof function and unconditional same-process capture, leaving no environment-controlled raw execution branch.
- The three medium open threats remain visible even though `workflow.security_block_on` is `high`.
- Full per-threat source-and-line evidence was returned by the 2026-09-19 auditor; the compact closed rows above preserve the register while the open rows retain exact remediation evidence.

---

## Sign-Off

- [x] All 78 threats have a disposition.
- [x] All 18 plan-authored accepted risks are documented.
- [x] `threats_open: 0` confirmed.
- [x] `status: secured` set in frontmatter.

**Approval:** secured 2026-09-19; three medium non-blocking mitigation gaps remain documented.
