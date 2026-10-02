---
quick_id: 261002-hwa
phase: quick
plan: 261002-hwa
type: execute
status: planned
date: 2026-10-02
wave: 1
depends_on: []
autonomous: true
files_modified:
  - .planning/PROJECT.md
  - .planning/seeds/SEED-034-shift-manual-uat-clauses-left-into-ci.md
  - .planning/seeds/SEED-035-first-party-core-host-and-pair-pinning.md
  - .planning/STATE.md
  - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-VERIFICATION.md
  - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-HOSTED-EVIDENCE.md
  - scripts/check-tracked-text-hygiene.sh
  - .github/workflows/ci.yml
  - .gitignore
estimate:
  tokens: 36000
  raw_tokens: 24000
  tasks: 3
  confidence: low
must_haves:
  truths:
    - "The emulator direction, fixture rights policy, and future host/core pinning gap are recorded with decision provenance and clear non-goals."
    - "Tracked content has no real workstation-specific home-directory paths, and CI checks tracked text with a narrow, reasoned synthetic-example exception."
    - "Phase 06 records merged PR #7 and its latest green hosted evidence accurately while retaining the virtual-HID and aggregate/requirement gates as open."
    - "The next GSD action acknowledges that execute-phase 06 has no runnable plans and does not fabricate an implementation plan."
  artifacts:
    - path: ".planning/seeds/SEED-035-first-party-core-host-and-pair-pinning.md"
      provides: "Discoverable future seed for first-party core/host strategy, fixture provenance, and independently pinned host/core artifacts."
    - path: "scripts/check-tracked-text-hygiene.sh"
      provides: "Dependency-free tracked-text absolute-path hygiene check."
    - path: ".planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-VERIFICATION.md"
      provides: "Current Phase 06 evidence and remaining gates after PR #7 merge."
  key_links:
    - from: ".github/workflows/ci.yml"
      to: "scripts/check-tracked-text-hygiene.sh"
      via: "Hosted CI invokes the dependency-free tracked-file gate before normal jobs."
    - from: "scripts/check-tracked-text-hygiene.sh"
      to: "git ls-files"
      via: "Only tracked textual files are scanned; ignore rules cannot hide committed paths."
    - from: ".planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-VERIFICATION.md"
      to: ".planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-HOSTED-EVIDENCE.md"
      via: "The verification verdict cites the exact merged commit, workflow run, lane outcomes, and evidence ledger."
---

# Quick Task 261002-hwa: Record emulator direction and close tracked-text hygiene gaps

<objective>
Record the owner's emulator/core and fixture decisions, preserve the future host/core artifact identity gap, add a dependency-free privacy hygiene gate for tracked text, and reconcile Phase 06 evidence with merged PR #7.

Purpose: Keep the product boundary and legal fixture provenance discoverable, prevent machine-local absolute paths from entering tracked files, and leave Phase 06 status grounded in current hosted evidence.

Output: Updated project/seed/evidence records, a checked-in tracked-text path gate and exact root ignore entries, and a clear next GSD action. No app, emulator host, renderer, audio stack, fixture ROM, schema, or database changes are part of this task.
</objective>

<execution_context>
@$HOME/.codex/gsd-core/workflows/execute-plan.md
@$HOME/.codex/gsd-core/templates/summary.md
</execution_context>

<context>
@AGENTS.md
@.planning/STATE.md
@.planning/PROJECT.md
@.planning/research/STACK.md
@.planning/seeds/SEED-034-shift-manual-uat-clauses-left-into-ci.md
@.planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-20-SUMMARY.md
@.planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-VERIFICATION.md
@.planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-HOSTED-EVIDENCE.md
@.planning/ROADMAP.md
@.gitignore
@.github/workflows/ci.yml
</context>

