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
  tokens: 4545
  tasks: 2
  commits: 4
plan_head_before: c412c8ee94ea7d6df99ac1ee7a123e49f5a84684
tech-stack:
  added: []
  patterns: [private raw capture, sanitizer-owned publication, atomic evidence rename]
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
duration: 5min
completed: 2026-09-19
status: complete
---

# Quick Task 260919-eui: Phase 03 notarization evidence remediation Summary

**Full notarized-release output now crosses the existing sanitizer before an atomic durable publication, with no direct raw transcript path.**

## Accomplishments

- Added a dependency-free capture helper that preserves the wrapped command status, validates the sanitizer manifest, and publishes only sanitized bytes.
- Added `notarization.log` to the existing bounded text sanitizer vocabulary, including secret/path redaction and rejection of empty, oversized, symlinked, non-UTF-8, or control-byte input.
- Made `--evidence-output` mandatory for full release verification before preflight/build/sign/notary tools; `--preflight-only` remains unchanged.
- Documented the sanitized artifact as the only release transcript suitable for review or commit.

## Task Commits

1. `09f4adc` — RED: failing transcript capture and adversarial-output tests.
2. `c3b818e` — GREEN: private capture, sanitizer routing, manifest validation, and atomic publication.
3. `ec73e62` — RED: failing production wiring and early-refusal guards.
4. `52d401c` — GREEN: mandatory full-run capture boundary, binary hardening, and release documentation.

## Verification

- `scripts/ci/tests/notarization-evidence-test.sh` — 22 assertions passed.
- `scripts/ci/tests/notarization-preflight-test.sh` — 7 assertions passed.
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

## Independent Security Follow-up

Implementation is complete, but this summary does **not** declare T-03-12-03 closed. Run `$gsd-secure-phase 03`; only that fresh audit may update `03-SECURITY.md` and determine the threat verdict.

## Self-Check: PASSED

All six planned files exist, all four code commits are present, focused verification is green, and the Phase 03 security report remains untouched.
