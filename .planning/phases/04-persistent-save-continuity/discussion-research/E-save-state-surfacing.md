# Area E — Save State Surfacing vs. the Frozen One-Status-Slot Ladder (SAVE-02)

**Question:** where and how the six SAVE-02 states become visible, without breaking
P3 D-13's frozen single-status-slot card contract and without lying.

**Verified against source, not memory:** `playstead-mac/Playstead/Design/StatusToken.swift`
(8 hex literals, `allValues` asserted disjoint from `SystemAccent`),
`Library/StatusSlotView.swift` (`LibraryStatus` — 7 cases, `rank` 1–6, `glyphIdentifier`,
`listViewLabel`, `accessibleName(title:)`, `highestPriority(among:)`),
`Design/DesignTokens.swift` (280×158 fixed card, 44pt targets, 4-role type scale,
2 weights), `Design/MotionPreference.swift` (`morphAndTransitionDuration`, and
`ProgressFillState` deliberately independent of it), `Design/AccessibilityIdentifiers.swift`
(20 surfaces, 21 controls, `allStaticIdentifiers`), `Readiness/ReadinessCheck.swift`
(`ReadinessCheckKind` — six kinds **including `saveDirectory`**),
`Readiness/ReadinessSheetView.swift`, `03-UI-SPEC.md`, `EXPERIENCE-ETHOS.md`,
`playstead-server/lib/playstead/attention/reason.ex` (nine **frozen** reasons, all
import/recognition-scoped — **no save reason exists**), `playstead_web/live/` (no
saves LiveView exists).

**Two grep findings that change the answer:**

1. `ReadinessCheckKind` **already has `saveDirectory`**, and EXPERIENCE-ETHOS's
   "Ready to Play" contract **already specifies a Save row**: *"Save: current, pending
   backup, older remote revision, or conflict."* The per-game save surface is not a
   new invention I have to justify — it is a slot the shipped design already cut and
   Phase 3 left stubbed. That decides Q3 almost entirely.
2. `Playstead.Attention.Reason` is a **frozen nine-reason vocabulary about asset
   recognition** (`missing_member`, `quarantined`, `ambiguous_recognition`, …).
   A save conflict is not in it. So "make conflicts show up as rank-1 attention" is
   *not* free — either the attention context grows a save-shaped reason (widening a
   deliberately narrow bounded context) or the card's rank-1 derivation ORs in a
   second, independent source. I choose the latter and defend it in D-E5.

---

## 0. Role lenses actually applied

Applied: **UI/UX + creative direction**, **microcopy**, **accessibility**,
**product / first-adopter (JTBD)**, **performance/resource**, **domain modeller**
(the three-axis model is a ubiquitous-language decision, not a layout one),
**test/verification engineer**, **QA adversarial**, **SRE/operator** (alert-noise
economics of a permanently-syncing surface).

Genuinely not applicable here and deliberately skipped: filesystem/durability
engineer, Elixir/OTP transaction idiom, Swift process-lifecycle — those are areas
A/B/D/F. I consume their outputs as assumptions and flag every one in §9.

---

## 1. The reframe that dissolves the collision

SAVE-02 says: *"A user can see whether **a save revision** is local-only, queued,
uploaded, current, restored, or in conflict…"*

D-13 froze the status slot on **the library card**. A library card is a **game**, not
a revision. **SAVE-02 is a per-revision requirement and the card is a per-game
object; they are not the same subject and the requirement was never addressed to the
card.** Every attempt to satisfy SAVE-02 in the card's one slot is a category error
that produces exactly the "generic synced label hiding the distinction" the
requirement forbids — because collapsing N revisions × 3 axes into 1 badge *is* the
generic label.

So the card is not the venue. The card's only two obligations are:

- **Never lie** — it must not imply save safety it cannot substantiate. It currently
  says nothing about saves, which is honest, and I keep it that way for five of six
  states.
- **Route** — when a save state genuinely requires a human decision, the card must
  be the thing that gets you there, because the card is where a player's eye already
  is.

That yields option (c) from the prompt, in its narrowest possible form: **exactly one
save condition reaches the card, and it reaches it through the ladder's *existing*
rank-1 state with its *existing* glyph, shape, colour, label and accessible-name
sentence — zero new ranks, zero new tokens, zero copy edits, zero snapshot rebaselines.**

---

## 2. The three axes (Q2) — the honest information architecture

The six state names are not one dimension. Modelled properly they are three, and the
whole design follows from separating them:

| Axis | States | Cardinality | Mutability | Subject |
|---|---|---|---|---|
| **Durability** — has this version left this Mac? | `local-only` → `queued` → `uploaded` | Exactly one per revision; **monotone** (never regresses) | Changes over time, resolves itself | `(revision)` |
| **Position** — which version does play continue from? | `current` | Exactly one *per (game, device)* | Changes on capture and on restore | `(revision, device)` |
| **Provenance** — where did this version come from? | `captured` (implicit default) / `restored` | Exactly one per revision; **immutable** | Never changes; it is a historical fact | `(revision)` |
| **Lineage** — do two versions descend from one base? | `conflicted` | A property of a *set* of ≥2 revisions, not of one | Changes only by human decision | `(revision-set)` |

Four findings fall out, and they are the substance of this area:

**(a) `restored` is not a status, it is provenance.** It never decays, never
resolves, never competes. It is a permanent origin fact — "this version arrived here
from somewhere else on 3 Sep." Rendering it as a status chip alongside `uploaded`
would imply it can expire. It belongs on the row's origin line, next to "From this
Mac" / "From Kitchen Mac".

**(b) `current` is device-scoped, not global.** "Current" means *these bytes are in
this Mac's save directory and the next launch continues from them*. That is a fact
about a `(revision, device)` pair. The server cannot know it for a device that has
not reported in, and it can be simultaneously true of two different revisions on two
different devices — that is precisely the pre-conflict condition. **The LiveView
console must therefore never render a global "current".** (§6.) This is the single
most likely place for a well-meaning implementation to start lying.

**(c) `conflicted` is a property of a set.** Attaching it to one row forces the
question "which of the two is *the* conflicted one?", which has no answer. It renders
as a **fork in the rail** joining two rows, plus a group banner — never as a lone chip.

**(d) A row can be truthfully `uploaded` + `current` + `restored` simultaneously.**
That is the empirical proof that one badge cannot carry this. Three axes → three
independent visual channels on the row (trailing chip / leading rail marker /
secondary origin line). Nothing overlaps, nothing has to win a priority fight, and
there is **no ladder** inside the save surface at all. The absence of a second
priority ladder is a deliberate design decision, not an omission — priority ladders
exist to fit N facts into 1 slot, and the save surface has enough slots.

### The game-level rollup (Q2's crux: 40 revisions, 39 uploaded, 1 local-only)

> **Locked rule: the game-level save summary is the durability of the *newest*
> revision, scoped in the sentence itself. It is never a `min()` over all revisions,
> and it is never called "backed up".**

Three arguments, in priority order:

1. **A `min()` rollup is a permanent false alarm.** Under any retention scheme
   (area D) some old revision will be pruned-but-locally-present, or captured during
   an offline session and later superseded. A `min()` rollup paints the library
   permanently amber for a system that is working exactly as designed. EXPERIENCE-ETHOS
   #3 forbids that; it is also the well-documented Dropbox/iCloud failure mode where
   a status icon that is never green stops being read at all.
2. **A `max()`/newest rollup is a lie only if the sentence over-claims.** So the
   sentence never claims more than it knows: **"Latest save is on your server"**, not
   "This game's saves are safe". Scoping the claim is what makes newest-wins honest.
   This is the direct application of EXPERIENCE-ETHOS #16 — *never show a reassuring
   green "safe" state merely because one disk currently contains the bytes.*
