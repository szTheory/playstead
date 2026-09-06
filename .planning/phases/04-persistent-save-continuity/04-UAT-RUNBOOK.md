# Phase 4 UAT — Runbook

Everything that a machine could check has been checked. **109 of 120 tests pass.**
This is the list of what still needs you, and exactly how to do each one.

There are **4 sessions**. You can do them in any order, on different days.

| Session | Time | Closes | Needs |
|---|---|---|---|
| A — Look at the web console | 5 min | 108 | Nothing, the server is already running |
| B — Run the Mac UI tests | 20 min | 109, 110, 111, 115, 113 | Your Mac, Xcode |
| C — Push to CI | 5 min + wait | 106, 117 | A push to GitHub |
| D — Play a real game | 30 min | 107, 112, 120 | A real GBA game + mGBA |

After each session, record the result (see **How to record a result** at the bottom).

---

## Session A — Look at the web console (5 min)

**Closes test 108.**

1. Open this in your browser:

   ```
   https://localhost:18443/saves
   ```

   (Self-signed cert — click through the warning. Your stack is already up.)

2. Find a game with a diverged save line and open it. If none exists, `/saves` alone is
   enough to judge the list surface.

3. Look at the comparison screen and answer one question:
   **does it feel calm, and does tabbing through it feel natural?**

   The things below are *already proven by tests* — you do not need to check them:
   - exactly four facts per side
   - digest hidden behind "Details"
   - no confirmation dialog
   - no Undo
   - no side pre-selected or recommended
   - no bulk "always use this Mac" control

   You are only judging how it *reads*.

4. Record `108` as **pass**, or describe what feels off.

---

## Session B — Run the Mac UI tests (20 min)

**Closes tests 109, 110, 111, 115. Also lets you eyeball 113.**

These are blocked for me on purpose. The project's own script refuses to launch the app
from an automated run, because launching Playstead can pop a login-Keychain prompt:

> `run-mac-verification.sh:1026` — *"a human may explicitly set
> PLAYSTEAD_HUMAN_APPROVED_LOCAL_APP_LAUNCH=1, but automated GSD runs must not set it"*

**You** are allowed to set it. I am not. That is the whole reason these are open.

1. Open a terminal:

   ```bash
   cd ~/projects/playstead/playstead-mac
   export PLAYSTEAD_HUMAN_APPROVED_LOCAL_APP_LAUNCH=1
   ```

2. Run the four suites, one command each. If a Keychain prompt appears, click **Always Allow**.

   ```bash
   # Test 109 — the divergence comparison sheet
   ./scripts/ci/run-mac-verification.sh --layers ui \
     --only-testing PlaysteadUITests/ConflictResolutionInteractionTests

   # Tests 110 and 111 — the "only copy" interruptive modal
   ./scripts/ci/run-mac-verification.sh --layers ui \
     --only-testing PlaysteadUITests/OnlyCopyInterruptionTests

   # Test 115 — the four front-door journeys
   ./scripts/ci/run-mac-verification.sh --layers ui \
     --only-testing PlaysteadUITests/SaveFrontDoorJourneyTests
   ```

3. Each command either says it passed or prints the failures.
   - All green → record those tests as **pass**.
   - Anything red → paste the failure into the UAT file. That is a real gap.

4. **While the modal suite runs**, watch the screen for test 113: when the interruptive
   sheet appears and you press the default **"Export saves…"** button, does opening the
   browser feel calm and unambiguous — or does it feel like something destructive might
   have just happened? Record `113` on that impression alone. (The URL being correct and
   the destructive path never firing are already proven by tests.)

5. When you are finished:

   ```bash
   unset PLAYSTEAD_HUMAN_APPROVED_LOCAL_APP_LAUNCH
   ```

---

## Session C — Push to CI (5 min + wait)

**Closes tests 106 and 117.**

These two need a live paired server and the staged live-server fixture
(`PLAYSTEAD_MAC_CI_ROOT`, `PLAYSTEAD_LIVE_SERVER_STAGE_ROOT`). That whole rig is built by
the hosted runner. Doing it by hand is not worth it.

1. Push the branch and let the macOS workflow run.
2. When it goes green, the live-server layer has executed
   `PlaysteadUITests/SaveEndToEndTests` and the upload lane against a real server.
3. Record `106` and `117` as **pass**, with the CI run URL as the evidence.

If CI is not set up for this yet, leave both blocked. They are not defects — they are
missing infrastructure.

---

## Session D — Play a real game (30 min)

**Closes tests 107, 112, and 120 (CP7-SAVE-C) — the one that actually matters.**

This is the only proof that a save restored by Playstead still *plays*. Nothing else in
this phase substitutes for it. A green test suite is not this.

You need: the pinned mGBA adapter installed, a real commercial GBA title, and the server
running and paired.

Do these five steps and write down what you see after each one:

1. **Launch the title through Playstead.** Play until you trigger an in-game save.
   → Roughly how long after the in-game save does the `.sav` file on disk change?
   It must change on some bounded cadence. "Never" is a failure.

2. **Quit the emulator normally.**
   → Did Playstead capture a revision for that session?
   → Did the post-exit settle pass pick up bytes the earlier reads had missed?

3. **Delete the game's save directory** (simulating a clean Mac). **Relaunch through
   Playstead** and let the automatic restore run.
   → It must restore with **no prompt**. A prompt is a failure.

4. **Continue the game.**
   → Is the progress exactly what you saved? Not a fresh file, not an older state.
   → Any in-game "save corrupt, erase?" prompt is a failure.

5. **Repeat step 2 with a force-quit** instead of a normal exit.
   → Did it still capture a revision?

**Also record the game title you used and the mGBA adapter version.**

> If any step fails, do **not** mark it passed. Write down the failure and stop — it is a
> phase-blocking finding.

---

## How to record a result

Open:

```
.planning/phases/04-persistent-save-continuity/04-UAT.md
```

Find the test by its number (`### 108.`, `### 120.`, etc.) and change its `result:` line:

```yaml
result: pass
```

or, if something was wrong:

```yaml
result: issue
reported: "what you actually saw, in your own words"
```

Then commit and re-run:

```bash
/gsd-verify-work 4
```

That re-reads the file, updates the counts, and — if anything is marked `issue` —
automatically diagnoses it and writes fix plans.

---

## What is already done (no action needed)

- **109 tests pass.** 104 covered by passing automated suites across all 25 plans.
- **Test 1, cold start** — ran `compose-smoke.sh --fresh` in an isolated Docker project
  (your real library volumes were never touched). All five Phase 4 migrations applied from
  an empty database; server booted; endpoints returned 200.
- **Test 119** — Mac unit suite, 44 tests, 0 failures.
- **Tests 114 and 116** — these asked you to rule on two disclosed gaps. Both were already
  closed by later plans in this same phase (04-19 wired the failure classifier and the
  capture trigger; 04-20, 04-23 and 04-25 closed the rest). Nothing for you to decide.
- **Zero issues found.** Nothing is currently broken. Everything open is "not yet
  observed," not "observed and wrong."