<decisions>
- Owner direction: Playstead does not build emulator cores; preserve `.planning/PROJECT.md`'s existing core exclusion. The owner builds cores in separate repositories, each producing a C library, a headless runner, and a thin Libretro adapter, with no core-specific standalone player.
- Until a shared host exists, RetroArch is the core's host. Recommend a future shared host remain under the Playstead product/repository umbrella, behind an adapter and in a separately launched least-privilege process. This is provisional; revisit a repository split only if independent users or lifecycle needs justify it. Do not build the host, renderer, or audio stack in this task.
- Plan 06-20's Libretro harness remains test-only and throwaway; do not grow or reuse it. Preserve acceptance lessons as a possible later seed.
- Fixtures should be checked into Git when rights allow. Prefer a tiny Playstead-authored deterministic homebrew game/ROM with source, generated fixture, and explicit license/provenance if it can satisfy the oracle. A third-party fixture requires verified explicit public-repository and CI distribution rights covering ROM, code, assets/audio/data, and attribution. AerevenAdvance remains private unless its rights are independently established. No ROM or fixture implementation now.
- The present single-artifact AdapterPin/Catalog/Installer cannot represent a versioned host plus an independently versioned and hash-verified core. Record a future contract with host/core artifact roles, independent versions, archive and installed-file hashes, provenance/license/platform, compatible-pair manifest, staged atomic install/rollback, a launch descriptor selecting the core library, and runtime verification of the loaded core. Promote the host/core pair as future primary pin identity; a legacy standalone adapter is one case. Defer all implementation and ORM/schema changes.
- Hygiene: replace the 60 real workstation-specific home paths in tracked `.planning` text with a neutral placeholder; retain only synthetic test examples. Gate all tracked textual files, with narrow token-level allowlist entries and reasons for synthetic test paths. Add exact root `.gitignore` entries `root.crt` and `Playstead-Import-Fix-Local-CA.crt`.
- Preserve hosted-only PR runner posture. The committed CI has hosted runners and documents virtual-HID as blocked; do not import or enable the unsafe self-hosted job visible only in the owner's dirty shared checkout. Do not change `mode:yolo`, runtime/config, or third-party ROM fixture-inclusion policy beyond the rights policy above.
- Reconcile to merged PR #7 commit `ddd04ee06b93035711f3bdaeb8c40f86d99cdfed` and workflow run `37021805359`, latest attempt green for Linux recovery, server precommit, ordinary Mac (Unit 759/759, Rendering 52/52, UI 122/122, LiveServer 6/6), and Docker job (build/smoke steps path-filter skipped). Narrow mGBA 0.10.5 + private AerevenAdvance continuation passed twice with a visible state oracle. Phase 06 stays open for virtual-HID entitlement and aggregate/requirement review.
- In this isolated checkout, `gsd init execute-phase 06` reports 06-20 and 06-22 through 06-25 complete with no runnable/incomplete plans. State the next action without inventing a runnable phase plan. The untracked `06-recovery-proof-ci-and-e2e-p2` in the shared checkout is a plain text context file, is absent here, and must not be deleted by this task.
- Planning-hook annotation: `No external API integration: planning decisions and tracked-text CI hygiene only.` No external API coverage artifact is required.
</decisions>

<tasks>

<task type="auto">
  <name>Task 1: Record the owner-approved emulator and fixture policy with a future artifact-pair seed</name>
  <files>.planning/PROJECT.md, .planning/seeds/SEED-034-shift-manual-uat-clauses-left-into-ci.md, .planning/seeds/SEED-035-first-party-core-host-and-pair-pinning.md</files>
  <action>Keep `.planning/PROJECT.md`'s existing statement at line 59 that Playstead does not build emulator cores, and add concise owner-decision context for separate owner-built core repositories, C library/headless runner/thin Libretro adapter outputs, RetroArch as interim host, and the provisional Playstead-umbrella shared host boundary with adapter and least-privilege separate process. Record that the shared host split is revisited only if independent users/lifecycle justify it, and that no host/renderer/audio work is authorized now. Update SEED-034 with the Plan 06-20 disposition: its Libretro harness is throwaway and test-only, with useful acceptance lessons retained without reuse or growth. Create SEED-035 as a dormant, discoverable seed triggered before the next adapter/installer/core-host contract work; include the first-party fixture preference and exact third-party rights checks, private status of AerevenAdvance, host/core independent pin identity and complete fields from `<decisions>`, and explicit boundaries against emulator, schema, or ROM implementation now. Cite this owner decision and source paths/date so future planning has provenance. Keep the exact external-API hook annotation in this plan only; do not persist it in PROJECT.md or either seed.</action>
  <verify>
    <automated>git diff --check && rg -n 'does not build emulator cores|RetroArch|headless runner|AerevenAdvance' .planning/PROJECT.md .planning/seeds/SEED-034-shift-manual-uat-clauses-left-into-ci.md .planning/seeds/SEED-035-first-party-core-host-and-pair-pinning.md</automated>
  </verify>
  <done>The project boundary remains explicit, the throwaway harness cannot be mistaken for a product host, and the legal-fixture plus future host/core pinning decisions are discoverable from seed metadata and provenance.</done>