3. **Older unprotected versions still get said out loud — quietly, in one place.**
   Whenever `count(revisions on this Mac and nowhere else, excluding the newest) > 0`,
   the save section (not the card, not the sidebar) carries one muted line:
   **"{N} earlier versions are only on this Mac."** No colour, no glyph, no badge, no
   count anywhere it could become a nag.

So for 39 uploaded + 1 local-only: if the local-only one is the newest → header reads
*"Latest save is only on this Mac"*; if it is an old one → header reads *"Latest save
is on your server"* plus the muted *"1 earlier version is only on this Mac."* Both
are literally true and neither is alarming. **The rollup is a scoped claim about one
revision plus an unscoped count, never a fused verdict about a game.**

Corollary, stated so nobody re-derives it wrong later: **"this game's saves" is not a
thing that has a state.** Any code that computes `SaveStatus(for: game) -> enum` is
the SAVE-02 violation wearing a type signature.

---

## 3. Does save state enter the card's ladder? (Q1)

**Yes — exactly once, as the ladder's *existing* rank-1 `needsAttention`, for
`conflicted` only.**

Read against the actual `LibraryStatus.rank` (1 attention, 2 missingDependency,
3 downloading, 4 queued, 5 pinned/verified, 6 serverOnly):

- A conflict is, definitionally, *a decision only a human can make, with data at
  risk until they make it* — the exact predicate rank 1 exists to express. It
  outranks a missing BIOS for the same reason PROJECT.md ranks data safety above
  reliable play.
- Reusing rank 1 means: **no new `LibraryStatus` case**, no eighth glyph, no ninth
  `StatusToken` hex, no change to `listViewLabel`, no change to
  `accessibleName(title:)`, no change to `highestPriority(among:)`, no change to the
  seven-status equality assertion in `StatusLadderTests`, and **no snapshot
  rebaseline** (03.5 D-17 makes rebaselining a manual, reviewed, and expensive act —
  a design that avoids triggering it is a better design).
- The card keeps saying "Needs attention" / *"{title} needs your attention."* The
  card was always a router, not an explainer; the conflict's identity is one
  activation away in the save section. This is *why* the ladder was built with a
  generic top rank.
- The other five states never touch the card. A card that changed appearance every
  ~24 s of play (area A's capture cadence) would be strobing, and the durability
  axis is self-resolving — showing it on the card would advertise a problem the
  system is already fixing.

**What this costs, honestly:** `.needsAttention` becomes overloaded — a card showing
it might mean "unidentified ROM" or "two save versions", and a user with several
attention cards cannot triage from the grid alone. Accepted, with the mitigation that
the list view and the accessible name are *not* where triage happens; the Attention
inbox and the save section are. I would not accept this if attention were common; per
03-UI-SPEC it is an exception state by construction.

---

## 4. The surface (Q3): "Save history", a section — not a sidebar noun

### IA placement

**No new top-level sidebar entry.** P3 D-14's eight-step order (Home, Continue,
Favorites, Collections, Queue, Recent, Systems, Unidentified) is asserted literally by
`03-05`/`03-06` acceptance criteria, mirrored on the console, and 03-UI-SPEC calls a
regression there "a contract violation, not a style nit." Beyond the mechanical cost:
that list is **six curated nouns a user chose plus two derived groupings**. "Saves" is
neither — a user does not browse saves the way they browse Favorites; they arrive at
saves *from a game*, always. A global Saves view is SEED-012's memory-card explorer,
which is explicitly future work.

**Placement (locked):**

1. **Readiness sheet — one Save row.** `ReadinessCheckKind.saveDirectory` exists and
   EXPERIENCE-ETHOS already specifies this row's four values. Phase 4 makes it real.
   This is the pre-play glance: *"is my progress here, and is it safe?"*
2. **`SaveHistoryView` — a sheet opened from that row's "Save history…" control**, and
   from the conflict banner, and from the game's context menu. A sheet, not a new
   window and not a pane: it inherits the readiness sheet's already-tested
   keyboard/focus/Escape/Done chrome (03.5 D-20's toolbar-sheet contract) instead of
   inventing a second, untested one.

Adding `ReadinessCheckKind.saveContinuity` as a **seventh** kind vs. widening
`saveDirectory`: widen `saveDirectory`'s *finding text* is wrong (the check's identity
is "can I write saves here"). **Add `saveContinuity` as a seventh kind**, ordered last;
its outcome is `.ready` / `.warning` / `.blocked(conflict)`. This is additive to a
`CaseIterable` enum whose order is documented as the tie-break order — cheap and
reversible.

### Is a timeline the right form? Interrogated — and amended

The naive answer is a reverse-chronological list of revisions. **Rejected.** With
area A's capture cadence, a 3-hour session produces tens to hundreds of near-identical
32 KB revisions. A flat list of "4:12 PM, 4:12 PM, 4:13 PM…" is not history; it is a
log, and it buries the two rows that matter (where you are, and the fork). It also
loses the actual job — nobody remembers *a revision*; they remember *an evening*.

**Locked form: a session-grouped timeline.** Default rows are **play sessions**
(a contiguous run of the adapter for one title); a session expands to its versions.

- Session row: **"Yesterday evening · 2 hr 10 min · 14 versions"**, trailing chip =
  the session's durability using the same newest-scoped rule.
- Auto-expanded by default, and only: the session containing **You are here**, any
  session containing a **conflict head**, and the newest session if its newest
  revision is not on the server. Everything else collapsed.
- Solves noise, performance, and JTBD in one move, and gives SEED-001 the natural
  place for a pinned/named revision to **float out of its session group** to a
  "Kept versions" section at the top.

Prior art: Time Machine's date rail (browse by *when*, not by file version), 1Password
item history, Obsidian version history's timestamp list, git clients' commit graph for
the fork rail. Ludusavi's per-backup **lock** is the direct model for SEED-001.

### Row anatomy — three zones, deliberately isomorphic to the card's three zones

Internal consistency is a pillar; a save row that reads like a card row is learned once.

```
┌──────────────────────────────────────────────────────────────────────┐
│ ▶ │  Today, 4:12 PM                             │  ⬆ Waiting to copy │
│ │ │  From this Mac                              │                    │
│ ├─┐│                                            │                    │
│ │ ││  Today, 4:09 PM                            │  ▤ On your server  │
│ │ ││  From Kitchen Mac · Separate version       │                    │
└──────────────────────────────────────────────────────────────────────┘
  ^rail          ^primary (Heading 20/600 + Label 14/400 muted)   ^durability chip
```

1. **Leading rail (fixed 28 pt):** the **You are here** playhead marker, and the fork
   rail when a session contains conflicting heads. Reserved width even when empty —
   SEED-006's screenshot thumbnail lands here later without re-laying-out the row.
2. **Primary:** time first (Heading role — the primary key a human searches by),
   second line origin + provenance (Label 14/400, `textMuted`): "From this Mac",
   "From Kitchen Mac", "Restored here on 3 Sep", "Separate version".
3. **Trailing:** the durability chip — SF Symbol + shape + text, never colour alone.

**Typographic-first (D-12) holds:** no fake thumbnails, no per-revision generated
imagery, no hash colours. Identity is carried by the system accent already on the
sheet header and by type hierarchy. The save surface adds **zero** new type roles,
**zero** new weights, and (see below) **zero** new colours.

### Colour: the save vocabulary introduces no new hues at all

D-13's premise is that two disjoint colour vocabularies (identity, status) teach the
user something. A **third** vocabulary would destroy that premise faster than any
individual hue choice could justify.

> **Locked: the save vocabulary is monochrome — `textMuted` glyph + text + shape on
> the default surface — with exactly one exception: `Separate version` and the
> conflict banner use `StatusToken.attention` (`#F59E0B`), the colour the card is
> already showing for the same fact.** Zero new hex literals. Assertable:
> `SaveVocabularyTests` asserts the save vocabulary declares no colour literal outside
> `{StatusToken.attention, DesignTokens.textMuted, DesignTokens.textPrimary}`.

