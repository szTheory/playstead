---
type: quality
created: 2026-09-03
resolves_phase:
source: 04 execute-phase wave 1 post-merge gate
---

# Full-suite test runs are non-deterministic under load

Two unrelated higher-level tests failed intermittently during the Phase 4
Wave 1 post-merge gate, in two different runtimes, on binaries that were
otherwise identical. Each passed when run in isolation and on re-run.

| Test | Runtime | Assertion that flaked |
|---|---|---|
| `AppPathsBackupExclusionTests.testExistingInstallWithStaleRootFlagIsRepairedAtInit` | Swift | reads APFS `isExcludedFromBackup` immediately after writing it |
| `PlaysteadWeb.Browser.SetupWizardJourneyTest` "first run: token -> ... -> recovery login" | Elixir | Wallaby `assert_has(css("#nav-account", text: email))` found 0 visible elements |

**Why it matters:** a gate whose verdict depends on machine load cannot
distinguish a real cross-plan integration break from noise. That is the same
class of problem as a gate that fails open (see the 03.5 fail-open findings) —
it just fails loudly rather than silently. Every remaining Phase 4 wave
boundary runs this suite.

**Notes toward a fix:**
- The Swift case is an attribute-visibility race, and Phase 4 plan 04-01 built
  a probe (`save-p1-probe.swift`) that measures exactly this class of APFS
  behaviour. The probe's findings should inform whether the test needs a
  retry/poll or whether the production read is genuinely racy.
- The Wallaby case is most likely a missing explicit wait after navigation.

Suggested home: fold into 04-13 (validation), which already owns naming
honestly what can and cannot be proven automatically.
