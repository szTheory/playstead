---
status: diagnosed
trigger: "Replace real proprietary BIOS-byte UAT with a lawful deterministic acceptance seam that proves production wiring and the accept path without shipping or acquiring BIOS bytes."
created: 2026-09-19T15:54:38Z
updated: 2026-09-19T16:22:00Z
---

## Current Focus

hypothesis: CONFIRMED — G-03-13 is caused by an evidence-contract conflation plus a missing narrow composition seam: Test 13 equates proof of the generic accept branch with acceptance of the one proprietary production preimage, while AppEnvironment hardcodes BiosReferences.production and offers UI tests only a candidate-path seam, not a fixed synthetic reference-set seam.
test: completed by code-path tracing, focused execution of 28 BIOS tests, pin-validator positive and negative controls, exhaustive construction-site search, and CI required-test audit
expecting: satisfied — store acceptance and production trust metadata pass separately, but no lawful synthetic input can traverse AppEnvironment -> BiosStore -> BiosDropTarget -> BiosDropTargetView to .accepted
next_action: return diagnosis to the gap-closure planner; do not implement in diagnose-only mode
bug_class: bohrbug
reasoning_checkpoint:
  hypothesis: Test 13 remains blocked because its oracle requires the proprietary production digest preimage and the app composition boundary cannot substitute a fixed synthetic reference for deterministic acceptance testing.
  confirming_evidence:
    - BiosTests accepts synthetic matching bytes through the exact BiosStore validate/copy/persist algorithm, while BiosProductionReferenceTests separately proves pin parity and digest-comparison reachability.
    - AppEnvironment's sole designated initializer constructs BiosStore with BiosReferences.production unconditionally; UITestBootstrap has no reference argument and its packaged-app BIOS journey can only reject synthetic-system.
    - The standalone verify-bios-reference.sh is a second shell implementation fixed to the real pin, not an app-wiring oracle.
  falsification_test: Finding any existing path that supplies a fixed synthetic BiosStore.Reference through the shared AppEnvironment composition initializer and reaches BiosDropTargetView's accepted state would disprove the missing-seam half; exhaustive search found none.
  fix_rationale: Require the shared AppEnvironment initializer to receive a reference set, keep the production convenience path explicitly passing BiosReferences.production, and let only a finite compile-gated UI profile pass one fixed synthetic reference. This changes test data, not validation/storage/UI behavior.
  blind_spots: No new composed seam was implemented or run; the exact UI-profile shape and managed-storage inspection mechanism remain planning decisions.
  candidate_causes:
    - code: AppEnvironment line 519 hardcodes BiosReferences.production and UITestBootstrap cannot supply a lawful synthetic reference
    - data/contract: the UAT oracle binds generic acceptance correctness to possession of bytes matching a proprietary SHA-256 trust anchor
    - environment: CI intentionally has no proprietary BIOS artifact; this is a correct constraint, not a defect
  and_gate: yes — the physical-artifact blocker arises from the fixed proprietary preimage requirement together with the absence of a synthetic reference override at the shared composition boundary

## Symptoms

expected: BIOS acceptance is proven lawfully and deterministically through a production-wiring seam without requiring proprietary BIOS bytes in local development or CI.
actual: The current contract requires a legally-owned physical artifact for phase completion instead of accepting deterministic seam evidence.
errors: None reported.
reproduction: Test 13 in 03-UAT.md.
started: Discovered during UAT.

## Eliminated

- hypothesis: BiosStore has no deterministic accepted-path behavior
  evidence: BiosTests/testAcceptsMatchingLengthAndDigestAndCopiesIntoManagedStorage and testBiosDropTargetAcceptsAMatchingDroppedFile both passed; 25 BiosTests passed overall
  timestamp: 2026-09-19T16:11:00Z

- hypothesis: the production pin is absent, malformed, or disconnected from the Swift literals
  evidence: all 3 BiosProductionReferenceTests passed; the pin provenance guard passed 8 real-pin assertions and rejected all 3 malformed controls
  timestamp: 2026-09-19T16:15:00Z

- hypothesis: verify-bios-reference.sh can serve as the lawful production-wiring seam
  evidence: the script independently reimplements length/SHA-256 checking against a fixed JSON path and never constructs AppEnvironment, BiosStore, BiosDropTarget, or the shipped UI
  timestamp: 2026-09-19T16:18:00Z

- hypothesis: CI already requires a positive packaged-app BIOS acceptance journey
  evidence: the required-test list names BIOS rejection, cancellation, and no-acquisition tests only; no positive composed accept identifier is registered
  timestamp: 2026-09-19T16:18:00Z

## Evidence

- timestamp: 2026-09-19T16:06:00Z
  checked: knowledge base
  found: no prior resolved BIOS or lawful-acceptance pattern exists
  implication: no known-pattern shortcut applies

- timestamp: 2026-09-19T16:06:00Z
  checked: 03-UAT.md Test 13 and 03-BIOS-PIN.json
  found: the UAT marks the exact production-digest accept as blocked on a legally-owned artifact; the pin fixes gba to 16384 bytes and one SHA-256 digest while explicitly declaring no acquisition path
  implication: fabricating bytes for the production digest is neither lawful nor technically available; acceptance evidence must separate pin provenance from behavior proof

- timestamp: 2026-09-19T16:06:00Z
  checked: BiosStore.swift and BiosTests.swift
  found: BiosStore.Reference is caller-supplied and validateAndAccept already has synthetic accepted-path coverage including managed copy, SQLite row, original preservation, idempotency, concurrency, drop-result acceptance, and relaunch durability
  implication: the validation/storage algorithm has a lawful deterministic acceptance seam at the store boundary