This is a real trade: durability chips are less scannable in grey than in green/amber.
Accepted deliberately — **there is no green in this design anywhere**, because a green
save chip is precisely the "reassuring green safe state" EXPERIENCE-ETHOS #16 bans, and
because green would collide semantically with `verified` (#16A34A) which means
*game bytes are on this disk* — nearly the opposite claim.

### Glyphs — disjoint from the ladder by assertion

| Save state | SF Symbol | Heroicon | Shape |
|---|---|---|---|
| Only on this Mac | `laptopcomputer` | `computer-desktop` | rounded-rect chip, outline |
| Waiting to copy | `arrow.up.circle` | `arrow-up-circle` | circle, outline |
| On your server | `server.rack` | `server-stack` | rounded-rect chip, filled |
| You are here | `arrowtriangle.right.fill` | `play` (solid) | rail playhead, no chip |
| Restored here | `arrow.uturn.backward.circle` | `arrow-uturn-left` | inline glyph on the origin line |
| Separate version | `arrow.triangle.branch` | `arrows-right-left` | fork rail + inline glyph |

Deliberately **not** `icloud` (ladder rank 6), **not** `clock` (ladder rank 4),
**not** `checkmark.circle.fill` (rank 5) — a save row must never wear a ladder glyph.
Asserted: `Set(SaveState.glyphIdentifiers) ∩ Set(LibraryStatus.allGlyphIdentifiers) == []`.

### Motion (D-16)

| Interaction | Behaviour | Reduced motion |
|---|---|---|
| Durability chip transition (only on this Mac → waiting → on your server) | in-place crossfade, `MotionPreference.morphAndTransitionDuration` | instant swap |
| **You are here** marker moving after a capture or restore | rail marker slides to the new row, ~150 ms — *this is the one animation that earns its place*: it is the only signal that "what you continue from" changed | instant reposition, same end state |
| Session group expand/collapse | native disclosure | native |
| A new revision arriving while the sheet is open | row inserts, list never scroll-jumps, **You are here** never moves without the marker animation | instant |

Prohibited, matching 03-UI-SPEC: no ambient motion, no staggered fly-in, **no
skeletons** (the save history is local SQLite; a skeleton would be a placeholder for
nothing), no spinner on the durability chip (a spinner implies foreground work the
user is waiting on; they are not).

---

## 5. Microcopy — the locked strings (Q5)

**Locked user-facing nouns:** a save is a **save**; a revision is a **version**; the
timeline is **Save history**; the server is **your server** (never "the cloud", never
"backed up" — EXPERIENCE-ETHOS #16 reserves "backup" for PORT-03's independent
verified copy, and calling an upload a backup would be the single most consequential
lie available in this area).

**Banned from every save surface:** sha256/digest, cursor, journal, parent, base,
head, revision, blob, CAS, idempotency key, LWW, merge, HEAD, ancestor, hash.
(Available behind one "Details" disclosure per row for support — value shown as a
short prefix, copyable, never in the row itself.)

### The six states

| # | Axis | Label (chip / marker) | One-line explainer | VoiceOver sentence |
|---|---|---|---|---|
| 1 | durability | **Only on this Mac** | "This version hasn't reached your server yet. If this Mac is lost, so is this progress." | "Saved {time}. Only on this Mac — it has not reached your server yet." |
| 2 | durability | **Waiting to copy** | "Your server isn't reachable right now. This copies over on its own as soon as it is." | "Saved {time}. Waiting to copy to your server. It will copy on its own." |
| 3 | durability | **On your server** | "Stored on your server as well as on this Mac." | "Saved {time}. On your server and on this Mac." |
| 4 | position | **You are here** | "{title} continues from this version." | "You are here. {title} continues from this version, saved {time}." |
| 5 | provenance | **Restored here {date}** | "You brought this version back on {date}, from {device}." | "Restored here on {date}, from {device}." |
| 6 | lineage | **Separate version** | "This version and the one from {device} both continue from {time}. Neither has been changed." | "Separate version, saved {time} on {device}. It has not been merged with the version from {other device}. Both are kept." |

Why each word: "Only on this Mac" (not "local-only") names the machine the player is
touching. "Waiting to copy" (not "queued") avoids colliding with the ladder's
download-queued and states the object of the wait. "On your server" (not "uploaded")
drops the backend verb and keeps custody tangible per EXPERIENCE-ETHOS #2; the noun
matches the ladder's existing "On server" so a user learns one place-word, and the
subject (a save version vs. game bytes) is unambiguous from context — flagged as a
small accepted overload. "You are here" (not "current") is a map/Time-Machine
metaphor a player already owns, and it is the phrase that answers the question they
actually have. "Separate version" (not "conflict") refuses to frame a normal
two-machine outcome as an error; the word "conflict" appears nowhere user-facing.

### Section header — the game-level rollup sentences (exhaustive, in order)

| Condition (first match wins) | Header |
|---|---|
| any conflict head exists | **"Two versions of this save."** |
| newest revision only on this Mac | **"Latest save is only on this Mac."** |
| newest revision waiting to copy | **"Latest save is waiting to copy to your server."** |
| newest revision on server | **"Latest save is on your server."** |
| no revisions yet | **"No saves yet."** — body: "Play {title} and your progress will show up here." |

Second, muted line, shown only when the count > 0 and never alone:
**"{N} earlier versions are only on this Mac."** (singular: "1 earlier version is only
on this Mac.")

One-time section footnote, once per sheet, never a banner:
**"Your server holds these versions. Backing up the server itself is separate."**

### Readiness sheet — the Save row (the four EXPERIENCE-ETHOS values, made literal)

| Outcome | Finding |
|---|---|
| ready | "Your progress is here and on your server." |
| ready (offline, expected) | "Your progress is here. It'll copy to your server when it's reachable." |
| warning | "This Mac has your progress, but your server hasn't got it yet." |
| warning (server has newer) | "Your server has newer progress, from {device}, {relative time}. Playing now continues from what's on this Mac." |
| blocked | "Two versions of this save need your decision before playing." — remedy control: **"Review versions…"** (hands off to area G) |

### The danger case (area D): a revision that exists on exactly one device

This is where quiet-by-default is most tempting and most wrong, so the copy is
tiered by *what the user is about to do*, not by how long it has been true.

**Ambient (always):** the chip. **"Only on this Mac"**. That is all.

**Visible (in-context, non-modal, no colour):** the section header sentence, plus in
the readiness sheet: *"This Mac has your progress, but your server hasn't got it
yet."* Never in the grid, never a badge, never a notification.

**Escalated — only when the system cannot fix it itself** (auth revoked, capability
skew, server refusal, compat gate rejection). Persistent inline panel in the save
section and the readiness sheet:

> **"Your progress can't reach your server."**
> "The last {N} versions of {title} are only on this Mac, and this won't fix itself:
> {reason}. Your progress is safe here in the meantime."
> Controls: **"Fix this"** (routes to the remedy) · **"Export saves…"** · **"What's
> stored where?"**

**Interruptive — modal, and only at the moment of a destructive intent**
(remove local copy, quota eviction, unpair this device, sign out, delete game):

> **"This is the only copy of your progress."**
> "{N} versions of {title} are only on this Mac and nowhere else. Continuing removes
> them for good."
> Buttons: **"Export saves…"** (default) · **"Cancel"** · **"Remove anyway"**
> (destructive styling, `DesignTokens.destructive`, never the default button)

Note the modal never says "are you sure" and never blames; it states the fact, offers
the escape hatch first, and keeps the destructive path available (EXPERIENCE-ETHOS #4,
#12 — no dark patterns, and no fake-guard-rail that just trains people to click through).

---

## 6. LiveView console parity (Q4): full for inspection, deliberately partial for action

Per P3 D-11 the console ships parity through the **same context functions**. Here
parity must be **full in vocabulary and ordering, partial in verbs** — and the
partiality is a truth constraint, not a scope cut.

| Capability | Mac | Console | Why |
|---|---|---|---|
| See a game's save history, session-grouped | ✅ | ✅ | Same context function, same order, same strings |
| Durability chips (3 states) | ✅ | ✅ | Server-side truth; identical |
| Provenance (`Restored here`) | ✅ | ✅ | Immutable historical fact |
| **You are here** | ✅ (this Mac) | ⚠️ **per-device only** | `current` is a `(revision, device)` fact — see below |
| Export / download exact bytes of one version | ✅ | ✅ | PORT-01; the console is the natural place |
| Resolve a conflict (choose a side / keep both) | ✅ | ✅ | A lineage decision, no emulator needed — area G owns the flow |
| **Capture** a save | ✅ | ❌ | No adapter, no save directory |
| **Restore into play** | ✅ | ❌ | There is nothing to restore *into* |
| Cross-device view: every device's saves for a title, side by side | ⚠️ own device emphasised | ✅ **the console's superpower** | The server is the only vantage point that sees all devices |

**The console's honest role: the vantage point and the archive** — inspect everything
across every device, export exact bytes, and settle a conflict. It never pretends to
be a place you play from.

**The truth constraint, stated as a rule the implementation must obey:** the console
renders **"Playing from this on {device}"**, per device, with **"as of {last check-in
time}"** whenever the device has not reported since the revision landed. It **must
never** render a bare "Current" or a global playhead. A global playhead on the console
would be a first-class lie in exactly the SAVE-02 sense — it would assert one truth
where two devices legitimately hold two. Corresponding negative test named in §10.

**Shared spec artifact (P3 D-17):** the vocabulary is authored once in
`.planning/phases/04-persistent-save-continuity/04-UI-SPEC.md` (a "Save Vocabulary &
Axes" table extending, never restating, 03-UI-SPEC), and mirrored mechanically as one
checked-in fixture, `shared/save-vocabulary.json`, containing for each state:
`id`, `axis`, `label`, `explainer`, `voiceover_template`, `sf_symbol`, `heroicon`,
`shape`, `color_token`. Both clients read it **as a test resource, not at runtime** —
runtime reads would mean a data file could change shipped copy, and a corrupt/missing
file would silently blank the UI. `Playstead.Saves.Vocabulary` (Elixir literals) and
`SaveState` (Swift literals) each assert equality against it. Drift becomes a red test
on whichever side moved, in the same CI run — which is the only mechanism that has
ever actually stopped SwiftUI/HEEx drift.

---

## 7. Quiet by default vs. honest (Q6) — the central judgement

**The rule (locked): escalate on undecidability, never on duration.**

A save UI that escalates on *time* ("still not uploaded after 10 minutes") or on
*count* ("3 versions unsynced") turns an offline-first product into a permanent
low-grade alarm — because EXPERIENCE-ETHOS #7 declares offline browsing and offline
play the **normal, intended state**, and area A's capture cadence means a two-hour
offline session legitimately produces a large pile of local-only versions. Escalating
that is escalating success.

So the trigger is not "how bad is it" but **"can the system still fix this on its
own?"**:

| Tier | Trigger | Surface | Colour |
|---|---|---|---|
| **Ambient** (always, zero attention cost) | any durability state | chips inside `SaveHistoryView` only | none (`textMuted`) |
| **Visible** (in-context sentence, non-modal, never in the grid) | the newest revision is not on the server; or the server holds newer work from another device | save section header + readiness sheet Save row | none |
| **Escalated** (persistent panel; still not modal) | the sync failure is **non-retryable without a decision** — credential revoked, capability skew with a remedy (P1 D-19), server refusal, compat gate rejection (area C) | save section + readiness sheet | none, or `attention` if it also blocks play |
| **Interruptive** (rank-1 on the card **and** a modal at the point of action) | **exactly two:** (1) a conflict exists; (2) the user initiated an action that destroys the only copy of a version | card status slot (conflict only) + modal at the action | `StatusToken.attention` |

**Explicitly does *not* escalate, ever:** an offline queue; a slow or retrying upload;
an old local-only version; a session that produced many versions; a device that has not
checked in; a pruned version. These are the system working.

**Adversarial check on the rule:** "credential revoked at 9 pm, player plays until
midnight, never opens the save sheet, Mac dies" — the escalated tier is a panel, not a
notification, so they may never see it. **Accepted with a mitigation:** the escalated
tier *does* raise the card to rank-1 attention **when the same condition also blocks
play** (which auth revocation and capability skew do, via the readiness engine) — so
the escalation reaches the grid through the existing, already-tested channel rather
than a save-specific one. A non-play-blocking non-retryable failure remains
panel-only, and that is a **recorded residual risk (R3)**, not a solved problem. I
will not add a notification: PROJECT.md ranks low-administration quiet at 3, and a
notification here would fire on every laptop that closes its lid on a coffee-shop
network.

---

## 8. Design pillars (Q7, Q8) — honoured, and traded

**Honoured, each with its mechanism:**

- **Accessibility (WCAG 1.4.1, non-colour-only):** every save state is glyph +
  shape + **text** simultaneously, in every view — there is no compact/icon-only mode
  for save chips at all, which is a stronger guarantee than the card's (the card's
  grid view is glyph+shape only, with text in list view). Since the save vocabulary is
  nearly monochrome, **colour carries no save information at all** — the strongest
  possible form of 1.4.1 compliance: not "not colour-only" but "not colour at all".
- **VoiceOver full sentences (P3 D-13):** every state above has a locked sentence; a
  row's composed name is `"{time}. {provenance}. {durability}."` with the playhead
  prepended when present. Fork rails, chip shapes, and the rail column are
  `.accessibilityHidden(true)` — their meaning is already in the sentence.
- **Keyboard parity (03.5 D-19/D-21 — the `.onMove` lesson):** every save action has
  an ordinary keyboard path *and a visible control*, not just a gesture. Specifically:
  session expand/collapse (disclosure, Space/Right/Left), row selection (arrows),
  **"Restore this version…"**, **"Export this version…"**, **"Details"**, and — the
  one that would repeat 03.5 D-21's mistake if missed — **conflict resolution: two
  visible, focusable "Keep this one" buttons, one per head, plus "Keep both"**, never
  a swipe, drag, or contextual-menu-only path. Sheet chrome inherits the readiness
  sheet's Escape/Done/focus-restore contract (03.5 D-20).
- **Dynamic Type / long titles / Unicode:** the save sheet has **no fixed-height
  constraint of the card's kind** — the card's 280×158 is fixed because a 500-item
  grid demands it; a save row is a list row and grows. Rows use fixed *estimated*
  height for virtualization, not clamped height. Device names are user-supplied and
  therefore truncate with tail truncation at a locked max width; the VoiceOver
  sentence uses the untruncated name.
- **Light/dark/system:** the sheet inherits `preferredColorScheme(.dark)` +
  `DesignTokens.background` like the readiness sheet — no new appearance surface, no
  hover/focus divergence (there are no hover-only affordances; everything is visible).
- **Internal consistency:** zero new type roles, zero new weights, zero new colour
  literals, zero new ladder ranks, zero card copy changes, one new sheet reusing an
  existing sheet's chrome, one new `ReadinessCheckKind`.
- **Performance (D-16, interactive < 1 s cold):** session grouping caps default row
  count at tens; durability is read from local SQLite columns, **never** derived by
  hashing or stat-ing files at render time; `List`/`LazyVStack` virtualization; no
  per-row byte access (SEED-006 thumbnails, when they come, load lazily into the
  reserved rail width). A 500-session, 5,000-revision title renders as ~500 rows,
  virtualized.
- **Offline-first:** every save surface renders fully from the local read model with
  zero network calls, including the readiness Save row — CACH-04's zero-network
  preflight rule is preserved because the Save row consults only local state.
  "Waiting to copy" is a *normal* rendering, not an error rendering.
- **Honesty/explainability:** the scoped-claim rollup, the no-green rule, the
  per-device console playhead, the "backup ≠ your server" footnote.

**Trades made, resolved by PROJECT.md's ranked list:**

| Conflict | Resolution | Rank invoked |
|---|---|---|
| Full per-revision durability on the card (honesty) vs. quiet grid | Quiet grid; honesty relocated to a surface that can carry it truthfully | 3 over a false reading of 1 — a strobing card *reduces* comprehension |
| `min()` rollup ("safest") vs. `newest`-scoped rollup | Newest, scoped in the sentence, + muted count | 1 and 3 — a permanently-amber UI is not data safety, it is noise |
| Green "safe" chip (scannability) vs. monochrome | Monochrome | 1 over 4/5 — EXPERIENCE-ETHOS #16 is explicit |
| A "Saves" sidebar noun (discoverability) vs. frozen IA | Frozen IA + per-game section | 3 (internal consistency) over 6 (breadth) |
| Notify on non-retryable sync failure (safety) vs. low-administration quiet | No notification; card escalation only when play is also blocked; residual risk recorded | 3 over 1, **the one place I ranked against data safety** — recorded as R3, not hidden |
| Console action parity (consistency) vs. capability truth | Partial verbs, full vocabulary | 1 — a console "Restore" button that cannot restore is a lie |

---

## 9. JTBD (Q9)

**Job 1 — "Did my progress make it off this machine?"**
*Who:* a player who just finished a session, or is about to close a laptop / travel /
wipe a Mac. *Where/when:* right after playing, or at the moment of a destructive
action. *What they need:* one sentence about the newest version, and an honest count
of anything else stranded. *What they get back:* the section header + the muted count,
and — at the destructive moment — the modal with **Export saves…** offered first.
*Domain:* noun `save version`; verb `copy to your server`; event `version reached your server`.

**Job 2 — "I want to go back to before I sold the sword."**
*Who:* a player who made a mistake 20 minutes ago. *What they need:* to find a moment
in *time*, not a file — and to be told what going back costs. *What they get:*
session-grouped history, **You are here** as the anchor to navigate relative to, and
**"Restore this version…"**. *Domain:* noun `session`; verb `restore`; event
`restored here` (which is why provenance is permanent — the restore must remain
visible in the history afterwards, or the next question, "wait, what happened here?",
has no answer).
**Critical honesty point owned by this area:** restoring must not silently orphan the
version you were on. The restore confirmation says: **"Continue {title} from {time}?"**
— "Your current progress stays in this list — nothing is thrown away." (Mechanism is
area B/G's; this is the copy contract.)

**Job 3 — "Two machines disagree."**
*Who:* a two-Mac household. *What they need:* to be told nothing was lost, before
anything else. *What they get:* the card's rank-1 attention → the banner **"Two
versions of this save."** → **"Review versions…"**.
**→ HANDOFF TO AREA G. I design the entry point and the vocabulary; area G designs
the resolution flow.** My contract to area G, stated so the seam is explicit: (i) the
entry point is a rank-1 card attention plus a banner in the save section; (ii) the
word "conflict" never appears user-facing — the heads are "separate versions";
(iii) both heads stay visible in the history *after* resolution, with their provenance
intact; (iv) resolution must offer **Keep both** as a first-class option, not a
fallback; (v) every choice is reachable by keyboard through visible controls.
**COLLISION FLAG:** if area G lands on a modal blocking dialog at launch time
(the Steam Cloud shape), it collides with my escalation ladder, which puts conflict
resolution in a sheet you enter deliberately. My position: launch-time modal is the
documented Steam footgun (users pick under time pressure to get into their game, and
pick wrong) — but area G owns the call, and I will conform.

---

## 10. Prior art

| System | Copy this | Documented footgun to avoid | Source |
|---|---|---|---|
| **Steam Cloud** | It refuses to auto-pick; it shows a conflict and stops | The dialog fires **at launch**, offering "upload local"/"download cloud" with timestamps only — a destructive choice under time pressure, with no third "keep both" option and repeated-dialog/save-reversion reports. The canonical example of *right instinct, wrong moment, wrong options*. | [Arc Games support](https://support.arcgames.com/hc/en-us/articles/360017610713-Steam-Cloud-Sync-Conflict-Window-in-Hob), [Steam discussions](https://steamcommunity.com/discussions/forum/1/2953755260403665202/) |
| **RetroArch cloud sync** | On conflict it **overwrites neither side and logs it**; with destructive sync off, files that would be overwritten are copied to `cloud_backups/…-YYMMDD-HHMMSS`. That "never destroy, always keep a copy" reflex is exactly PROJECT.md's rule. | The recovery artifact is a **timestamped filename in a folder** — filename archaeology, which EXPERIENCE-ETHOS #Sync explicitly forbids. Users still report "the cloud removed my most current save in a flash." Keep the behaviour, replace the surface. | [libretro docs](https://docs.libretro.com/guides/retroarch-cloud-sync/), [issue 17731](https://github.com/libretro/RetroArch/issues/17731), [issue 16663](https://github.com/libretro/RetroArch/issues/16663) |
| **Ludusavi** | **Lock a backup so it is exempt from retention limits** — the precise mechanism SEED-001's "treasured revision" needs, already proven in this exact domain. | — | [ludusavi.com](https://ludusavi.com/), [docs.rs 0.22.0](https://docs.rs/crate/ludusavi/0.22.0) |
| **Nintendo Switch Save Data Cloud** | Per-title entry point (title icon → + → Save Data Cloud) — saves are reached *from a game*, never from a global "saves" menu. Directly supports my no-new-sidebar-noun call. Also: **honest exclusions** — some titles are explicitly not covered, stated up front rather than silently unsynced. | First download per title is **manual**, an invisible precondition for automatic behaviour later — a hidden state the user cannot see. Any "automatic" claim we make must be visibly true from day one. | [Nintendo Support](https://support.nintendo.com/sg/nso/services/savedata-backup/index.html), [supported-title check](https://en-americas-support.nintendo.com/app/answers/detail/a_id/41213/) |
| **PlayStation Plus cloud saves** | Explicit per-save upload/download with visible timestamps and device attribution. | Auto-upload only on rest mode / sign-out — a durability guarantee tied to an invisible condition. Our equivalent trap is claiming durability tied to area A's flush cadence; the chip must reflect the byte's actual location, never an intent. | (behavioural, revalidate) |
| **iCloud Drive / Dropbox status icons** | — | The best-documented result in the whole area: icon-only sync vocabularies **do not survive contact with users**. Apple's own forums are full of "what does the cloud with a slash mean" and "the icons confuse me more each time I ask." Direct justification for the always-text-with-glyph rule and for refusing a compact icon-only save chip. | [Apple Community](https://discussions.apple.com/thread/6851689), [Apple Community](https://discussions.apple.com/thread/255083872), [Dropbox macOS icons](https://help.dropbox.com/sync/macos-sync-icons) |
| **Time Machine** | Browse by **when**, not by file version — the direct model for session grouping. | Its star field is ambient decoration the ethos bans; take the date rail, leave the galaxy. | (Apple, behavioural) |
| **Git clients (Tower/Fork/GitHub Desktop)** | The fork rail as the *only* honest rendering of divergence — you cannot draw two heads as one badge. | Their vocabulary (HEAD, ancestor, rebase, merge) is exactly what the ban list excludes. Take the **rail**, leave the **words**. | (behavioural) |
| **1Password item history / Obsidian version history** | Timestamp-first rows, restore-with-history-preserved — restoring adds an entry, it does not rewrite the past. Directly shapes "Restored here" as permanent provenance. | Both are flat lists that get unusable at high revision counts — the exact failure session grouping exists to prevent. | (behavioural) |
| **Dropbox "conflicted copy" / Syncthing conflict files** | Never destroys a side. | The artifact is a **filename** — the anti-pattern our whole surface exists to replace. | (behavioural) |

*Revalidation note:* every console/platform behaviour above is mutable vendor UI and
should be re-checked before implementation; the two load-bearing citations (RetroArch's
non-destructive conflict handling, Ludusavi's backup lock) are documented in
first-party docs and are the two I would defend.

---

## 11. Options considered

| # | Option | Sketch | Pros | Cons | Failure mode | Reversibility | Effort |
|---|---|---|---|---|---|---|---|
| **1** | **Card ladder absorbs save states** | new ranks between attention and downloading | one glance | **Impossible** — 6 states, 3 axes, 1 slot; forces a fused verdict = the SAVE-02 violation; breaks the seven-status equality test, forces snapshot rebaselines | Fused badge lies on 39-of-40 case | one-way (ladder is a published contract) | High |
| **2** | **Dedicated surface only; card untouched** | Save history sheet, card never mentions saves | Purest contract preservation; zero card risk | A conflict — data at risk, human decision required — is invisible until you go looking. Violates "escalate when the user must decide" | Silent conflict | cheap | Med |
| **3** ✅ | **Dedicated surface + conflict reuses existing rank 1** | as designed above | Satisfies SAVE-02 per-revision; card contract literally unchanged (no new case/glyph/token/copy/snapshot); one escalation, principled | `.needsAttention` overloaded; no grid-level triage between an unidentified ROM and a save conflict | Attention-inbox ambiguity | cheap both ways | Med |
| **3b** | 3, but conflict gets a **new** rank-1.5 case + glyph + hue | `saveConflict` in `LibraryStatus` | Grid-level triage | Third colour vocabulary or a ninth status hex; rewrites the frozen seven-status assertions; forces snapshot rebaseline (03.5 D-17 manual gate); buys triage nobody asked for | Contract churn | costly | Med-High |
| **4** | **New "Saves" sidebar noun** | 9th IA entry | Discoverable; is SEED-012 | Breaks D-14's literally-asserted 8-step order on both clients; a noun the user did not curate; explicitly future scope | Contract violation | costly | High |
| **5** | **Flat reverse-chron revision list** (instead of session grouping) | one row per revision | Simplest to build | Hundreds of near-identical rows; buries the playhead and the fork; perf risk against D-16 | Unusable at real cadence | cheap to change later | Low |

Chosen: **3**, with **session grouping** (rejecting 5) inside it.

---

## 12. Adversarial pass on my own recommendation

1. **"You hid five of six SAVE-02 states behind a sheet nobody opens. That fails the
   requirement."** — Partly fair. Mitigation: the readiness sheet's Save row is on the
   **pre-play path**, which is the highest-traffic per-game surface in the app, and it
   carries the rollup sentence; the history sheet is one activation from it. SAVE-02
   says a user *can see* the distinction, not that it is ambient. **But I concede the
   requirement's verifier could reasonably demand a glance-level surface.** If so, the
   cheapest honest addition is a *quiet muted line in the card's meta line* — **not**
   the status slot — and I have deliberately not proposed it because the meta line is
   already spec'd (monogram + region/version chips + not-yet-identified badge) and
   adding a fourth element there re-opens a frozen anatomy. **Recorded as R1.**
2. **"Newest-scoped rollup hides a stranded old version behind a calm sentence."** —
   The muted count line exists precisely for this and is unconditional when count > 0.
   The hostile version — "a user won't read a muted line" — is real, and answered at
   the only moment it matters: the destructive modal, which enumerates *every*
   only-here version, not just the newest. **Residual: R2.**
3. **"Escalate-on-undecidability means a silently-broken pipe can stay quiet for
   weeks."** — True when the failure does not also block play. Answered in §7,
   recorded as **R3**. I chose it consciously and would rather have a recorded residual
   than a notification that cries wolf on every closed lid.
4. **"Monochrome chips are less scannable; you traded accessibility for purity."** —
   Inverted, actually: monochrome makes colour carry *zero* save information, which is
   a stronger 1.4.1 posture than "also has a glyph". Scannability is recovered by
   shape + glyph + the fact that only ~3 chip values exist.
5. **"`.needsAttention` overloading will produce a grid of identical amber triangles
   with unrelated causes."** — Real. Mitigated only by attention being rare by
   construction. **Recorded as R4.** If it proves common in practice, option 3b is the
   escape hatch and it is not foreclosed by anything here.
6. **"You are here" is cute; a localiser will hate it.** — Accepted. It is the one
   piece of voice in the surface, it is metaphorically exact, and nothing about it is
   ambiguous when read aloud by VoiceOver.

---

## 13. Recommendation — numbered decisions

- **D-E1 — SAVE-02 is a per-revision requirement; the library card is not its venue.**
  The card is a router, not an explainer. *Rationale:* collapsing N revisions × 3 axes
  into 1 slot **is** the generic label SAVE-02 forbids. *Reversibility:* cheap.

- **D-E2 — Model the six states as three orthogonal axes** — durability
  (`only on this Mac` → `waiting to copy` → `on your server`, per revision, monotone),
  position (`you are here`, per **(revision, device)**), provenance (`restored here`,
  per revision, immutable), lineage (`separate version`, per revision-**set**) — and
  render each on its own visual channel. **No second priority ladder exists inside the
  save surface.** *Rationale:* a row is truthfully uploaded + current + restored at
  once. *Reversibility:* one-way (it is the ubiquitous language).

- **D-E3 — The game-level rollup is the durability of the *newest* revision, scoped in
  the sentence** ("Latest save is on your server"), never a `min()` fusion, never the
  word "backed up", **plus** an unconditional muted "{N} earlier versions are only on
  this Mac." *Rationale:* `min()` is a permanent false alarm; an unscoped claim is
  EXPERIENCE-ETHOS #16's forbidden green. **Any `SaveStatus(for: game) -> enum` is a
  bug.** *Reversibility:* cheap.

- **D-E4 — Save history lives as a per-game surface, not a sidebar noun:** a Save row
  in the readiness sheet (new seventh `ReadinessCheckKind.saveContinuity`, ordered
  last) opening a `SaveHistoryView` sheet that reuses the readiness sheet's
  keyboard/Escape/Done/focus-restore chrome. *Rationale:* D-14's 8-step IA is literally
  asserted; EXPERIENCE-ETHOS already specifies a Save readiness row; NSO's per-title
  entry point is the proven shape. *Reversibility:* cheap (SEED-012 can add a global
  view later without moving this one).

- **D-E5 — Exactly one save condition reaches the card: `conflicted`, via the ladder's
  *existing* rank-1 `needsAttention`** — no new `LibraryStatus` case, glyph,
  `StatusToken` value, label, or accessible-name sentence, therefore **no snapshot
  rebaseline**. Derived at render time (D-13's derivation rule) by OR-ing conflict
  presence with the existing attention source; **do not** widen the frozen nine-reason
  `Playstead.Attention.Reason` vocabulary. *Rationale:* rank 1 already means "a human
  must decide, data at risk". *Reversibility:* cheap; option 3b remains available.

- **D-E6 — Session-grouped timeline, not a flat revision list.** Rows are play sessions
  ("Yesterday evening · 2 hr 10 min · 14 versions"), expandable to versions; auto-expand
  only the session containing the playhead, any session with a conflict head, and the
  newest session when its newest revision is not on the server. *Rationale:* area A's
  cadence makes a flat list a log, not a history; people remember evenings, not
  revisions; it fixes noise + perf + JTBD together. *Reversibility:* cheap.

- **D-E7 — Row anatomy is three zones isomorphic to the card's:** leading rail (fixed
  28 pt: playhead / fork; reserved for SEED-006 thumbnails), primary (time as heading +
  origin/provenance as muted label), trailing durability chip. Fixed *estimated* height
  + virtualization; durability read from local SQLite, **never** hashed or stat-ed at
  render. *Reversibility:* cheap.

- **D-E8 — The save vocabulary adds zero colour literals.** Monochrome
  (`textMuted`/`textPrimary`) glyph + shape + text everywhere, with exactly one
  exception: `Separate version` and the conflict banner use the existing
  `StatusToken.attention`. **No green anywhere in the save surface.** Save glyphs are
  asserted disjoint from `LibraryStatus.glyphIdentifier`. *Rationale:* a third colour
  vocabulary destroys D-13's two-vocabulary premise; a green save chip is #16's
  forbidden reassurance. *Reversibility:* cheap.

- **D-E9 — Locked microcopy** (§5, verbatim): the six labels, explainers and VoiceOver
  sentences; the five rollup headers; the muted count line; the server/backup footnote;
  the readiness Save findings; the escalated panel; the only-copy modal. User-facing
  nouns: **save / version / Save history / your server**. **"Conflict", "revision",
  "sync", "backed up", "uploaded", and every backend term are banned from user-facing
  copy**; digests live behind a per-row Details disclosure only. *Reversibility:* cheap
  per string, one-way as a register.

- **D-E10 — Escalate on undecidability, never on duration or count.** Four tiers
  (§7): ambient chips → visible sentences → persistent panel (non-retryable failure) →
  interruptive (conflict exists; or a destructive action would destroy the only copy).
  Offline queues, slow uploads and old local-only versions **never** escalate. The
  escalated tier reaches the card only when the same condition also blocks play, via
  the existing readiness channel. *Rationale:* offline is the intended state; escalating
  it escalates success. *Reversibility:* cheap; **this is the decision I would defend
  hardest and the one most likely to be eroded by a well-meaning "just add a badge".**

- **D-E11 — Console parity is full in vocabulary/ordering, partial in verbs.**
  Inspect, export exact bytes, resolve a conflict, and be the only cross-device
  vantage point; it can never capture or restore-into-play. It renders **"Playing from
  this on {device}" + "as of {last check-in}"**, and **must never render a global
  playhead** — `current` is device-scoped. *Reversibility:* cheap.

- **D-E12 — One shared spec artifact (P3 D-17):** the Save Vocabulary & Axes table in
  `04-UI-SPEC.md`, mirrored as checked-in `shared/save-vocabulary.json`
  (`id, axis, label, explainer, voiceover_template, sf_symbol, heroicon, shape,
  color_token`), consumed **as a test resource on both sides, never at runtime**, with
  `Playstead.Saves.Vocabulary` and Swift `SaveState` each asserting literal equality.
  Drift fails CI on the side that moved. *Reversibility:* cheap.

- **D-E13 — Every save action has a visible control and an ordinary keyboard path**
  (03.5 D-21's `.onMove` lesson): expand/collapse, select, **Restore this version…**,
  **Export this version…**, **Details**, and conflict resolution as **two visible
  "Keep this one" buttons plus "Keep both"** — never gesture- or context-menu-only.
  *Reversibility:* one-way (it is a contract).

---

## 14. Forward compatibility (Q10)

| Seed | The exact seam that keeps it open | What I deliberately did **not** build |
|---|---|---|
| **SEED-001** (curation, naming, treasuring, provenance) | (a) The **provenance axis already exists and is immutable** — "Restored here", "From {device}" — so origin/emulator-version/import-method fields extend an existing row line rather than inventing one. (b) Session grouping reserves a **"Kept versions" section above the sessions** for revisions that float out of their group — Ludusavi's proven "locked backup exempt from retention" shape. (c) The row's primary zone already has a heading line that a user-supplied name can replace, with the timestamp demoting to the muted line. | No naming, no notes, no tags, no pinning, no Kept-versions section, no retention exemption. |
| **SEED-019** (system saves vs save states must not share a lying surface) | The vocabulary is **axis-based, not kind-based** — every one of the six states is equally true of a save state. The surface therefore needs one new discriminator when save states arrive: an **artifact-kind grouping above the session grouping** (or a segmented control), which the sheet's existing single-list layout accommodates without changing row anatomy. Critically, **nothing in the copy says "save" in a way that would become a lie** — the rollup says "Latest **save**…", which is why the artifact-kind grouping must arrive *before* save states, not with them. Flagged explicitly. | No kind discriminator, no segmented control, no second artifact kind. |
| **SEED-006** (screenshots make revisions recognisable) | The leading rail is a **fixed 28 pt column reserved even when empty**; a thumbnail widens it without re-laying-out the primary or trailing zones, and lazy image loading was already the plan since no byte access happens at render. | No thumbnail, no capture, no image storage. |
| **SEED-012** (memory-card explorer) | Because the surface is a **sheet driven by a context function** and not a sidebar-coupled pane, the same `SaveHistoryView` rows can later be hosted in a global explorer with a game column added. The console's cross-device view is the seed's server-side prototype. | No global saves view, no sidebar entry, no cross-game browse. |
| **SEED-002** (cartridge) | The provenance axis takes "From a cartridge, {date}" as one more origin value — no schema shape change. | Nothing. |

---

## 15. How this is proven (Q11)

Under 03.5 D-13 (pixel snapshots prove only genuinely visual claims), D-14 (exact
semantic XCTest for vocabulary/ordering/completeness), D-15 (fixtures assert exact
counts and state sets), D-17 (recording disabled in CI; missing references fail).

**Semantic XCTest — `SaveVocabularyTests`:**
1. `testSaveStateSetIsExactlySix` — equality with the complete `{onlyOnThisMac,
   waitingToCopy, onYourServer, youAreHere, restoredHere, separateVersion}` set.
2. `testEachStateDeclaresItsAxis` — the axis mapping is exhaustive and matches the spec.
3. `testSaveGlyphsAreDisjointFromLadderGlyphs` — set intersection with
   `LibraryStatus.glyphIdentifier` is empty.
4. `testSaveVocabularyIntroducesNoNewColorLiteral` — declared colours ⊆
   `{StatusToken.attention, textMuted, textPrimary}`; and disjoint-from-`SystemAccent`
   still holds.
5. `testLockedLabelsExplainersAndVoiceOverSentences` — literal string equality for all
   6 × 3 strings, the 5 rollup headers, the singular/plural count line, the footnote,
   the 5 readiness findings, the escalated panel, and the only-copy modal.

**Semantic XCTest — `SaveRollupTests`:**
6. `testRollupIsNewestScopedNotMinimum` — the 40-revision fixture (39 on server, 1
   local-only **old**) asserts header == "Latest save is on your server." **and**
   count line == "1 earlier version is only on this Mac."
7. `testRollupWithLocalOnlyNewest` — same fixture, local-only newest → "Latest save is
   only on this Mac."
8. `testNoGameLevelSaveEnumExists` — a meta/API-shape test asserting no
   `SaveStatus(for:)`-shaped fused accessor is exposed.
9. `testEmptyState` — zero revisions → "No saves yet." + body, no chips rendered.

**Semantic XCTest — `SaveCardEscalationTests` (the card-contract guards):**
10. `testConflictYieldsExactlyOneStatusSlotAtRankOne` — with a conflict plus a
    simultaneous downloading/queued/verified condition, exactly one slot renders and it
    is `.needsAttention`.
11. `testLibraryStatusSetIsStillExactlySeven` — the existing Phase 3 assertion, kept
    green as the proof that D-E5 changed nothing.
12. `testNonConflictSaveStatesNeverReachTheCard` — every durability/position/provenance
    permutation renders **no** save-derived status on the card.
13. `testCardCopyUnchanged` — literal equality of all seven `listViewLabel` and
    `accessibleName` strings against the Phase 3 values.

**Semantic XCTest — ordering / grouping:**
14. `testSessionGroupingAndAutoExpandRules` — exact expanded/collapsed set for a
    fixture with a playhead session, a conflict session, and eight quiet sessions.
15. `testRowAccessibleNameComposition` — `"{time}. {provenance}. {durability}."` with
    the playhead prefix, for each combination including uploaded+current+restored.

**Keyboard / accessibility (03.5 D-19/D-20/D-21):**
16. `testSaveHistoryFocusOrder` — XCUITest with an **independently authored** expected
    ID sequence; exactly one focused element per forward/reverse keypress; wrap
    behaviour exact; sheet opens by keyboard, contains focus, closes by Escape and by
    a focused Done, and restores focus to the opener.
17. `testConflictResolutionIsKeyboardOperableViaVisibleControls` — the explicit
    D-21-class guard: both "Keep this one" buttons and "Keep both" are focusable,
    activatable, and produce exactly one mutation/outbox effect each.
18. `testLiveAccessibilityAuditOnEverySettledSaveSurface` — all supported audit
    categories; exclusions only per exact audit type + exact element ID + pinned
    OS/Xcode fingerprint.
19. Accessibility-identifier inventory extended with `playstead.surface.save-history`,
    `playstead.surface.save-conflict`, and controls `save-restore`, `save-export`,
    `save-details`, `save-keep-this`, `save-keep-both`, `save-expand-session` — the
    existing meta-test that fails when a documented surface has no production route
    covers them automatically.

**Pixel snapshots (only genuinely visual claims):**
20. Contact sheet: all six save states as rendered chips/markers (proves distinct
    glyph + distinct shape + text present).
21. One populated `SaveHistoryView` (collapsed + auto-expanded sessions), one conflict
    state with the fork rail, one empty state. Rendered under D-16's fixed
    clock/UTC/`en_US_POSIX`/animations-disabled/2×/SDR harness, plus targeted
    **Large-text** and **long-Unicode-device-name** cases.
22. Negative visual assertion: the library card under a save-conflict fixture is
    **pixel-identical** to the existing `.needsAttention` reference — the cheapest
    possible proof that D-E5 did not disturb the frozen contract.

**Console (ExUnit / LiveView):**
23. `save_vocabulary_test.exs` — `Playstead.Saves.Vocabulary` literal equality with
    `shared/save-vocabulary.json` (the same fixture the Swift test reads).
24. `save_history_live_test.exs` — renders the same six labels and the same ordering;
    **and the negative test**: asserts the rendered HTML contains no bare "Current"/
    global playhead and that every playhead is qualified with a device name and an
    "as of" time.
25. `save_history_live_test.exs` — asserts capture/restore controls are **absent** on
    the console, and export/resolve controls are present.

**Not claimed:** VoiceOver pronunciation, rotor behaviour, sentence *comprehension*
(03.5 D-23 keeps these explicitly unclaimed), physical-controller navigation of the
save sheet, and anything requiring a real emulator + real bytes (checkpoint 7 remains
blocked). Say so in the UAT record rather than inferring it from a neighbouring test.

---

## 16. Coherence notes — what I assume about other areas, and where I collide

| Area | What I assume | Collision risk |
|---|---|---|
| **A — capture trigger / 24 s window** | Captures are frequent and machine-driven, and a "session" is derivable from adapter start/exit. | **Flag:** if A produces exactly one revision per session, session grouping is over-engineering (it degrades gracefully to one row per session — still correct, just no expansion). If A cannot delimit sessions, D-E6 needs a time-gap heuristic; say so explicitly rather than grouping by calendar day. **Also:** the 24 s worst-case loss window must be *said*, not hidden — I assume A owns that copy; if not, I claim it and it belongs in the Save history footnote, not in a per-row chip. |
| **B — lineage / conflict detection** | Conflict is detected as ≥2 heads from a common base and is a property of a set, with each revision carrying an origin device and a timestamp. | **Flag:** if B models conflict as a per-revision boolean flag, my fork rail and my group banner are unimplementable as specified — D-E2's set-cardinality claim is load-bearing. |
| **C — restore compatibility gate** | A restore can be *refused* on compatibility grounds. | **Flag:** an incompatible-but-present revision is a **seventh** state I have not designed a chip for. My position: it is **not** a durability state; it renders as a disabled "Restore this version…" plus a row-level explainer sentence, never a chip. If C wants it as a first-class state, D-E2's three-axis model needs a fourth axis and this must be decided jointly. |
| **D — retention / dedupe / storage** | Revisions can be pruned; the client keeps a bounded local set; "exists on exactly one device" is computable locally without a network call. | **Flag (two):** (1) the muted "{N} earlier versions are only on this Mac" count is only honest if D can compute it offline — if it needs the server, the line must be omitted rather than guessed. (2) **Pruning must never delete a version that exists nowhere else without the D-E9 modal** — this is the danger case and it is D's mechanism plus my copy. Ludusavi's "locked backup exempt from retention" is the SEED-001 seam and I ask D to leave room for a boolean it does not yet honour. |
| **F — launch preflight (zero network)** | The Save readiness row can be computed from purely local state. | **Flag:** if the "server has newer progress from {device}" finding requires a network call, it violates CACH-04 and must be dropped from preflight (it can still appear in the save sheet, which is not on the launch critical path). I assume it renders from the last-synced local read model with an "as of" qualifier. |
| **G — conflict resolution flow** | **Explicit handoff, five-point contract in §9 Job 3.** | **Loud flag:** if G chooses a **launch-time modal** (the Steam shape) it collides with my escalation model, which routes conflicts through the card and a deliberate sheet. My evidence-backed position is that launch-time forced choice is the documented footgun; G owns the call and I will conform. Also: G must offer **Keep both** as first-class, and must not use the word "conflict" in user-facing copy. |
| **H — export layout (PORT-01)** | Exporting one version, and exporting all of a game's saves, are both possible and deterministic. | **Flag:** my only-copy modal offers **"Export saves…"** as the *default* button — that escape hatch must exist and must be reachable from the Mac client at that moment. If H's export is server-side only, the modal's default action is a lie on an offline Mac and must change to "Keep it here". |

---

## 17. Residual risks

- **R1 — Glance-level SAVE-02.** Five of six states are one activation away, not
  ambient. If a verifier reads SAVE-02 as requiring glance-level visibility, the
  cheapest honest fix is a muted meta-line element on the card (**not** the status
  slot) — which re-opens a frozen anatomy. Deliberately not proposed; recorded.
- **R2 — The muted count line may go unread.** Mitigated only at the destructive
  moment, where the modal enumerates every only-here version.
- **R3 — A non-retryable, non-play-blocking sync failure stays panel-only.** Accepted
  consequence of escalate-on-undecidability; the alternative (notifications) fires on
  every closed lid. This is the one place I ranked low-administration quiet above
  data-safety visibility, and it is recorded rather than hidden.
- **R4 — `.needsAttention` overloading** makes grid-level triage between an
  unidentified ROM and a save conflict impossible. Escape hatch (option 3b) is not
  foreclosed.
- **R5 — "On your server" is overloaded** with the ladder's "On server" (game bytes
  not downloaded). Different surface, different subject, disambiguated by the explainer
  — but it is a genuine collision in a one-word scan.
- **R6 — SEED-019 ordering hazard.** The rollup copy says "Latest **save**…". When
  save states arrive, that word becomes ambiguous, so the artifact-kind discriminator
  must land **before or with** save states, never after. Flagged now because it is
  cheap now and expensive later.
- **R7 — Session grouping depends on area A** being able to delimit sessions. Degrades
  safely (one row per session) but the auto-expand rules assume multi-revision sessions.
