---
quick_id: 260826-tqx
status: complete
date: 2026-08-26
---

# Quick Task 260826-tqx: Adopt Playstead

## Goal

Adopt **Playstead** as the project and ecosystem family name without changing the product scope, establish the intended monorepo workspace roots, preserve the naming research and decision provenance, and rename the parent workspace from `emu-server` to `playstead`.

## Tasks

### 1. Migrate the project identity

**Files:** `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/research/*.md`, `.planning/discovery/*.md`, `AGENTS.md`

**Action:** Replace the temporary Emu Server identity with Playstead, update Elixir module/application examples, mark the old naming deferral as superseded, and record the owner's 2026-08-26 decision with the existing non-legal-clearance caveat intact.

**Verify:** Search tracked files for stale `Emu Server`, `emu-server`, and `emu_server` references, allowing only explicitly labeled historical references where necessary.

**Done:** All active project documentation consistently identifies the product as Playstead and preserves rather than erases the naming history.

### 2. Establish the workspace boundaries

**Files:** `README.md`, `playstead-server/README.md`, `playstead-mac/README.md`

**Action:** Document the parent workspace and create tracked server and Mac client code roots. Keep Phoenix LiveView inside the server application and keep the protocol server-first until more than one proven consumer justifies extraction.

**Verify:** Confirm the documented structure matches the architecture and roadmap and contains no nested Git repositories.

**Done:** A contributor can tell where server and Mac work belong and which future repositories are intentionally deferred.

### 3. Record and complete the migration

**Files:** `.planning/STATE.md`, this quick-task directory

**Action:** Add the quick-task completion record and summary, verify the planning corpus and Git status, commit the migration atomically, then rename `~/projects/emu-server` to `~/projects/playstead` as the final filesystem operation.

**Verify:** The commit is clean before the move; the new path exists afterward and contains the Git repository and both code roots.

**Done:** Playstead is ready for Phase 1 planning from its final workspace path.
