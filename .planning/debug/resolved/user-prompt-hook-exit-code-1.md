---
status: resolved
trigger: "can u fix this first? keeps happening from above • UserPromptSubmit hook (failed) error: hook exited with code 1"
created: 2026-08-31T16:21:21-04:00
updated: 2026-08-31T16:55:00-04:00
---

## Current Focus
<!-- OVERWRITE on each update - reflects NOW -->

bug_class: bohrbug
reasoning_checkpoint:
  hypothesis: "@opengsd/gsd-core 1.12.0's Codex installer copies gsd-context-monitor.js but omits its hooks/lib dependency closure, so Node throws MODULE_NOT_FOUND before the advisory hook can fail open."
  confirming_evidence:
    - "The literal configured command deterministically exits 1 at gsd-context-monitor.js:25 with MODULE_NOT_FOUND for ./lib/hook-exit.js."
    - "The 1.12.0 installer explicitly copies gsd-context-monitor.js for Codex while stating that hooks/lib is deliberately not copied."
    - "The packaged dependency closure is exactly hook-exit.js -> cli-exit.js -> exit-code-registry.js, and the installed monitor differs from packaged 1.12.0 only by expected installer substitutions."
  falsification_test: "After staging the exact three packaged helpers, the hypothesis is false if the unchanged configured hook still exits nonzero or reports a different missing local module."
  fix_rationale: "Installing the exact omitted dependency closure restores the package's intended module graph without changing hook registration or advisory behavior."
  blind_spots: "A future GSD reinstall using the same 1.12.0 installer can omit the helpers again; this local repair cannot correct the upstream installer package itself."
  candidate_causes:
    - "code: the Codex installer allowlist stages a hook whose new local dependency bundle it explicitly skips."
    - "environment: the configured Node binary might be missing or incompatible, but it executed successfully and produced a normal CommonJS resolution stack."
    - "data: malformed hook JSON might crash parsing, but module loading fails before stdin is parsed and the same result occurs with valid representative JSON."
  and_gate: "no — the absent dependency closure alone is sufficient to reproduce the failure for every input; runtime and input candidates were directly ruled out."
verification_state: "Guardrail accepted: original command and adjacent cases exit 0; 20/20 stability runs pass; controlled removal restores the exact exit-1 failure and replacement fixes it."
human_verification: "passed — the user submitted the normal prompt 'replying here' and the Codex UI reported no UserPromptSubmit hook failure."
next_action: Archive this resolved session, append its prevention summary to the debug knowledge base, and commit the planning artifacts.

## Symptoms
<!-- Written during gathering, then IMMUTABLE -->

expected: Submitting a prompt runs the advisory GSD context monitor successfully without displaying a hook failure.
actual: Every prompt submission displays a UserPromptSubmit hook failure.
errors: "UserPromptSubmit hook (failed)\nerror: hook exited with code 1"
reproduction: Submit a user prompt while the configured ~/.codex/hooks.json UserPromptSubmit hook is enabled.
started: Recurrent in the current Codex session; exact first occurrence is unknown.

## Eliminated
<!-- APPEND only - prevents re-investigating -->

- hypothesis: The configured Node runtime is absent or incompatible.
  evidence: The configured Node 24.19.0 binary ran and emitted a standard CommonJS MODULE_NOT_FOUND stack from inside the hook.
  timestamp: 2026-08-31T16:42:00-04:00

- hypothesis: A malformed UserPromptSubmit payload causes the hook to exit 1.
  evidence: Node fails at top-level require before stdin parsing, including with valid representative JSON.
  timestamp: 2026-08-31T16:42:00-04:00

## Evidence
<!-- APPEND only - facts discovered -->

- timestamp: 2026-08-31T16:21:21-04:00
  checked: ~/.codex/hooks.json UserPromptSubmit registration
  found: The event invokes Node 24.19.0 with ~/.codex/hooks/gsd-context-monitor.js.
  implication: The failing command and runtime are identified precisely.

- timestamp: 2026-08-31T16:21:21-04:00
  checked: gsd-context-monitor.js top-level imports and ~/.codex/hooks filesystem
  found: The script requires ./lib/hook-exit.js, but ~/.codex/hooks/lib does not exist.
  implication: Node will exit before the hook's try/catch or fail-open crash policy can execute.

- timestamp: 2026-08-31T16:25:00-04:00
  checked: Initial reproduction wrapper using jq plus awk to split the configured command
  found: The wrapper preserved literal quote characters around the Node path and exited 127 before invoking Node.
  implication: This test is inconclusive and must be rerun using shell parsing of the literal configured command.

- timestamp: 2026-08-31T16:27:00-04:00
  checked: Literal configured UserPromptSubmit command invoked via zsh with representative JSON
  found: Node 24.19.0 exits 1 with MODULE_NOT_FOUND for ./lib/hook-exit.js at gsd-context-monitor.js line 25.
  implication: The missing local helper directly and deterministically causes the reported hook failure before runtime error handling begins.

- timestamp: 2026-08-31T16:30:00-04:00
  checked: Installed context monitor dependency graph and local/cached GSD package trees
  found: gsd-context-monitor.js has exactly one relative require, ./lib/hook-exit.js; the installed ~/.codex/hooks tree lacks it, while the cached @opengsd/gsd-core package contains hooks/lib/hook-exit.js.
  implication: The likely minimal repair is one helper file, subject to confirming version/hash compatibility and no nested local dependency.

