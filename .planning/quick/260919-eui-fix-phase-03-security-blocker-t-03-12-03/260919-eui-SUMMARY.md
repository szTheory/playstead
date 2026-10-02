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
  tokens: 5640
  tasks: 2
  commits: 10
plan_head_before: c412c8ee94ea7d6df99ac1ee7a123e49f5a84684
tech-stack:
  added: []
  patterns: [private raw capture, sourced capture primitive, internal proof function, sanitizer-owned publication, atomic evidence rename]
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
  - "The full release proof is an internal function passed unconditionally to a sourced capture primitive; no recursion, environment marker, capability file, or separately callable raw body exists."
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
duration: 15min
completed: 2026-09-19
status: complete
---

# Quick Task 260919-eui: Phase 03 notarization evidence remediation Summary

**Full notarized-release output now crosses the existing sanitizer before an atomic durable publication, with no direct raw transcript path.**

## Accomplishments

- Added a dependency-free capture helper that preserves the wrapped command status, validates the sanitizer manifest, and publishes only sanitized bytes.
- Added `notarization.log` to the existing bounded text sanitizer vocabulary, including secret/path redaction and rejection of empty, oversized, symlinked, non-UTF-8, or control-byte input.
- Made `--evidence-output` mandatory for full release verification before preflight/build/sign/notary tools; `--preflight-only` remains unchanged.
- Removed release-script recursion entirely: full proof work is an internal function unconditionally passed to a sourced sanitizer capture primitive.
- Documented the sanitized artifact as the only release transcript suitable for review or commit.

## Task Commits

1. `09f4adc` — RED: failing transcript capture and adversarial-output tests.
2. `c3b818e` — GREEN: private capture, sanitizer routing, manifest validation, and atomic publication.
3. `ec73e62` — RED: failing production wiring and early-refusal guards.
4. `52d401c` — GREEN: mandatory full-run capture boundary, binary hardening, and release documentation.
5. `fbb9ce0` — RED: executable regression proving `/etc/hosts` bypassed the old sentinel guard.
6. `8fd6f79` — GREEN: authenticated helper capability and fail-closed legacy/forged-input rejection.
7. `dd23918` — RED: same-UID structural forgery proving the replacement capability remained bypassable.
8. `6c80db3` — GREEN: non-reentrant internal proof function and unconditional sourced capture.

Prior plan metadata commits: `483e813`, `fae56bd`.

## Verification

- `scripts/ci/tests/notarization-evidence-test.sh` — 23 assertions passed.
- `scripts/ci/tests/notarization-preflight-test.sh` — 11 assertions passed, including a structurally conforming same-UID capability forgery that remains inside capture.
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

**2. [Rule 1 - Security Bug] Identified caller-controlled release-body bypass**

- **Found during:** Independent `$gsd-secure-phase 03` re-audit after the initial implementation.
- **Issue:** `PLAYSTEAD_EVIDENCE_CAPTURE_ACTIVE=/etc/hosts` satisfied the regular-file check, skipped the capture helper, and reached external preflight/body execution.
- **Initial fix:** A random helper token replaced the plain regular-file marker and closed the trivial `/etc/hosts` form, but the second audit correctly proved that a same-UID caller could reproduce the complete file/token/layout contract. This intermediate design was superseded rather than treated as closure.
- **Verification:** The second RED regression created the exact mode-0700 root, mode-0600 file, matching 64-hex token, ownership, and raw/evidence layout and observed preflight outside capture.
- **Committed in:** `fbb9ce0` (RED), `8fd6f79` (GREEN).

**3. [Rule 1 - Security Bug] Removed the forgeable re-entry design class**

- **Found during:** Second independent `$gsd-secure-phase 03` re-audit.
- **Issue:** Any environment/filesystem recursion credential validated by the same UID remained caller-forgeable; strengthening token validation could not establish provenance.
- **Fix:** Removed re-entry and all `PLAYSTEAD_EVIDENCE_CAPTURE_*` handling. `verify-notarized-release.sh` now defines `run_full_proof` internally, sources the capture primitive, and unconditionally captures that function once. The helper isolates function failure in a subshell so sanitization and atomic publication still occur without exposing a raw proof entry point.
- **Verification:** Executable source guards reject capture environment branches or `$0` recursion. The structurally conforming forgery is inert: external preflight runs, its diagnostics appear only in the sanitized evidence destination, and nothing leaks to the caller log.
- **Committed in:** `dd23918` (RED), `6c80db3` (GREEN).

## Independent Security Follow-up

Implementation is complete, but this summary does **not** declare T-03-12-03 closed. Run `$gsd-secure-phase 03`; only that fresh audit may update `03-SECURITY.md` and determine the threat verdict.

## Self-Check: PASSED

All six planned files exist, all eight code commits plus two prior metadata commits are present, focused verification is green, and the Phase 03 security report remains untouched.
