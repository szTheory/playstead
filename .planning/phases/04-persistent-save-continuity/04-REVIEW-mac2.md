---
status: issues-found
scope: mac-swift-remainder
files_reviewed: 22
critical: 4
warning: 5
info: 2
---

# Phase 4 Mac/Swift Code Review — Remainder Pass (mac2)

Scope: the 22 files in `/tmp/gsd-scope-mac2.txt`, not opened by the prior
20-file pass. Extra attention given to `Net/APIClient.swift`,
`Sync/Outbox.swift`, and `Sync/SyncEngine.swift` per instructions. Every
finding below cites lines actually read in this session. Where a finding
required following a call chain into a file outside the 22-file scope
(e.g. `GameRowView.swift`, `LibraryShellView.swift`, `StatusSlotView.swift`'s
zero call sites), that cross-reference is noted explicitly — the file that
anchors the finding inside scope is always identified.

## Critical

### CR-01: The D-40 interruptive-gate's own escape hatch is a no-op button

**Files:**
`playstead-mac/Playstead/Library/ReclaimPromptView.swift:153-173`
`playstead-mac/Playstead/Library/StorageView.swift:241-261`

**Issue:** Both production call sites of `OnlyCopyInterruptiveSheet` wire
`onExport` to nothing but dismissal:

```swift
onExport: {
    showOnlyCopyInterruption = false
},
```