</task>

<task type="auto">
  <name>Task 2: Remove tracked local paths and enforce narrow tracked-text hygiene in hosted CI</name>
  <files>scripts/check-tracked-text-hygiene.sh, .github/workflows/ci.yml, .gitignore, tracked text files under .planning</files>
  <action>Replace the 60 real workstation-specific home-directory path occurrences in tracked `.planning` text with a neutral placeholder while retaining only deliberately synthetic test examples. Implement a dependency-free gate that enumerates tracked files from `git ls-files`, identifies textual content without dumping matched lines or path contents into CI logs, rejects workstation-specific absolute-path tokens across all tracked text (including `.planning`), and handles filenames safely. Keep the exception narrow and token-level: allow only exact synthetic test-example tokens, with an adjacent reason for each allowlist token; do not exempt whole files, directories, or broad home-directory patterns. Failure output must never contain matched text; emit only a fixed finding identifier and a safe aggregate count. Invoke the gate on hosted CI from repository root, before normal jobs or as a required hosted-only job. Preserve current hosted runners and virtual-HID blocked documentation; do not add any self-hosted runner, secret, privilege, or trigger. Add only the two exact root `.gitignore` lines `root.crt` and `Playstead-Import-Fix-Local-CA.crt`.</action>
  <verify>
    <automated>bash scripts/check-tracked-text-hygiene.sh && git diff --check</automated>
  </verify>
  <done>All real workstation paths are removed from tracked `.planning` text, only justified synthetic path tokens are exempted, the dependency-free gate implements and wires into hosted CI, failure output contains no matched text, and the two requested local CA files are ignored exactly.</done>
</task>

<task type="auto">
  <name>Task 3: Reconcile Phase 06 state and verification to merged PR #7 evidence</name>
  <files>.planning/STATE.md, .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-VERIFICATION.md, .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-HOSTED-EVIDENCE.md</files>
  <action>Update stale Phase 06 state and evidence records from PR #6-era pending/failing claims to the provided merged PR #7 evidence, citing merge commit `ddd04ee06b93035711f3bdaeb8c40f86d99cdfed` and workflow `37021805359` with its latest-attempt results: Linux recovery, server precommit, and ordinary Mac pass; Unit 759/759, Rendering 52/52, UI 122/122, LiveServer 6/6; Docker job success with Docker build/smoke steps skipped by path filter. Record two successful narrow mGBA 0.10.5/private AerevenAdvance continuation runs with visible state oracle, while explicitly keeping the fixture private and the result narrow. Retain Phase 06 as open: virtual-HID entitlement is blocked/not-configured, and aggregate/requirement review remains incomplete. Reconcile STATE.md's stale phase position/status using the actual GSD phase state without claiming the milestone or Phase 06 complete. Record `gsd init execute-phase 06`'s no-runnable-plan result and name `$gsd-progress` as the next command to select the correct action; do not fabricate a phase plan or delete absent shared-checkout context. Keep evidence provenance precise and do not infer skipped Docker steps passed as executed.</action>
  <verify>
    <automated>git diff --check && rg -n 'ddd04ee06b93035711f3bdaeb8c40f86d99cdfed|37021805359|759/759|52/52|122/122|blocked/not-configured|gsd-progress' .planning/STATE.md .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-VERIFICATION.md .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-HOSTED-EVIDENCE.md</automated>
  </verify>
  <done>The records identify the merged head and current hosted evidence, accurately distinguish skipped Docker steps from executed jobs, preserve the still-open entitlement/aggregate gates, and direct the operator to `$gsd-progress` because Phase 06 has no runnable plans.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|---|---|
