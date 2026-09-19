---
quick_id: 260919-eui
phase: quick
plan: 260919-eui
subsystem: release-security
tags: [notarization, evidence, sanitizer, shell, macos]
requires:
  - phase: 03-mac-offline-play-vertical-slice
    provides: notarized release proof and evidence sanitizer
provides:
  - fail-closed notarization transcript capture through the existing evidence sanitizer
  - mandatory sanitized evidence destination for full release verification
affects: [phase-03-security, release-verification]
actuals:
  tokens: 5937
  tasks: 2
  commits: 7
plan_head_before: c412c8ee94ea7d6df99ac1ee7a123e49f5a84684
tech-stack:
  added: []
  patterns: [private raw capture, authenticated capture capability, sanitizer-owned publication, atomic evidence rename]
key-files:
  created:
    - playstead-mac/scripts/ci/capture-notarization-evidence.sh
    - playstead-mac/scripts/ci/tests/notarization-evidence-test.sh
  modified:
    - playstead-mac/scripts/ci/sanitize-evidence.sh
    - playstead-mac/scripts/verify-notarized-release.sh
    - playstead-mac/scripts/ci/tests/notarization-preflight-test.sh
    - playstead-mac/docs/RELEASE.md
key-decisions:
  - "Raw release output exists only under a mode-0700 temporary root and reaches durable storage only after sanitizer validation."
  - "Preflight-only remains credential-testable without an evidence destination; every full run requires --evidence-output before external tools execute."
  - "Release-body re-entry requires a random helper-issued token bound to a mode-0700 helper root and mode-0600 capability file; legacy or forged caller markers fail before external tools."
requirements-completed: []
coverage:
  - id: D1
    description: Notarization transcripts are sanitized and atomically published without a raw-output bypass.
    verification:
      - kind: integration
        ref: playstead-mac/scripts/ci/tests/notarization-evidence-test.sh
        status: pass
    human_judgment: false
  - id: D2
    description: Full release verification refuses missing evidence before external tools while preflight-only remains compatible.
    verification:
      - kind: integration
        ref: playstead-mac/scripts/ci/tests/notarization-preflight-test.sh
        status: pass
    human_judgment: false
duration: 10min
completed: 2026-09-19
status: complete
---

# Quick Task 260919-eui: Phase 03 notarization evidence remediation Summary

**Full notarized-release output now crosses the existing sanitizer before an atomic durable publication, with no direct raw transcript path.**

## Accomplishments

- Added a dependency-free capture helper that preserves the wrapped command status, validates the sanitizer manifest, and publishes only sanitized bytes.
- Added `notarization.log` to the existing bounded text sanitizer vocabulary, including secret/path redaction and rejection of empty, oversized, symlinked, non-UTF-8, or control-byte input.
- Made `--evidence-output` mandatory for full release verification before preflight/build/sign/notary tools; `--preflight-only` remains unchanged.
- Replaced the caller-controlled recursion sentinel with a random helper-issued capability validated against its private root, ownership, modes, token, and capture layout.
- Documented the sanitized artifact as the only release transcript suitable for review or commit.

## Task Commits

1. `09f4adc` — RED: failing transcript capture and adversarial-output tests.
2. `c3b818e` — GREEN: private capture, sanitizer routing, manifest validation, and atomic publication.
3. `ec73e62` — RED: failing production wiring and early-refusal guards.
4. `52d401c` — GREEN: mandatory full-run capture boundary, binary hardening, and release documentation.
5. `fbb9ce0` — RED: executable regression proving `/etc/hosts` bypassed the old sentinel guard.
6. `8fd6f79` — GREEN: authenticated helper capability and fail-closed legacy/forged-input rejection.

Prior plan metadata commit: `483e813`.

## Verification

- `scripts/ci/tests/notarization-evidence-test.sh` — 23 assertions passed.
- `scripts/ci/tests/notarization-preflight-test.sh` — 14 assertions passed, including forged legacy and replacement capabilities.
- `scripts/ci/tests/sanitizer-test.sh` — 35 positive/negative checks passed.
- `bash -n` passed for the release verifier, capture helper, and sanitizer.
- `03-SECURITY.md` has no executor-owned diff.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Rejected UTF-8 control-byte transcripts**

- **Found during:** Task 2 adversarial regression expansion.
- **Issue:** Invalid UTF-8 failed closed, but a NUL-bearing transcript remained technically decodable and could pass as text.
- **Fix:** The shared log sanitizer now rejects binary control bytes while retaining newline, carriage return, and tab.
- **Verification:** The capture test observes the NUL-bearing producer fail without leaving a destination; the existing sanitizer suite remains green.
- **Committed in:** `52d401c`.

**2. [Rule 1 - Security Bug] Removed caller-controlled release-body bypass**

- **Found during:** Independent `$gsd-secure-phase 03` re-audit after the initial implementation.
- **Issue:** `PLAYSTEAD_EVIDENCE_CAPTURE_ACTIVE=/etc/hosts` satisfied the regular-file check, skipped the capture helper, and reached external preflight/body execution.
- **Fix:** The helper now creates a random 256-bit token in its private mode-0700 root and passes the matching mode-0600 capability only to its child. The verifier validates token format and binding, file/root types, modes, ownership, private-root layout, and then unsets both values before external tools. The legacy sentinel is rejected outright.
- **Verification:** Both `/etc/hosts` as the legacy sentinel and `/etc/hosts` plus a forged replacement token fail with `INVALID_EVIDENCE_CAPTURE_CAPABILITY` before tool invocation or evidence publication.
- **Committed in:** `fbb9ce0` (RED), `8fd6f79` (GREEN).

## Independent Security Follow-up

Implementation is complete, but this summary does **not** declare T-03-12-03 closed. Run `$gsd-secure-phase 03`; only that fresh audit may update `03-SECURITY.md` and determine the threat verdict.

## Self-Check: PASSED

All six planned files exist, all six code commits plus the prior metadata commit are present, focused verification is green, and the Phase 03 security report remains untouched.
