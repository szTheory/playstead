---
id: 261009-uoo
type: quick-full
status: planned
description: Add privacy-safe per-attempt Save E2E failure diagnostics
must_haves:
  truths:
    - A Save E2E failure reports the closed failure classification and HTTP status/API code from the exact drain pass that produced its result.
    - Matching server-route status is available for the same synthetic save request when safely correlatable by the existing live-server fixture.
    - The sanitized CI artifact retains only bounded diagnostic fields, and rejects secret-bearing or unbounded values.
    - Upload retry behavior and the production-facing latest classification contract remain unchanged.
  artifacts:
    - playstead-mac/Playstead/Saves/SaveUploadLane.swift
    - playstead-mac/Playstead/UITesting/UITestBootstrap.swift
    - playstead-mac/Playstead/Net/APIClient.swift
    - playstead-mac/PlaysteadUITests/SaveEndToEndTests.swift
    - playstead-mac/scripts/ci/sanitize-evidence.sh
    - playstead-mac/scripts/ci/tests/sanitizer-test.sh
  key_links:
    - `drainOnce` returns a value carrying that pass's classification and bounded API status/code, and the UI harness uses that value instead of sampling `lastFailureClassification` after an await.
    - The failure-only test evidence writer emits a fixed schema that `sanitize-evidence.sh` validates and copies to the hosted artifact.
    - The live-server fixture's route status is correlated to the synthetic upload attempt without capturing request bodies or user/device credentials.
    - Deterministic tests prove overlapping passes cannot change another pass's diagnostic and prove sanitizer acceptance and rejection boundaries.
---

<objective>
Add per-attempt, privacy-safe diagnostics for the repeated Save E2E upload refusal so the next hosted run distinguishes a real server response from a classification overwritten by another drain pass.

Purpose: PR head `9b084fd7eaa49609c9d0bc3c5415e2c7385634c2` failed hosted Mac run `38012577910` at `SaveEndToEndTests.swift:185`; prior run `38012559750` and main run `38011046324` failed at the same assertion. Sanitized evidence reports `FAILURE_STAGE unavailable` and carries no status, API code, or pass-local classification. Historical duplicate revision 409 and overlapping lane passes both remain plausible.

Output: Bounded failure-only evidence that attributes the drain outcome, closed classification, HTTP status, finite allowlisted API error code (or bounded `other` marker), and safely matched server route status to the exact upload attempt. Preserve the latest-classification behavior consumed by product UI and do not change retries or mask failures.
</objective>

<context>
- Work in the already-isolated clean worktree `/private/tmp/playstead-release-evidence-revalidation`; do not create or switch worktrees.
- Read `.planning/STATE.md`, `AGENTS.md`, `.planning/todos/pending/save-e2e-duplicate-revision-409.md`, `playstead-mac/Playstead/UITesting/UITestBootstrap.swift`, `playstead-mac/Playstead/Saves/SaveUploadLane.swift`, `playstead-mac/Playstead/Net/APIClient.swift`, `playstead-mac/PlaysteadUITests/SaveEndToEndTests.swift`, and `/private/tmp/playstead-phase-051-pr/.planning/debug/save-e2e-upload-server-refused.md` before implementation.
- The current harness checks `lane.lastFailureClassification` after `await lane.drainOnce()`. That cell is intentionally a synchronous latest-value view used by production-facing escalation and must retain its contract.
- APIClient's `APIError` includes status, code, title, and detail. Diagnostics may carry status and a finite allowlist of codes only; cap/validate all scalar and collection sizes and map unknown codes to `other`.
- Test artifacts pass through `playstead-mac/scripts/ci/sanitize-evidence.sh`, which currently accepts only fixed test-evidence keys and checks structured strings for sensitive content. Extend that allowlist narrowly and keep sanitization fail-closed.
- Explicitly exclude response bodies/details/titles, credentials/tokens, local paths, ROM/save metadata, content keys, and arbitrary error descriptions from every serialized diagnostic and log.
- Assumption delta: add per-attempt evidence alongside the existing mutable latest-classification view; do not replace or alter the production-facing latest classification contract. Diagnostic instrumentation only: no external API capability or schema push.
- Security enforcement is enabled at ASVS level 1, with high severity blocking.

## Assumption-Delta Checkpoint