| Tracked repository text -> hosted CI logs | A failed path scan must not echo sensitive matched lines or file contents. |
| Synthetic test allowlist -> production gate | An overbroad exemption could hide real machine-local paths from review and CI. |
| Public pull request -> CI runner | Workflow changes and untrusted PR content execute on hosted runners; no self-hosted machine or private fixture may be exposed. |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|---|---|---|---|---|---|
| T-Q-HWA-01 | Information Disclosure | tracked-text hygiene output | medium | mitigate | Report only a fixed failure token and safe aggregate count; never print matching lines or path-bearing file content. |
| T-Q-HWA-02 | Tampering | synthetic token allowlist | high | mitigate | Allow exact token(s) only, require an adjacent reason, and reject directory/file-wide bypasses. |
| T-Q-HWA-03 | Elevation of Privilege | public PR workflow | high | mitigate | Retain hosted ephemeral runners and existing read-only permissions; never enable or copy a self-hosted job or expose local fixtures/secrets. |
</threat_model>

<verification>
Run the dependency-free tracked-text hygiene gate against the checked-out tracked content, then `git diff --check`. Review the workflow diff to confirm only hosted execution remains and Docker path-filter skip semantics are unchanged. Do not run app, XCTest, or local suite commands.
</verification>

<orchestrator_follow_up>
After executing the quick task and recording its summary, run `$gsd-progress`. The Phase 06 execute-phase initializer reports no runnable or incomplete plans; use the progress result to route the next GSD action, and preserve the open virtual-HID and aggregate/requirement gates. Do not create a new phase plan from this evidence-reconciliation task.
</orchestrator_follow_up>

<source_coverage>

| Source | Item | Coverage |
|---|---|---|
| GOAL | Owner emulator/core boundary and fixture direction | Task 1 records decisions, scope limits, rights requirements, and provenance. |
| GOAL | Tracked-text path privacy and root ignore entries | Task 2 updates tracked text and implements and wires the hosted gate. |
| GOAL | Reconcile PR #7 and Phase 06 status | Task 3 updates STATE, verification, and hosted evidence without closing open gates. |
| RESEARCH | Mature emulator integration; user-supplied/private content posture; adapter boundary | Tasks 1 and 3 preserve these constraints and do not authorize content distribution. |
| CONTEXT | Owner decisions in this plan | Tasks 1–3 implement the fixture/core, hygiene, evidence, and next-command decisions. |
| SECURITY | CI log disclosure, allowlist overbreadth, untrusted PR execution | Task 2 and this plan's STRIDE register define direct mitigations. |

</source_coverage>

<success_criteria>
- Owner decisions, fixture provenance policy, and future host/core artifact pinning are durable and discoverable.
- A dependency-free tracked-text gate rejects local workstation path tokens without revealing matches, and CI invokes it on hosted runners.
- Requested root CA ignore entries are present, while the virtual-HID lane remains blocked and no self-hosted workflow is introduced.
- Phase 06 hosted evidence cites the merged PR #7 commit and latest run, retains the open aggregate gates, and gives `$gsd-progress` as the next GSD action.
- No emulator, fixture, app, test-suite, schema, or database implementation is included.
</success_criteria>

<output>
Create `.planning/quick/261002-hwa-record-first-party-emulator-core-directi/261002-hwa-SUMMARY.md` after execution, capturing changed records, focused hygiene verification, current Phase 06 status, and the `$gsd-progress` follow-up.
</output>