- timestamp: 2026-09-19T16:06:00Z
  checked: PlaysteadApp.swift, UITestBootstrap.swift, UITestBiosCandidate.swift, BiosRejectionCopyTests.swift
  found: every AppEnvironment path funnels through one private initializer that unconditionally constructs BiosStore with BiosReferences.production; UI_TESTING can substitute the candidate URL but cannot substitute the reference set, and deterministic profiles use synthetic-system with no production reference
  implication: the real composed UI can prove rejection only; it cannot lawfully traverse .accepted without adding a narrow reference-set seam to the shared composition initializer

- timestamp: 2026-09-19T16:06:00Z
  checked: BiosProductionReferenceTests.swift and bios-pin-provenance-test.sh
  found: production tests independently prove the reference is nonempty/well-formed, equals the JSON pin, reaches digest comparison, and has provenance/no-acquisition validation with negative controls
  implication: production-data fidelity can be proved without executing the accept preimage; it should remain a separate oracle from synthetic behavioral acceptance

- timestamp: 2026-09-19T16:08:00Z
  checked: first focused xcodebuild run
  found: build stopped before test execution because the local project names a placeholder Mac Development team and no matching certificate exists
  implication: this run says nothing about the BIOS hypotheses; retry without code signing

- timestamp: 2026-09-19T16:11:00Z
  checked: focused xcodebuild with code signing disabled
  found: BiosTests executed 25 tests and BiosProductionReferenceTests executed 3 tests; all 28 passed with zero failures, including synthetic accept-and-managed-storage and production pin/parity/digest-rejection coverage
  implication: the algorithmic accept path and the real production trust metadata are each testable today, but only as separate store-level and reference-level evidence

- timestamp: 2026-09-19T16:15:00Z
  checked: bios-pin-provenance-test.sh
  found: the real pin passed 8 assertions; one-provenance, non-hex digest, and missing-pin negative controls each failed as intended
  implication: reference provenance/shape/no-acquisition has an independent fail-closed oracle and does not need BIOS bytes

- timestamp: 2026-09-19T16:15:00Z
  checked: run-mac-verification.sh required BIOS identifiers
  found: CI explicitly requires three unit rejection/no-acquisition tests and two UI rejection/cancel tests, but no production-reference class and no positive composed acceptance journey by identifier
  implication: even though the full unit plan currently discovers store acceptance, CI has no non-vacuous named contract for lawful acceptance through production composition

- timestamp: 2026-09-19T16:15:00Z
  checked: all reference construction sites
  found: BiosStore accepts references at its initializer, but the only shipped AppEnvironment construction line hardcodes BiosReferences.production; UITestBootstrap supplies no reference argument
  implication: the smallest lawful seam is a defaulted reference-set dependency at AppEnvironment's shared designated initializer, with production retaining BiosReferences.production and test profiles supplying one fixed synthetic reference

- timestamp: 2026-09-19T16:18:00Z
  checked: verify-bios-reference.sh and repository-wide BIOS reference search
  found: the operator script is the only other validator; it is pinned directly to 03-BIOS-PIN.json and duplicates the comparison outside the app. No factory, alternate pin, or AppEnvironment reference parameter exists.
  implication: shell success would not prove the shipped composition, and the script cannot be made lawfully positive without either a test-only pin seam or the real artifact

- timestamp: 2026-09-19T16:18:00Z
  checked: BiosRejectionCopyTests
  found: the packaged-app journey already traverses the production readiness route, production BIOS view/control, production BiosStore, and accessibility readout; it intentionally uses synthetic-system, for which production has no reference, so it asserts only rejection
  implication: extending this established journey with a finite synthetic-reference profile is the narrowest front-door proof; no new validator or alternate UI route is needed

## Resolution

root_cause: "Two contributing causes: (1) Test 13's oracle conflates validation-behavior acceptance with possession of bytes matching the proprietary production SHA-256 pin; (2) AppEnvironment hardcodes BiosReferences.production in the shared composition initializer, while the UI harness can inject only a candidate URL, so lawful synthetic bytes cannot exercise the packaged app's accepted branch."
fix: "Not applied (diagnose-only). Recommended seam: make the shared AppEnvironment designated initializer require a BiosStore.Reference array; keep the normal production convenience initializer explicitly passing BiosReferences.production; under #if UI_TESTING, add one finite deterministic BIOS-acceptance profile that passes a fixed synthetic reference and a matching temp candidate through the existing UITestBiosCandidate, readiness route, BiosDropTarget, and status readout. Do not accept arbitrary digests/pins from environment variables. Add named CI-required tests for: production-default reference equality to the JSON-mirrored pin; composed synthetic accept with managed file + bios_files row + original unchanged; packaged UI exact accepted copy; same-length wrong-digest rejection with no residue; N-1/N+1 length rejection; removal/non-forwarding of the seam; and release-binary absence of compile-gated hook tokens. Retain the existing pin malformed/missing negative controls and no-acquisition sweep."
verification: "Diagnosis only. Observed: focused xcodebuild executed 28 BIOS tests (25 BiosTests + 3 BiosProductionReferenceTests), all passed; bios-pin-provenance-test.sh ran 8 assertions and 3 failing negative controls successfully; static search found exactly one AppEnvironment BiosStore construction with hardcoded BiosReferences.production and no alternate reference injection. Evidence boundary: this can prove production pin wiring, generic length+SHA-256 acceptance, managed copy/row persistence, and rendered accept/reject states. It must not claim possession, provenance, legality, or authenticity of any user's BIOS; that real proprietary bytes were accepted in CI; emulator consumption or fidelity equivalence; hardware accuracy; support for an open replacement (03-BIOS-PIN.json explicitly declares none); or a literal drag gesture if automation uses Choose File."
files_changed: []
