---
quick_id: 260919-eui
phase: quick
plan: 260919-eui
type: execute
status: planned
date: 2026-09-19
wave: 1
depends_on: []
autonomous: true
files_modified:
  - playstead-mac/scripts/ci/sanitize-evidence.sh
  - playstead-mac/scripts/ci/capture-notarization-evidence.sh
  - playstead-mac/scripts/ci/tests/notarization-evidence-test.sh
  - playstead-mac/scripts/verify-notarized-release.sh
  - playstead-mac/scripts/ci/tests/notarization-preflight-test.sh
  - playstead-mac/docs/RELEASE.md
estimate:
  tokens: 30000
  raw_tokens: 30000
  tasks: 2
  confidence: low
must_haves:
  truths:
    - "A full notarized-release proof cannot write its evidence destination directly: the command output is captured in a private temporary root, passed through scripts/ci/sanitize-evidence.sh, and only the sanitizer result is atomically installed at the requested destination."
    - "Notarization transcripts redact secret-bearing lines and local paths, while empty, oversized, symlinked, binary/non-UTF-8, or otherwise malformed transcript evidence is rejected."
    - "The notarization preflight remains usable without Apple credentials in tests, and the full release path refuses to start unless an explicit evidence destination is supplied."
    - "Phase 03 security status is changed only by a fresh gsd-secure-phase audit after implementation; the executor does not edit 03-SECURITY.md or declare T-03-12-03 closed."
  artifacts:
    - playstead-mac/scripts/ci/capture-notarization-evidence.sh
    - playstead-mac/scripts/ci/tests/notarization-evidence-test.sh
    - playstead-mac/scripts/verify-notarized-release.sh
  key_links:
    - "verify-notarized-release.sh full-run entry -> capture-notarization-evidence.sh -> sanitize-evidence.sh -> atomic evidence destination"
    - "notarization-evidence-test.sh -> real capture helper and sanitizer, plus a production-wiring guard on verify-notarized-release.sh"
---

# Quick Task 260919-eui: Close the Phase 03 notarization-evidence disclosure path

<objective>
Close the implementation gap behind Phase 03 threat T-03-12-03 by making sanitized evidence capture an unavoidable part of the full notarized-release command.

Purpose: notarization, signing, Gatekeeper, XCTest, and launch output can contain credentials, hashes, or local paths. A release proof must never reach its durable evidence destination before the repository sanitizer has processed and validated it.

Output: a fail-closed notarization transcript capture helper, production wiring in the release verifier, and regression tests for routing, redaction, rejection, and preflight compatibility.

This quick task does not rewrite historical evidence or security conclusions. After execution, the orchestrator reruns `$gsd-secure-phase 03`; that audit alone decides whether T-03-12-03 closes and updates `03-SECURITY.md`.
</objective>

<execution_context>
@/Users/jon/.codex/gsd-core/workflows/execute-plan.md
@/Users/jon/.codex/gsd-core/templates/summary.md
</execution_context>

<context>
@AGENTS.md
@.planning/STATE.md
@.planning/phases/03-mac-offline-play-vertical-slice/03-SECURITY.md
@.planning/phases/03-mac-offline-play-vertical-slice/03-12-PLAN.md
@.planning/phases/03-mac-offline-play-vertical-slice/03-12-SUMMARY.md
@playstead-mac/scripts/ci/sanitize-evidence.sh
@playstead-mac/scripts/ci/tests/sanitizer-test.sh
@playstead-mac/scripts/verify-notarized-release.sh
@playstead-mac/scripts/ci/tests/notarization-preflight-test.sh
</context>

<tasks>