D-40's locked copy makes "Export saves…" the **default button** — the
explicitly-designed escape hatch a user is meant to take before a
destructive action proceeds ("it states the fact, offers the escape hatch
first, and keeps the destructive path available"). In both shipped call
sites, tapping it does not export anything; it just closes the sheet.
`pendingSelection` is left untouched (it is only cleared in the cancel and
remove-anyway branches), so a user who taps the default, safest-looking
button walks away believing their only-copy saves are now protected, when
nothing happened. `ReadinessSheetView.apply(_:)` in the same codebase
states the design principle this violates almost verbatim: "Every branch
either opens a real surface or performs a real action — a remedy button
that did nothing would be worse than no button at all" (`Readiness/ReadinessSheetView.swift:106-109`).

**Why it matters:** A user who trusts the default button to have exported
their progress, then later returns and clicks "Remove anyway" on a
subsequent occurrence (having forgotten nothing was actually exported),
can lose the only copy of their save data while believing it was backed
up moments earlier by the very control designed to prevent that.

**Fix:** Wire `onExport` to a real export action (there is a
`compareExportAction`/export machinery already built for the comparison
sheet — reuse it, or route to `Export.SavesPlan` per D-62), or, if export
truly isn't wired yet, do not present this button as the default action
until it does something; disable it with an honest "coming soon" state
rather than silently succeeding at nothing.

---

### CR-02: The D-40 interruptive gate can never fire from either production reclaim surface — it is fed a hardcoded zero

**File:** `playstead-mac/Playstead/App/PlaysteadApp.swift:887-891`

```swift
func reclaimCandidateRows() -> [ReclaimCandidateRow] {
    evictionPlanner.candidates().map {
        ReclaimCandidateRow(id: $0.id, title: $0.title, bytes: $0.bytes)
    }
}
```

`ReclaimCandidateRow.onlyOnThisMacCount` defaults to `0`
(`Library/ReclaimPromptView.swift:15`) and is never set here. Cross-checked
against both consumers: `GameRowView.swift:170-174` calls
`environment.reclaimCandidateRows()` directly with no override, and
`LibraryShellView.swift:252-261` constructs `StorageView(...)` without ever
passing `onlyOnThisMacCounts:`, so that view's default `[:]`
(`Library/StorageView.swift:47`) applies too. `OnlyCopyInterruptionGate
.shouldPresent(onlyOnThisMacCount:)` is `onlyOnThisMacCount > 0`
(`Saves/OnlyCopyInterruptiveSheet.swift:17-19`), so with the count always
`0`, the interruptive modal can **never** appear from either shipped
reclaim/eviction surface, no matter how many revisions are genuinely
local-only.

**Why it matters:** D-40 names "eviction" as one of the five destructive
intents that must show this modal. The gate, the sheet, and the locked
copy are all fully implemented and individually correct (see "Verified
clean" below) — but the one fact the gate needs to decide whether to
appear at all is never computed in the app's composition root. This is
the exact "dead safety control" failure mode: code review of the sheet in
isolation would find nothing wrong, but the control never activates in a
running app. (Whether `EvictionPlanner.execute` can currently ever
actually touch save bytes given D-29's "saves are never evictable"
guarantee is outside this file's scope to confirm — but the wiring gap
itself is unambiguous and contradicts the decision's explicit intent
regardless of how `EvictionPlanner` currently behaves.)

**Fix:** Compute a real per-candidate `onlyOnThisMacCount` in
`reclaimCandidateRows()` and thread `onlyOnThisMacCounts` through the
`StorageView(...)` call site, sourced from `SaveStore`/durable rows per
`OnlyCopyInterruptiveSheet`'s own doc comment ("compute … from durable
rows, not from a pending upload's assumed outcome").

---

### CR-03: The whole divergence-surfacing pipeline (card badge + comparison sheet) has no production call site

**Files:**
`playstead-mac/Playstead/Library/StatusSlotView.swift:129-149`
`playstead-mac/Playstead/Saves/ConflictComparisonSheet.swift:248-259` (doc comment, self-disclosed)
`playstead-mac/Playstead/App/PlaysteadApp.swift` (absence, whole file)

**Issue:** `LibraryStatus.forSaveState(conflicted:)` is the sole documented
seam by which a genuine save divergence is supposed to reach the card's
rank-1 `needsAttention` rung (D-38). A repo-wide search found **zero**
production call sites for `forSaveState`, `SaveAttentionSource.*`, or
`SaveAttentionItem` — only the type/enum definitions and their own unit
tests. `ConflictComparisonSheet.swift`'s own doc comment confirms this
directly: "No production navigation reaches this sheet yet — that live
wiring (attention inbox, game detail) is a later plan's job." Consistent
with this, `AppEnvironment` in `PlaysteadApp.swift` constructs no
`SaveStore`, `SaveAttentionSource`-consuming view model, or attention
inbox of any kind — the only save-shaped store it touches is the private
one `SyncEngine` builds for itself to apply incoming journal entries
(`Sync/SyncEngine.swift:69,81`).

**Why it matters:** D-38's entire purpose is that a diverged save must
reach the user through the same rank-1 "Needs attention" channel as every
other must-fix condition. As shipped, a user with two genuinely diverged
save versions gets **no card badge, no attention-inbox item, and (per
CR-04 below) no readiness-sheet warning either** — the feature exists,
is unit-tested, and is completely invisible in the running app. This
directly undercuts the phase's stated goal ("shows honestly which
revisions exist where") for the one condition (divergence) that most
needs surfacing, since D-46 also forbids auto-resolving it — an
unsurfaced, un-auto-resolved fork is a fork nobody is ever told about.

**Fix:** Wire `SaveAttentionSource.allItems` into whatever view model feeds
`StatusSlotView`'s `statuses:` array and into a real attention inbox
surface, and give `ConflictComparisonSheet` a real presentation trigger
from game detail / the inbox, per D-53's three named entry points.

---

### CR-04: `ReadinessEngine` is built without `saveReadiness:` — the D-37 Save row always reports "No saved progress yet."

**File:** `playstead-mac/Playstead/App/PlaysteadApp.swift:699-730`

```swift
let engine = ReadinessEngine(
    cas: casManager,
    downloadQueue: downloadQueue,
    adapterInstallState: { installState },
    biosRequired: biosRequired,
    hasManagedBIOS: { hasBIOS },
    hasController: { hasController },
    saveDirectoryURL: saveDirectory
)
```

No `saveReadiness:` argument is passed, so `ReadinessEngine`'s default
(`{ .noSavesYet }`, `Readiness/ReadinessEngine.swift:71`) is used
unconditionally. Cross-checked the one production call site of
`readinessReport(for:)`, `GameRowView.swift:130-133` — it calls
`environment.readinessReport(for: entry)` with no override available (the
`saveReadiness` closure lives entirely inside `AppEnvironment`, not
exposed to the caller). The same call site also never passes
`saveHistorySessions:` into `ReadinessSheetView`, so that closure's default
`{ [] }` (`Readiness/ReadinessSheetView.swift:27`) applies too — the "Save
history" sheet reached from "Review versions…" would also always render
its empty state.

**Why it matters:** Every branch of `evaluateSaveState()` other than
`.noSavesYet` — `uploadedAndCurrent`, `localOnlyExpectedOffline`,
`localOnlyReachable`, `serverHasNewer`, `twoVersions` — is dead code in
production. The Save row required by D-37/SAVE-02 never tells a real user
their progress is local-only, never explains an offline queue, and never
surfaces the "Two versions of your progress are waiting for your
decision." warning with its "Review versions…" action. Combined with
CR-03, this means there is currently **no reachable UI surface in the
shipped app that tells a user about a real save divergence or an
unuploaded-only-local save**, despite both being fully modeled, copy-locked,
and unit-tested.

**Fix:** Compute the real `SaveReadinessCase` for `entry` from `SaveStore`
in `AppEnvironment.readinessReport(for:)` and pass it as `saveReadiness:`;
likewise compute real `SaveHistorySession`s for `saveHistorySessions:`.

---

## Warnings

### WR-01: `SaveOutbox` has no backoff and no terminal/quarantine state, unlike the `Outbox` immediately above it in the same file

**File:** `playstead-mac/Playstead/Sync/Outbox.swift:360-392`

`Outbox` (curation) has `maxAttempts`, exponential `retryDelay`, and a
`quarantined` terminal state for a poison entry (lines 58-63, 87-89,
192-207). `SaveOutbox.markFailed` (lines 364-368) only increments
`attempt_count` — no cap, no delay, no terminal state — and
`SaveOutbox.drainOnce` (lines 375-392) retries **every** pending entry on
**every** call with no `next_retry_at` filter at all. A save-resolution
intent (choose-side / acknowledge-fork) that is permanently rejected by
the server — e.g. a `409` because another device already resolved the
same fork — will be retried on every future drain cycle, forever, with no
backoff and with no way for the entry to ever surface as "stuck" to a
test or a future UI. This is explicitly the failure mode the review brief
calls out ("retry/backoff that can spin or give up permanently on a
recoverable failure").

**Why it matters:** Not a data-loss path (the local mutation this entry
protects is non-destructive per the type's own doc comment), but it is a
resource/robustness gap: a rejected resolution intent hammers the server
indefinitely with no observable "this needs attention" signal, unlike
every other outbox in this codebase.

**Fix:** Give `SaveOutbox` the same `attemptCount`/backoff/terminal-state
shape `Outbox` already has, or explicitly document why resolution intents
are exempt from that discipline.

### WR-02: `SaveOutbox.drainOnce` conflates transport failure with permanent rejection

**File:** `playstead-mac/Playstead/Sync/Outbox.swift:376-392`

```swift
do {
    _ = try await apiClient.send(...)
    try? markDone(entry.id)
    sent += 1
} catch {
    try? markFailed(entry.id)
}
```

Every non-2xx response and every transport error take the identical
`markFailed` path. `Outbox` (curation) distinguishes a transport/5xx
failure (`markPendingForRetry`, retry-worthy) from a permanent 4xx
rejection (`markRejected`, revert + surface to user) — see
`Outbox.swift:182-221`'s own doc comments. `SaveOutbox` has no equivalent
distinction, compounding WR-01: a `400`/`404`/`409` here is treated
exactly like a flaky network blip and retried forever.

**Fix:** Classify `APIClientError.server` by status code the way
`OutboxWorker` presumably already does for curation, and give
`SaveOutbox` a permanent-failure path.

### WR-03: `SyncEngine` silently drops a malformed snapshot `save` element with no diagnostic trail

**File:** `playstead-mac/Playstead/Sync/SyncEngine.swift:293-298`

```swift
private static func synthesizedSaveEntry(from payload: JSONValue) -> JournalEntry? {
    guard case .object(let object) = payload, let revisionID = object["revision_id"]?.stringValue else {
        return nil
    }
    return JournalEntry(entityKind: "save", entityID: revisionID, operation: "upsert", payload: payload)
}
```

Used inside `page.save.compactMap(Self.synthesizedSaveEntry(from:))`
(line 200) — any element missing `revision_id` simply vanishes from the
local mirror. The analogous curation function immediately above it
(`synthesizedCurationEntry`, lines 264-286) has an extensive "Known gap
(flagged, not silently worked around)" doc comment explaining exactly
this kind of fallback; `synthesizedSaveEntry` has no equivalent comment
and, more importantly, no logging call anywhere in this file for either
function. Low likelihood in practice (the server is the only producer of
this payload and D-17 says `revision_id` is always present), but if a
future server-side schema change or bug ever omits it, a save revision
would disappear from a device's local mirror during a snapshot bootstrap
with zero trace.

**Fix:** At minimum, log (not silently drop) a snapshot `save` element
that fails to decode its `revision_id`, mirroring the curation path's
documented honesty about its own fallback.

### WR-04 (needs confirmation): No production drain trigger found anywhere for `SaveOutbox` / `SaveConflictResolver`

**File:** `playstead-mac/Playstead/App/PlaysteadApp.swift` (absence, whole
file — the app's composition root)

A repo-wide search for `SaveOutbox(` and `SaveConflictResolver(`
construction found only test files and `Saves/SaveConflictResolver.swift`
itself (which is outside this pass's 22-file scope). `PlaysteadApp.swift`
wires three drain triggers for the curation `Outbox`
(`OutboxDrainTrigger`, lines 444-455: on-enqueue, on-reachability-regained,
on-app-active) but constructs no equivalent trigger, and no `SaveOutbox`
instance at all, anywhere in `AppEnvironment`. If this is accurate, a
"choose this side" / "keep both" resolution is durably recorded locally
(safe — matches `SaveConflictResolver`'s own doc comment that the local
write and the outbox row happen with no network dependency) but may never
actually reach the server in the shipped app, so two devices could each
believe they have separately resolved the same fork and never converge.

I flag this as "needs confirmation" rather than asserting it outright: the
wiring could legitimately live in a file outside this review's 22-file
scope that I have not read (e.g. a dedicated `SaveEnvironment` type), and
the prior 20-file pass may already have covered it.

### WR-05 (minor, needs confirmation): `GameRowView.swift` constructs its own ad hoc `SaveStore`, bypassing the "one shared store" rule `PlaysteadApp.swift` states for every other store

**File:** `playstead-mac/Playstead/App/PlaysteadApp.swift:282-286` (the
stated rule) — the violation itself is in `GameRowView.swift:432`, outside
this pass's scope, but the rule it breaks is documented in an in-scope
file:

`PlaysteadApp.swift`'s own doc comment on `AppEnvironment` states: "The
single-instance rule is load-bearing, not stylistic: all five curation
nouns must read and write *one* store and *one* outbox, or a favorite
added on Home would be invisible on the Favorites shelf." `SyncEngine`
constructs its own private `SaveStore(localStore:)`
(`Sync/SyncEngine.swift:69,81`), and `GameRowView.swift:432` constructs a
second, separate `SaveStore(localStore: environment.localStore)` on the
fly for the launch path. If `SaveStore` is a stateless SQL facade with no
in-memory cache (consistent with what `CatalogueStore`/`CurationStore`
appear to be), multiple instances over the same `LocalStore` are harmless.
I could not fully confirm `SaveStore` holds no cached state from the files
in this pass's scope, so I flag this only as an architectural
inconsistency worth a second look, not a confirmed bug.

## Info

### IN-01: `04-CONTEXT.md`'s locked copy for `result.console_after_choosing` contradicts its own banned-word list; the shipped strings correctly diverge from it

The context doc's locked-copy table (`04-CONTEXT.md:237`) specifies
"Continuing from {Origin}. Your Macs will use this version the next time
they **sync**." — but the same document's vocabulary rules ban "sync"
from every save surface (`04-CONTEXT.md:133`). Both
`shared/save-vocabulary.json:89` and
`Saves/SaveVocabulary.swift:98` correctly use "**connect**" instead,
consistent with each other and with the banned-word rule. This is not a
defect in the implementation — the implementation is the one place this
was fixed — but it means a future audit that diffs the shipped strings
against `04-CONTEXT.md` verbatim will find a false-positive "drift." Worth
a one-line fix to `04-CONTEXT.md` itself so it stops being a trap for the
next reviewer.

### IN-02: `SaveHistorySheet`'s "Done" button is a plain string literal, not sourced from `SaveVocabulary`

**File:** `playstead-mac/Playstead/Saves/SaveHistorySheet.swift:98`

```swift
Button("Done", action: onClose)
```

Every sibling sheet in this file family (`ConflictComparisonSheet`,
`OnlyCopyInterruptiveSheet`) sources its dismiss button from
`SaveVocabulary` (`compareDismiss`). This one is hardcoded. Today's value
happens to match `SaveVocabulary` has no independent "Save history dismiss"
key at all, so there's nothing to drift against yet — but it's an
inconsistency with the pattern the rest of the file family follows, and
if a future locked-copy revision changes "Done" elsewhere it would not
propagate here.

## Verified clean

The following invariants were actively checked against the code (not
assumed) and hold as far as this pass could determine:

- **D-40 button semantics inside the sheet itself:** `OnlyCopyInterruptiveSheet`'s
  default action (`.keyboardShortcut(.defaultAction)`, `.defaultFocus`) is
  bound to "Export saves…", never to "Remove anyway"; the destructive
  button uses `role: .destructive` and carries no default styling; the
  copy never says "are you sure" (`Saves/OnlyCopyInterruptiveSheet.swift:70-84`).
  The button's *effect* being a no-op is CR-01 above; its *positioning
  and semantics* are correct.
- **D-51/D-55 no-ranking, one-sentence-per-side:** `ConflictComparisonSheet`
  renders `sides` in caller-supplied order with no highlighting,
  pre-selection, or color distinction anywhere in the view; each side's
  individual `Text` elements are `accessibilityHidden(true)` and combined
  into exactly one `accessibleSentence` on the containing element
  (`Saves/ConflictComparisonSheet.swift:143-245`).
- **D-49 no-undo:** the non-chosen side keeps a live, permanently
  re-clickable "Continue from this one" button; no undo/reversal control
  exists anywhere in the sheet.
- **D-35/D-36/D-38 orthogonal-axis model:** `SaveStateModel` has no
  collapsing status enum anywhere; `SaveRollup.rollup` reads only the
  newest revision's durability (never `min()` across revisions);
  `SaveStateModel.isConflicted` derives divergence from a head-ID set,
  never a stored per-revision field (`Saves/SaveStateModel.swift`,
  `Saves/SaveRollup.swift`).
- **D-42 widened save-directory check:** `ReadinessEngine.evaluateSaveDirectory()`
  genuinely performs a write-then-atomic-`replaceItemAt` probe against a
  fixed target name (not merely `isWritableFile`), and a `defer` block
  removes both probe artifacts on every exit path, blocking or not
  (`Readiness/ReadinessEngine.swift:285-335`).
- **D-37 Save row cannot block:** `ReadinessEngine.evaluateSaveState()`'s
  switch has no path returning `.blocked` for any `SaveReadinessCase`,
  including `.twoVersions` (`Readiness/ReadinessEngine.swift:345-373`).
  (The row's *content* never actually varying in production is CR-04
  above; its *inability to block* is structurally correct.)
- **Zero-network launch-path proof is real, not a stub:** `RecordingURLProtocol`
  globally registers via `URLProtocol.registerClass`, intercepts any
  `http`/`https` request from any session configuration, and fails every
  one — it is not scoped to only `APIClient`'s own session
  (`UITesting/RecordingURLProtocol.swift`).
- **`SyncEngine` never wipes local save state on a snapshot reset:**
  `bootstrapFromSnapshot()` clears `catalogueStore`/`curationStore` but
  never `saveStore`, exactly as documented, and only commits the
  transaction after every page of the snapshot has been fetched
  successfully — a failed fetch never touches the local store at all
  (`Sync/SyncEngine.swift:180-220`).
- **`APIClient` never leaks the bearer token** in a log line or URL, and
  its problem+json decoding degrades safely (`try?`, falls back to a
  synthetic `"unknown"` code) rather than crashing on a malformed error
  body (`Net/APIClient.swift:206-211`).
- **`SaveOutbox`'s idempotency key is stable across retries** — minted once
  at `enqueue` and reused verbatim by every later `drainOnce` attempt of
  the same entry (`Sync/Outbox.swift:304`, `:383`). This is evidence
  against WR-04 (the SaveUploadLane idempotency concern noted in this
  phase's known-issues list) being a systemic pattern in this codebase's
  outbox designs — `SaveOutbox` gets this right, which narrows that open
  question toward `SaveUploadLane` specifically rather than the outbox
  architecture generally.

---

_Reviewed: 2026-09-04_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