The only assumption shift is to capture diagnostic classification and response metadata in the specific `drainOnce` pass, rather than reading the mutable latest-classification cell afterward. Preserve that cell and its production-facing contract unchanged; this shift affects test attribution only.
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Return a bounded failure snapshot from each save drain pass</name>
  <files>playstead-mac/Playstead/Saves/SaveUploadLane.swift, playstead-mac/Playstead/Net/APIClient.swift, playstead-mac/PlaysteadTests/SyncTests/SaveUploadLaneTests.swift</files>
  <behavior>
    - Each drain result exposes that pass's outcome, closed `SaveUploadFailureClassification`, optional HTTP status, and finite API error code or `other` marker.
    - A later or overlapping pass cannot mutate the already-returned diagnostic value for an earlier pass.
    - Successful and no-pending passes report no failure metadata; production `lastFailureClassification` continues to update and reset as it does today.
    - Diagnostic values never include title, detail, response body, or error descriptions.
  </behavior>
  <action>Define an immutable, Sendable, Equatable per-pass diagnostic/result value in the save upload lane boundary. Capture classification and safe API fields while handling the concrete failure inside that `drainOnce` invocation, before updating/returning to any caller; include the result in the returned value rather than consulting the mutable classification cell later. Keep `lastFailureClassification` and its existing update/reset semantics for production escalation. Extract only the HTTP status and a finite allowlist of API error codes, normalizing all other code strings to a fixed `other` case before they leave APIClient/lane handling. Never copy APIError title/detail or arbitrary `Error` values into the diagnostic. Add deterministic tests using separate controlled passes to prove returned metadata is pass-local, including the overlapping-pass ordering that can otherwise reproduce stale attribution.</action>
  <verify>
    <automated>cd playstead-mac && xcodebuild test -project Playstead.xcodeproj -scheme Playstead -testPlan Unit -destination 'platform=macOS' -only-testing:PlaysteadTests/SaveUploadLaneTests && scripts/ci/run-mac-verification.sh --self-test-contracts</automated>
  </verify>
  <done>The lane returns immutable, bounded per-pass failure metadata and deterministic XCTest coverage proves attribution stays with its originating pass; existing latest-classification semantics and retry decisions are unchanged.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Carry the exact pass diagnostic into Save E2E failure evidence</name>
  <files>playstead-mac/Playstead/UITesting/UITestBootstrap.swift, playstead-mac/PlaysteadUITests/SaveEndToEndTests.swift, playstead-mac/scripts/ci/sanitize-evidence.sh, playstead-mac/scripts/ci/tests/sanitizer-test.sh</files>
  <behavior>
    - The harness bases retry decisions and terminal classification on the corresponding returned pass value, preserving existing behavior while eliminating the post-await shared-cell read for this test.
    - A failure-only artifact has an exact schema containing only drain outcome, closed classification, bounded HTTP status/API code, and a matching server-route status when the fixture can safely correlate it.
    - The sanitizer preserves valid fields and rejects unknown fields, invalid enum/code/status values, oversized values, and attempted secret/path/content-bearing fields without echoing their contents.
    - Existing CI artifact staging carries the sanitized diagnostic while raw response details, credentials/tokens, paths, ROM/save metadata, content keys, and arbitrary descriptions remain excluded.
  </behavior>
  <action>Have `UITestBootstrap` retain the per-pass result for the current attempt and write a diagnostic only when that attempt contributes to a failing Save E2E outcome. Use fixed JSON keys and closed tokens; bound list sizes and integer ranges, and map unsupported API codes to `other`. Where the live-server fixture has a safe request identity already available, record the matching route's status only; do not add server-side logging of payloads or secrets. Wire the diagnostic through `SaveEndToEndTests`' bounded failure path and extend the sanitizer's exact-schema checks and shell fixtures so valid diagnostics survive staging while hostile/unbounded variants fail closed. Do not alter upload retry policy, response handling, assertion success criteria, or product-facing latest classification behavior.</action>
  <verify>
    <automated>cd playstead-mac && scripts/ci/tests/sanitizer-test.sh && scripts/ci/run-mac-verification.sh --self-test-contracts</automated>
  </verify>
  <done>A deterministic overlapping-pass test and sanitizer fixtures demonstrate correct same-attempt attribution, allowlisted status/code/classification preservation, and rejection of secret-bearing or unbounded evidence; hosted sanitized failure evidence can distinguish the two candidate causes without exposing raw data.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Save upload/API response → local test diagnostic | Server error payload and transport errors may contain untrusted private data; only validated status and finite code tokens may cross into evidence. |
| Local test evidence → hosted CI artifact | Generated JSON is an upload boundary; the sanitizer must allow only the explicit bounded diagnostic schema and reject secret/content/path data. |

## STRIDE Threat Register (ASVS level 1; blocking threshold: high)

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-261009-UOO-01 | Information disclosure | Per-attempt diagnostic serialization in `UITestBootstrap.swift` | high | mitigate | Serialize only the closed classification, bounded status, finite API code/`other`, and safely matched route status; tests assert titles, details, response bodies, credentials, paths, content keys, and arbitrary descriptions never enter artifacts. |
| T-261009-UOO-02 | Tampering | `sanitize-evidence.sh` diagnostic schema validation | high | mitigate | Validate exact keys, token enums, integer bounds, and finite code values; deterministic adversarial fixtures prove unknown fields and hostile/unbounded values block artifact creation. |
| T-261009-UOO-03 | Spoofing | Per-pass result attribution in `SaveUploadLane` | medium | mitigate | Capture immutable metadata in the pass handling the failure and test interleaved drains so a later classification update cannot impersonate the failing attempt. |
</threat_model>

<verification>
- Run the deterministic `SaveUploadLaneTests` coverage through the repository's Mac unit-test lane and verify interleaved pass results remain independently attributed.
- Run `cd playstead-mac && scripts/ci/tests/sanitizer-test.sh` and `cd playstead-mac && scripts/ci/run-mac-verification.sh --self-test-contracts`.
- Inspect a synthetic sanitized failure artifact: its status/code/classification and correlated route status identify one attempt; all forbidden data classes are absent.
- Confirm no retry policy, failure branch, API schema, or product-facing `lastFailureClassification` contract changed.
</verification>

<success_criteria>
The next hosted Save E2E failure identifies the exact pass-local classification and safe HTTP/API evidence, plus a safely correlated server route status when available. The artifact sanitizer retains only those bounded fields and rejects secrets, raw/unbounded values, paths, and content metadata. Diagnostic instrumentation preserves the current product classification contract and cannot turn a failing run green.
</success_criteria>

<output>
Create a GSD quick summary at `.planning/quick/261009-uoo-add-privacy-safe-per-attempt-save-e2e-fa/261009-uoo-SUMMARY.md` recording deterministic test and sanitizer results plus the next hosted run's bounded evidence outcome.
</output>