<task type="tracer" tdd="true">
  <name>Task 1: Carry one synthetic notarization transcript through the real sanitizer to a durable artifact</name>
  <files>playstead-mac/scripts/ci/sanitize-evidence.sh, playstead-mac/scripts/ci/capture-notarization-evidence.sh, playstead-mac/scripts/ci/tests/notarization-evidence-test.sh</files>
  <behavior>
    - A synthetic command that emits ordinary notarization markers, an absolute macOS path, and a secret-bearing line produces one non-empty durable transcript: ordinary lines survive, the path becomes `[PATH]`, and the sensitive line becomes `[REDACTED SECRET-BEARING LINE]`.
    - The capture helper preserves the wrapped command's exit status while still sanitizing its diagnostic transcript; it never copies or tees the raw temporary transcript to the requested evidence path.
    - Empty, oversized, symlinked, binary/non-UTF-8, and unsafe output-target cases fail non-zero and do not leave a partially written destination.
    - The existing directory-shaped CI evidence contract and sanitizer regression suite continue to pass unchanged.
  </behavior>
  <action>Write `notarization-evidence-test.sh` first and observe it fail. Extend `sanitize-evidence.sh` narrowly so `evidence/notarization.log` is an allowlisted text artifact governed by the existing 256 KiB text bound, symlink refusal, `sanitize_log`, post-sanitization scan, and manifest generation; do not create a second sanitizer vocabulary. Add `capture-notarization-evidence.sh` as the sole writer for release transcripts: require an explicit safe output file plus a command after `--`, create a mode-0700 temporary root containing `evidence/notarization.log`, capture the wrapped command's combined stdout/stderr there, invoke `sanitize-evidence.sh`, validate that the sanitized transcript and manifest exist, then atomically rename a sibling temporary file into the requested destination. Preserve the wrapped status after sanitization, clean all raw/staging material with an EXIT trap, reject symlink destinations and unsafe root/empty targets, and never print raw transcript contents from the helper. Keep this helper dependency-free and executable.</action>
  <verify>
    <automated>cd playstead-mac &amp;&amp; scripts/ci/tests/notarization-evidence-test.sh &amp;&amp; scripts/ci/tests/sanitizer-test.sh &amp;&amp; bash -n scripts/ci/capture-notarization-evidence.sh scripts/ci/sanitize-evidence.sh</automated>
  </verify>
  <done>A real synthetic producer reaches a durable sanitized transcript only through the shipped sanitizer, all adversarial evidence cases are covered, and the established CI sanitizer contract remains green.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Make sanitized capture mandatory for the production notarized-release proof</name>
  <files>playstead-mac/scripts/verify-notarized-release.sh, playstead-mac/scripts/ci/tests/notarization-preflight-test.sh, playstead-mac/scripts/ci/tests/notarization-evidence-test.sh, playstead-mac/docs/RELEASE.md</files>
  <behavior>
    - `--preflight-only` retains its current two-direction behavior and does not require or create an evidence file.
    - A non-preflight invocation without `--evidence-output PATH` exits before build/sign/notary work with a distinct bounded failure token.
    - A non-preflight invocation with `--evidence-output PATH` re-enters the existing proof exactly once under `capture-notarization-evidence.sh`; the nested `sign-and-notarize.sh` output and every later stapler, Gatekeeper, XCTest, launch, exit, and relaunch line share that capture boundary.
    - The production script contains no direct write, append, copy, move, or tee from raw command output to the requested evidence destination.
  </behavior>
  <action>Extend argument parsing in `verify-notarized-release.sh` with `--evidence-output PATH`, preserving `--preflight-only`. Before any full-run build work, require the evidence path and dispatch the existing proof body through `capture-notarization-evidence.sh`; use a private recursion/capture sentinel so the body runs once and the public invocation returns the helper's status. Keep preflight outside this requirement so its existing credential stubs remain fast. Expand `notarization-evidence-test.sh` with a production-wiring regression that fails if the verifier ceases to invoke the capture helper or gains a direct raw-to-destination write path, and extend `notarization-preflight-test.sh` to prove full mode refuses a missing evidence destination before touching external tools. Update `docs/RELEASE.md` so the canonical full command supplies an operator-chosen evidence destination and states that only the sanitized artifact is reviewable/committable. Do not edit `.planning/phases/03-mac-offline-play-vertical-slice/03-SECURITY.md`, do not mark the threat closed, and do not rerun real Apple notarization merely to manufacture new historical evidence.</action>
  <verify>
    <automated>cd playstead-mac &amp;&amp; scripts/ci/tests/notarization-evidence-test.sh &amp;&amp; scripts/ci/tests/notarization-preflight-test.sh &amp;&amp; scripts/ci/tests/sanitizer-test.sh &amp;&amp; bash -n scripts/verify-notarized-release.sh scripts/ci/capture-notarization-evidence.sh scripts/ci/sanitize-evidence.sh</automated>
  </verify>
  <done>The documented full release command cannot begin without a sanitizer-owned evidence destination, every output-producing stage sits inside that boundary, and preflight plus all sanitizer regressions pass.</done>