- timestamp: 2026-08-31T16:33:00-04:00
  checked: Installed monitor hash/version and cached @opengsd/gsd-core 1.12.0 hook helper
  found: Both monitors declare 1.12.0 but their SHA-256 hashes differ; packaged hook-exit.js imports a second local helper, ./cli-exit.js.
  implication: Copying only hook-exit.js would move the failure one import deeper; compatibility and the full two-file closure must be verified before repair.

- timestamp: 2026-08-31T16:37:00-04:00
  checked: Diff of installed monitor versus packaged 1.12.0 source and complete local import closure
  found: Monitor code differs only by expected installer substitutions (1.12.0 version stamp and .codex path comment); its helper chain is hook-exit.js to cli-exit.js to exit-code-registry.js, with no further local import.
  implication: Those three package-matched helper files are API-compatible with the installed hook and constitute its minimal dependency closure.

- timestamp: 2026-08-31T16:41:00-04:00
  checked: @opengsd/gsd-core 1.12.0 Codex installation branch and debug knowledge base
  found: The installer allowlist includes gsd-context-monitor.js but explicitly does not copy hooks/lib for Codex; no project debug knowledge base exists with an earlier resolution.
  implication: The package installer created an internally incomplete Codex hook installation; this is a deterministic Bohrbug and the omitted dependency closure is the root cause.

- timestamp: 2026-08-31T16:45:00-04:00
  checked: Installed repair artifact hashes
  found: ~/.codex/hooks/lib now contains hook-exit.js, cli-exit.js, and exit-code-registry.js with SHA-256 hashes identical to the cached @opengsd/gsd-core 1.12.0 package.
  implication: The installed repair is the exact compatible dependency closure, not a locally reimplemented substitute.

- timestamp: 2026-08-31T16:49:00-04:00
  checked: Exact configured command, fail-open edge cases, 20-run stability loop, syntax checks, and controlled removal/restoration
  found: Original command exits 0 with empty stderr/stdout; malformed JSON, traversal session ID, and absent metrics all exit 0; 20 of 20 runs pass; all helpers parse; removing lib restores exit 1 and replacing it restores exit 0.
  implication: The repair directly fixes the original failure, preserves adjacent advisory fail-open behavior, is stable, and satisfies revert-and-reconfirm.

- timestamp: 2026-08-31T16:55:00-04:00
  checked: Human verification through the normal Codex UserPromptSubmit UI path
  found: The user submitted "replying here" and no UserPromptSubmit hook failure was reported.
  implication: The repaired dependency closure works end-to-end in the real workflow, so the session can be resolved and archived.

## Resolution
<!-- OVERWRITE as understanding evolves -->

root_cause: "@opengsd/gsd-core 1.12.0's Codex installer stages gsd-context-monitor.js but explicitly omits hooks/lib, leaving its required three-file local dependency closure absent."
fix: "Installed the exact three-file 1.12.0 dependency closure under ~/.codex/hooks/lib: hook-exit.js, cli-exit.js, and exit-code-registry.js."
oracle_type: specified
verification:
  target_test:
    result: pass
    evidence: "Literal configured UserPromptSubmit command exits 0 with no stderr or stdout."
  mutation_check:
    result: skipped
    reason_if_skipped: "No Stryker configuration applies to installed external hook artifacts; exact package hashes plus revert-and-reconfirm provide the applicable signals."
    mutant_killed: false
  no_op_deletion:
    result: pass
    deletion_justified_by_rca: false
    evidence: "Repair is additive and restores required packaged modules; no behavior was deleted or short-circuited."
  adjacent_tests:
    result: pass
    suites_run:
      - "malformed JSON fail-open"
      - "path-traversal session ID fail-open"
      - "missing metrics silent exit"
      - "Node syntax checks for all three helpers"
      - "20-run stability loop"
  revert_and_reconfirm:
    result: pass
    bug_returned_on_revert: true
    fixed_on_reapply: true
  guardrail_verdict: accepted
  human_ui_path:
    result: pass
    evidence: "The normal prompt 'replying here' submitted without a UserPromptSubmit hook failure."
files_changed:
  - /Users/jon/.codex/hooks/lib/hook-exit.js
  - /Users/jon/.codex/hooks/lib/cli-exit.js
  - /Users/jon/.codex/hooks/lib/exit-code-registry.js

## Prevention

causal_branches:
  code:
    - "gsd-context-monitor.js acquired a local dependency on hooks/lib/hook-exit.js."
    - "The Codex installer copied the monitor through a file allowlist but explicitly skipped hooks/lib, so the installed module graph was incomplete."
    - "Node resolves top-level CommonJS imports before the hook's fail-open handler can run, turning the packaging omission into an exit-code-1 failure on every prompt."
  config_environment:
    - "The configured hooks.json command correctly selected Node 24.19.0 and the installed monitor, so runtime selection did not cause the failure."
    - "Valid and malformed payloads failed at the same pre-parse import step, ruling input data out as a contributing condition."
  and_gate: "No: the installer omission was sufficient by itself; runtime configuration and prompt data were independently ruled out."
why_not_caught: "No Codex installer integration gate existed in @opengsd/gsd-core 1.12.0 to launch every installed hook in a clean destination and verify that its complete relative-import closure was staged."
recurrence_guard: "The resolved-session pattern in .planning/debug/knowledge-base.md records the exact missing hooks/lib closure, the three-file repair, and the reinstall risk so a future Phase-0 debug recall tests this cause first."
