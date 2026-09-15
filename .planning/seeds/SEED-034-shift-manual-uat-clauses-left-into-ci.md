---
id: SEED-034
status: dormant
planted: 2026-09-13
planted_during: v1.0 / Phase 03 (Mac Offline Play Vertical Slice) — UAT item 7 manual run
trigger_when: before the next phase that touches AdapterHost, the outbox, or library availability
scope: testing strategy
---

# SEED-034: Shift the manual-UAT clauses left into CI, where recurring value exists

## Why This Matters

On 2026-09-13 the owner closed three clauses of UAT item 7 by hand and turned up
six defects in about two hours. The claim was made in-session that "no automated
test could have caught" the exit-classification one. **That claim was too strong,
and the owner pushed back correctly.** Most of what the manual run found is
mechanizable. This seed is the list, with the honest reason each one was missed,
so a future plan can decide where recurring value actually is rather than
automating everything reflexively.

## What the manual run found, and what would have caught it

1. **A normal quit classifies as `unknown`** (`AdapterPin.json` `exit_detection`
   has no `status 0 / exit` signature). Missed because `AdapterExitTests` classify
   against the same pin table they assert — a closed loop. **Catchable:** a test
   that spawns a real short-lived child process, lets it exit 0 on its own, and
   asserts the classification is a *named* case rather than `.unknown`. No
   emulator and no ROM needed — `/bin/sleep 0.1` exits 0/`exit` exactly like mGBA
   does. A boundary test over the cross-product of {0, 9, 11, 15} x {exit,
   uncaughtSignal} asserting no combination lands in `.unknown` would have failed
   on day one. This is the highest-value item here and it is cheap.

2. **Hardcoded `.serverOnly` card badge; `AvailabilityState.derive` and
   `GameListView` with zero production call sites.** Missed because every test
   constructs the type under test directly, so unreachable production wiring looks
   covered. **Catchable:** a reachability guard in CI — for a named set of types
   that are supposed to be on a production path, assert at least one
   non-test construction site exists. Cheaper and more honest than a UI test.
   Related: the existing `plumbed-everywhere-proven-nowhere` lesson.

3. **The real download path never writes `cache_objects`.** Missed because two
   download paths exist and only the queue path's commit is tested.
   **Catchable:** one integration test that drives `attemptDownload` against a
   stub server and asserts the post-conditions a download must leave behind
   (CAS object present AND `cache_objects` row AND quota's `usedBytes()` reflecting
   it). A seam test per-path, not per-function.

4. **The outbox never drains when a server returns without the Mac's network
   changing.** Missed because `Reachability` is injected and flipped directly in
   tests, so the "interface never changed but the server came back" case has no
   representation. **Catchable:** an integration test where the stub server goes
   from refusing to accepting while reachability stays `true` throughout, asserting
   the queue drains. This is the shape the runbook's own comparison table already
   names.

5. **"Quitting returns to the library" asserts navigation the app never
   performs.** Not a code defect — a criterion that does not match the
   architecture. No test would help; the lesson is that acceptance wording should
   be checked against reachable behaviour when it is written.

6. **Save capture needs the battery `.sav`, not a save state.** Cost an entire
   manual run. **Catchable** and probably already is, at the unit level; the
   failure was in the runbook's instructions, not the app.

## The discipline this should respect

Automate where there is *recurring* value. Several of the above are one-time
audits whose value is fully banked once fixed (2 and 3 partly), while others are
genuine regression risks worth a permanent gate (1 and 4). A plan acting on this
seed should classify each before adding CI, and should prefer a cheap
reachability/post-condition assertion over a hosted UI run whenever both would
catch the same class. The physical-hardware clauses (items 8-10) stay out of
scope — they need the IOHIDUserDevice virtual-gamepad work those items already
name.

The homebrew-ROM licensing decision for a self-hosted Mac runner is still the
owner's and still unmade; note that items 1-4 above need no ROM at all, so they
are not blocked on it.

## Status after the fix pass, 2026-09-13

Four of the six items above have been fixed and gated on branch
`feat/dev-standup-and-uat7-closure`. Recorded here rather than left for a
future plan to rediscover, because a seed that no longer describes reality
is worse than no seed.

- **Item 1 (normal quit classifies as `unknown`) — STILL OPEN, and still the
  highest-value gate here.** The gate this seed proposes cannot land before
  the fix does: the `{0, 9, 11, 15} x {exit, uncaughtSignal}` sweep asserting
  nothing lands in `.unknown` *fails today*, which is the whole point. And
  the fix is blocked on an owner decision, not on effort — see WINDOWS #76.
  Nothing consumes `AdapterExit.clean` behaviourally yet (only `GameRowView`'s
  debug "Last exit:" line), so the blast radius of changing the mapping is
  about as small as it will ever be. Write the sweep in the same change as
  the pin fix.

- **Item 2 (unreachable derivation / hardcoded badge) — fixed; gated at two
  levels.** `LibraryStatusWiringTests` drives each state through the real
  stores via the composition root, and
  `StorageInteractionTests.testCachedAndPinnedGameIsNotDescribedAsBeingOnThe
  Server` asserts it at the front door. The generic "reachability guard over a
  named set of types" this seed proposed was NOT built: a per-defect front-door
  assertion turned out to be cheaper and more honest than a list of types
  someone has to remember to maintain. The idea is still worth considering as
  a lint, but it is no longer needed for this defect. (WINDOWS #72/#73/#74)

- **Item 3 (download path post-conditions) — fixed, and gated exactly as
  proposed.** `StorageShellWiringTests` now asserts CAS object + `cache_objects`
  row + `usedBytes()` after a real `attemptDownload`, and its fixture no longer
  hand-inserts the row it was papering over. (WINDOWS #75)

- **Item 4 (server returns without a network change) — fixed, and gated
  exactly as proposed.** `OutboxDrainTickerTests.testAServerThatComesBackIs
  NoticedWithoutAnyNetworkChange` drives a 503 -> 200 transition with
  reachability untouched throughout. (WINDOWS #77)

- **Items 5 and 6** stand as written: neither wants a test.

One finding this seed did not anticipate, worth carrying forward as a pattern:
the fixture for item 3 was performing the exact write production was missing.
A wiring suite whose helpers simulate the production side-effect they exist to
prove cannot fail. When adding a post-condition gate, check what the fixture
does *before* trusting the suite's greenness.