</task>

</tasks>

<threat_model>
ASVS enforcement level: 1. Blocking severity: high.

## Trust Boundaries

| Boundary | Description |
|---|---|
| Apple/build/test tools -> temporary raw transcript | Untrusted tool output may contain local paths, credentials, content identifiers, hashes, or malformed bytes. |
| Temporary raw transcript -> sanitizer | Only the fixed `evidence/notarization.log` input is eligible; size, type, symlink, encoding, redaction, and post-scan checks fail closed. |
| Sanitizer staging -> durable evidence destination | The destination is installed atomically from sanitized output and must never receive raw bytes. |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|---|---|---|---|---|---|
| T-03-12-03 | Information Disclosure | notarization evidence output | high | mitigate | Make `capture-notarization-evidence.sh` invoke `sanitize-evidence.sh` before atomic publication, require that path from every full `verify-notarized-release.sh` run, and regression-test redaction plus absence of a raw-output bypass. |
| T-Q-EUI-01 | Tampering | temporary/staged evidence paths | high | mitigate | Private temporary root, symlink refusal, safe-target validation, sanitizer manifest validation, sibling atomic rename, and unconditional cleanup. |
| T-Q-EUI-02 | Repudiation | release proof exit/result | medium | mitigate | Preserve the wrapped command status and transcript, require a non-empty sanitized artifact, and test success and failure producers independently. |
| T-Q-EUI-03 | Denial of Service | transcript capture | medium | mitigate | Reuse the sanitizer's fixed 256 KiB text-file and total-size bounds and reject oversized evidence. |
| T-Q-EUI-SC | Tampering | package supply chain | low | accept | No package-manager install and no new dependency are introduced. |
</threat_model>

<verification>
1. Run `cd playstead-mac && scripts/ci/tests/notarization-evidence-test.sh`; confirm its positive, redaction, rejection, status-preservation, and production-wiring assertions are non-vacuous.
2. Run `cd playstead-mac && scripts/ci/tests/notarization-preflight-test.sh`; confirm the original four assertions pass and the missing-evidence full-run refusal happens before external tooling.
3. Run `cd playstead-mac && scripts/ci/tests/sanitizer-test.sh`; confirm the existing sanitizer surface remains green.
4. Confirm `git diff -- .planning/phases/03-mac-offline-play-vertical-slice/03-SECURITY.md` is empty. Security closure is not an executor-owned edit.
</verification>

<orchestrator_follow_up>
After the executor commits code and writes the quick-task SUMMARY, invoke `$gsd-secure-phase 03` as a separate GSD workflow. The security auditor must inspect the implementation and tests, then update `03-SECURITY.md` itself. If it does not close T-03-12-03, report the auditor's exact remaining evidence requirement instead of altering the verdict manually.
</orchestrator_follow_up>

<source_coverage>

| Source | Item | Coverage |
|---|---|---|
| GOAL | Route notarization output through `sanitize-evidence.sh` | Tasks 1-2 wire synthetic and production paths end to end. |
| GOAL | Test the fix | Both tasks provide automated positive/negative regression commands. |
| GOAL | Rerun Phase 03 secure-phase | Reserved explicitly for the orchestrator follow-up; executor cannot self-certify. |
| SECURITY | T-03-12-03 high blocker | Task 2 makes the registered mitigation mandatory. |
| CONTEXT | No quick-task CONTEXT.md exists | No locked or deferred decisions to omit. |
| RESEARCH | No research phase requested | Live scripts and tests are the implementation authority. |

</source_coverage>

<success_criteria>
- The full notarized-release verifier has one mandatory sanitizer-owned evidence path and no direct raw-output publication path.
- Sensitive/local-path transcript data is redacted; malformed, unsafe, or unbounded evidence is rejected without a partial destination.
- All three focused shell test suites and shell syntax checks pass.
- `03-SECURITY.md` remains untouched until `$gsd-secure-phase 03` produces a fresh audit verdict.
</success_criteria>

<output>
Create `.planning/quick/260919-eui-fix-phase-03-security-blocker-t-03-12-03/260919-eui-SUMMARY.md` with `status: complete` after implementation. Record the code commit(s), test results, and the required `$gsd-secure-phase 03` follow-up without claiming the threat is closed before that audit.
</output>
