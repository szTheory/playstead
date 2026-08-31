# GSD Debug Knowledge Base

Resolved debug sessions. Used by `gsd-debugger` to surface known-pattern hypotheses at the start of new investigations.

---

## user-prompt-hook-exit-code-1 — Codex UserPromptSubmit hook failed because its installed dependency closure was missing
- **Date:** 2026-08-31
- **Error patterns:** UserPromptSubmit hook failed, hook exited with code 1, MODULE_NOT_FOUND, ./lib/hook-exit.js, gsd-context-monitor.js
- **Root cause(s):** @opengsd/gsd-core 1.12.0's Codex installer stages gsd-context-monitor.js but explicitly omits hooks/lib, leaving its required three-file local dependency closure absent.
- **Fix:** Installed the exact three-file 1.12.0 dependency closure under ~/.codex/hooks/lib: hook-exit.js, cli-exit.js, and exit-code-registry.js.
- **Files changed:** /Users/jon/.codex/hooks/lib/hook-exit.js, /Users/jon/.codex/hooks/lib/cli-exit.js, /Users/jon/.codex/hooks/lib/exit-code-registry.js
- **Why not caught:** No Codex installer integration gate existed in @opengsd/gsd-core 1.12.0 to launch every installed hook in a clean destination and verify that its complete relative-import closure was staged.
- **Recurrence guard:** The resolved-session pattern in `.planning/debug/knowledge-base.md` records the exact missing hooks/lib closure, the three-file repair, and the reinstall risk so a future Phase-0 debug recall tests this cause first.
---
