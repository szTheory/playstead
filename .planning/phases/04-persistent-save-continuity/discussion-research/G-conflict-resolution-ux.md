# Area G — What "resolve a conflict" actually does, as a user flow (SAVE-04 UX)

**Scope:** the complete human flow for a divergent save, and the state transition a
choice causes. Area B owns lineage/detection; area E owns the save timeline surface;
area F owns launch; area H owns export layout. This file owns: what a person sees,
what they decide, what they get back, and what the system does to itself when they choose.

**Requirement, verbatim (SAVE-04):** "When two devices create revisions from the same
base, the system retains both and lets the user inspect device/time/play context,
choose or export either side, and resolve the conflict without silent last-write-wins."

---

## 0. Grep receipts (what I verified before asserting)

| Claim | Verified in |
|---|---|
| Attention inbox exists, is user-scoped, has `grouping_key` + `count` + `evidence` map, and **has no TTL and no sweep** | `playstead-server/lib/playstead/attention/item.ex` (moduledoc states it explicitly) |
| Attention reasons are a frozen nine-value vocabulary copying `Sync.EntityKind`'s shape | `playstead-server/lib/playstead/attention/reason.ex` |
| Resolutions are audited, transactional, guarded against double-apply, and **never delete a byte** | `playstead-server/lib/playstead/attention/resolutions.ex` (`with_resolution/3`, `try_transition/2`, moduledoc) |
| `PlaySession` is `{id, user_id, asset_set_id, started_at, ended_at}` with `utc_datetime_usec` and a validated `ended_at > started_at` | `playstead-server/lib/playstead/curation/play_session.ex` |
| Card has exactly one status slot; rank 1 is "Needs attention"; no state is colour-only | `.planning/phases/03-.../03-UI-SPEC.md` §Status Vocabulary & Priority Ladder |
| Machine identity strings are role-shaped, never copy or content | `playstead-mac/Playstead/Design/AccessibilityIdentifiers.swift` |
| No save code exists on either side yet | greenfield per brief; no `save_revision`/`divergence` symbols in tree |

Inference (marked as such): everything below about *how* revisions are stored, how the
fork point is computed, and whether both sides' bytes are local is **area B/D's call**;
I state my requirements on them as explicit collision flags rather than assuming.

---

## 1. JTBD framing

**Who** — the owner. One person, self-hosting, two Macs (desk + laptop), or a household
where a sibling plays the same game on the other machine. Not an ops engineer. Not
someone who knows what a parent pointer is.

**What** — "Both my Macs have progress in this game and they don't match. Tell me which
is which, let me keep the good one, and don't destroy the other."

**Where** — noticed on the library card (the existing rank-1 attention slot), enumerated
in the existing Needs-attention inbox, decided in one comparison surface. Also fully
available on the LiveView console.

**When** — rare, important, **not urgent**. It is discovered at the next sync, which may
be hours or months after the fact. The user is almost never mid-play when they see it.
This timing fact is the single biggest design lever: it means the flow must **not**
interrupt, must **not** live in the launch path, and must **not** be a modal under time
pressure — which is precisely where Steam Cloud's dialog fails (see §3).

**Why** — to keep playing without losing the good run, and to stop worrying.

**What they need to do it** — a name for each side they recognise ("MacBook Pro", not a
UUID), when each was last saved, and one fact that actually discriminates: **how much
they played on each side since the two split**.

**What they get back** — a chosen version to continue from, a permanent visible record
that the other version still exists, and optionally exported folders of either side.

### Domain language

| Player-facing noun | Internal noun | Never shown |
|---|---|---|
| **version** (of your progress) | revision | revision id, blob id |
| **this Mac / {device name}** → generalised as **origin** | device / origin | device UUID |
| **when the two versions split** | fork point / merge base | parent pointers |
| **kept both** | acknowledged divergence | journal entity kind |
| — | resolution revision | cursor, digest, entity ids |

**Verbs:** compare, continue from, keep both, export, switch back.
**Events:** `save.divergence_detected`, `save.divergence_resolved`,
`save.divergence_acknowledged`, `save.exported`.

**The word "conflict" is engineer-speak and it is not neutral** — it implies a fight and,
worse, implies the user caused one. `EXPERIENCE-ETHOS` §Sync lists `conflict` as a *state
name*; that stays as machine vocabulary and as the state name both clients cite. It never
appears in a player-facing string. What actually happened, from the player's side, is:
**two Macs both have progress.**

---

## 2. Role lenses actually applied

- **Domain modeller** — the flow adds exactly two domain events and one nullable
  reference; it introduces no new bounded context. It reuses `Attention` (announcement),
  `Curation.PlaySession` (context), and area B's lineage (truth).
- **Offline-sync engineer** — resolution is a client-originated mutation with
  `Idempotency-Key` + client UUIDv7 (P1 D-20), applied to the local read model
  immediately and journalled on reconnect. Two clients resolving the same divergence
  concurrently converge because resolution is append-only (§4), not a compare-and-swap
  on a head pointer.
- **Elixir/Phoenix** — one additive `Attention.Reason` member, one additive nullable
  `belongs_to` on `attention_items`, resolutions written through the existing
  `with_resolution/3` transactional discipline. Nothing new invented.
- **Swift/macOS** — a sheet, opened by keyboard, focus-contained, Escape-dismissible with
  focus restoration (03.5 D-20). Read model from SQLite; zero network on render.
- **Security** — the sheet renders a user-supplied device name and a title; both are
  untrusted display strings and must be length-clamped and rendered as text, never as
  markup, on the console. No digests, paths, or credentials in copy or in the export
  receipt shown to the user.
- **Product / first adopter** — see §3, the whole of it.
- **UI/UX + microcopy** — §7, every string.
- **Accessibility** — §8, a design pillar; the comparison is deliberately *not* a
  two-pane visual diff for exactly this reason.
- **Performance** — 32 KB per side; one aggregate query over `curation_play_sessions`.
  Nothing here justifies an index beyond the one that already exists
  (`[:user_id, :asset_set_id, :started_at]`, verified).
- **Test/verification** — §14.
- **Red team** — §12.
- *Skipped as not applicable:* filesystem/durability engineer (area A owns flush and
  atomic write; G does not touch bytes on disk), SRE (this surface emits no alerts by
  design — it is a user-facing inbox item, not a page).

---

## 3. Prior art, and what each one teaches

| System | What it does | Copy this | Avoid this |
|---|---|---|---|
| **Steam Cloud sync conflict dialog** — [Valve / community](https://savegamelocation.com/blog/steam-cloud-sync-not-syncing-fix-save-conflicts/), [failure reports](https://pcgaminguniverse.com/steam-cloud-sync-fix-2026-community-fixes/) | Modal at launch, two columns (local vs cloud) with **timestamp and file size**, buttons to upload local or download cloud | Two-column side-by-side comparison; showing a timestamp per side | Three fatal errors we must not repeat: **(1) it fires at launch**, when the user's intent is "play now", so they click through — the documented complaint is literally "members who lost saves overwhelmingly admit they clicked through the conflict dialog too fast"; **(2) the discarded side is genuinely gone** — the choice is destructive, so a misclick is unrecoverable; **(3) file size is offered as a discriminator** and is useless (for a 32 KB SRAM it is *identical on both sides*, so showing it implies a difference that does not exist). Button wording also varies by client version — ours is frozen in a shared artifact. |
| **Xbox / GDK game-save sync** — [MS Learn](https://learn.microsoft.com/en-us/gaming/gdk/docs/features/common/game-save/game-saves-syncing), [Xbox Support](https://support.xbox.com/en-US/help/games-apps/troubleshooting/cloud-storage-sync-error-messages) | "Which one do you want to use?" plus a **"Keep waiting"** option that lets the user *not* decide now | The explicit non-decision escape hatch — this is the ancestor of our "Keep both" | Still launch-time, still framed as an error condition, and "you may lose unsynchronized data from the other console" is stated as a consequence rather than prevented |
| **PlayStation Plus cloud saves** | Manual upload/download with an explicit overwrite confirmation; no automatic merge | Honesty about it being an overwrite | Puts the entire burden on manual discipline; users routinely overwrite the newer save |
| **Nintendo Switch Online cloud saves** | Restore is an explicit confirmed overwrite; several games are **deliberately excluded** from cloud save entirely | Deliberate exclusion is an honest response to an unsolvable case | Their answer to conflict is "there is no conflict, because we overwrite" |
| **Dropbox "conflicted copy"** — [help.dropbox.com](https://help.dropbox.com/organize/conflicted-copy) | Last-writer-wins on the canonical name, loser preserved as `… (Device's conflicted copy 2026-03-12)` | **Never delete the loser.** This is the one thing every criticised system still gets right | The filename *is* the UI. Custody is communicated through string archaeology, which EXPERIENCE-ETHOS §2 explicitly forbids ("without requiring filename archaeology"). Users report finding conflicted copies months later by accident |
| **Syncthing `.sync-conflict-…` files** — [docs](https://docs.syncthing.net/users/syncing.html), [#9280](https://github.com/syncthing/syncthing/issues/9280), [#7405](https://github.com/syncthing/syncthing/issues/7405) | Conflicts propagate to *all* devices — a conflict is not local to whoever noticed | The canonical baffling case: no UI at all. Issue #9280 is a standing request for one. A user reported 27 conflicts in 50,000 files with **zero visibility**. Discoverability, not preservation, is the failure |
| **Obsidian Sync** — [1.9.7 conflict options](https://forum.obsidian.md/t/option-to-let-user-manually-resolve-sync-conflicts/94468) | Auto-merge for text, **"last modified wins" for every non-text file**, optional "create conflict file" | The admission that binary files cannot be merged | "Last modified wins" for binaries is exactly the silent LWW SAVE-04 forbids |
| **iCloud `NSFileVersion`** | OS-level API: all conflicting versions are enumerable (`unresolvedConflictVersionsOfItem(at:)`), each with `localizedName` and `modificationDate`; the app marks them `isResolved` | **The model we are copying**: an enumerable set of versions each carrying an origin name and a date, plus an explicit resolution act. Note Apple's chosen facts per version are exactly *name of origin* and *date* — nothing byte-level | The API is right and the UIs built on it are mostly absent; developers default to "newest wins" |
| **git DAG / merge commit** | A merge commit names both parents; neither branch is rewritten | **Provenance shape** for resolution: an immutable, auditable act rather than a mutation | Do not import git's *vocabulary* (branch, HEAD, merge, ancestor) into the player's view, and do not import three-way content merge — 32 KB of opaque SRAM has no merge |
| **1Password item history** | Every change is a retained version; "restore this version" appends a new current version rather than rewinding | Restore-as-append. This is our undo model exactly | — |
| **RetroArch cloud sync** | Documented save-clobbering complaints; sync is byte-level with no lineage | — | The named anti-pattern this requirement exists to avoid |
| **Ludusavi** | Backs up save locations with explicit per-backup manifests, no automatic restore | Explicit manifests, explicit user action | Not a conflict UI at all |

**The synthesis:** every criticised system fails on exactly one of two axes —
*preservation* (Steam, Obsidian-binary, RetroArch destroy a side) or *discoverability*
(Dropbox, Syncthing preserve everything and tell nobody). `NSFileVersion` + 1Password
history get both right and are the template. We must be preserving **and** visible, and
we must put the decision somewhere other than the launch path.

---

## 4. What "resolve" does to the state — the options

Three shapes were on the table.

| Option | Sketch | Pros | Cons | Failure modes | Reversibility | Effort |
|---|---|---|---|---|---|---|
| **(a) Pick a winner; head moves; loser retained as an inspectable branch** | `head := chosen_revision`; loser branch stays in the timeline, marked | Simplest possible mental model; one row updated; nothing deleted | "Resolve" is a **mutation of a pointer**. The act itself lives only in an audit log, not in the thing the user looks at. Two devices resolving concurrently is a compare-and-swap race. A later re-resolution silently rewrites the same pointer, so the timeline cannot show "you switched back on the 14th" | Head pointer drifts from lineage under partition; the audit log becomes the only record of a user-visible act, and audit logs are not a UI | Cheap (re-resolve) | Low |
| **(b) Choosing appends a new revision whose lineage names *both* parents** — recommended | A `resolution` revision is appended: same bytes (same sha256, so CAS-deduped to zero new storage per P2 D-11/D-12), lineage `parents: [chosen, acknowledged]`, `chosen_parent: chosen` | Resolution is an **immutable, auditable, orderable event**, not a mutation. Fits the append-only change-journal spine (P1 D-21) with no new mechanism. Concurrent resolutions on two devices both land as appends and converge without a CAS race. Re-resolving later is another append, so the timeline honestly reads "kept the laptop version, then switched back". Both parents stay reachable forever *by construction*, not by policy | Conceptual weight: there is now a revision that represents an act rather than a capture. Requires area B's lineage to allow ≥2 parents | If area B models parents as a single nullable pointer, this is blocked (collision flag B-1) | Cheap and *free* — undo is just another append | Low-medium (one extra lineage edge type) |
| **(c) Both sides become two named save lines; "resolve" = pick which line this device follows** | Each branch gets a name; per-device `follows` pointer | Matches SEED-001's eventual model; nothing is ever "resolved" so nothing is ever wrong | Requires a naming UI, which is **explicitly out of scope for Phase 4** (SEED-001/012/019 deferred by the brief). Forces every user through a curation decision to answer a yes/no question. A brand-new user's first encounter with the product's save model becomes "invent a taxonomy" | Users abandon the flow; unnamed lines accumulate; SAVE-04's "resolve" is never actually satisfied | Cheap | High |

**Decision: (b).** Its stated cost — conceptual weight — evaporates because *the user
never sees the resolution revision as a revision*. They see one timeline entry that reads
"You chose to continue from MacBook Pro." Its stated benefit is structural: it makes the
one consequential act in this flow immutable and auditable, which is precisely what
PROJECT.md's #1 priority (data safety and recoverability) and EXPERIENCE-ETHOS §4
("reversibility earns trust") ask for. And the byte cost is zero — content-addressed
storage means the resolution revision references the identical sha256 the chosen side
already has.

**(c) is not discarded, it is deferred and kept open**: the "Keep both" outcome (§6) is
literally (c) minus the naming, and the acknowledgement record is the exact anchor a
future name attaches to.

---

## 5. Can a resolution be undone?

**Yes, and there is deliberately no Undo affordance.**

The honest answer here is the better one. An Undo toast is transient, has a TTL, is
missable, is unreachable by a user who closed their laptop, and is unavailable to a
screen-reader user who did not hear it in time. It also *implies harm was done* — the
whole point of shape (b) is that nothing was harmed.

The undo affordance is: **the other version is still there, in the same place, wearing
the same actions.** After a resolution the comparison surface does not disappear; it
re-renders in a resolved state with the non-chosen side still fully present and its
"Continue from this one" button still live. Choosing it appends another resolution
revision. There is no time limit, no confirmation, no data loss, and no separate concept
to learn.

Concretely:

- No Undo toast, no snackbar, no TTL, no "you have 30 seconds".
- The chosen side gains a persistent inline marker: **"Currently continuing from this one."**
- The other side keeps its unchanged **"Continue from this one"** button.
- The save timeline (area E) shows one entry per resolution act, permanently.

This is 1Password's restore-as-append model, and it is why that model is trusted.

---

## 6. Inspection — what can honestly be shown

The payload is 32,768 bytes of opaque SRAM. There is no diff. Being rigorous about what
genuinely helps:

### Shown (four facts, in this order, per side)

1. **Origin** — the device's user-chosen name ("MacBook Pro"). Primary heading of the
   side. *Why it helps:* it is the only label the user already has a mental model for.
   **Seam note:** this field is an **origin label**, not a device label, so SEED-002's
   "Game Boy Advance cartridge" can occupy it later without re-plumbing.
2. **Last saved** — relative under 7 days ("2 hours ago"), absolute after ("12 March 2026").
   *Why it helps:* recency is the fact every prior-art system shows, and it is genuinely
   the first thing a person reaches for. **Clock-trust caveat below.**
3. **How long you played there since the two versions split** — summed from
   `curation_play_sessions` (`ended_at - started_at`) for that asset set on that origin,
   after the fork point. *This is the single most decision-useful fact available, and I
   will argue it:* the question the user is actually answering is "which of these two is
   the run I care about?", and personal investment is what makes a save matter (SEED-001
   says this in as many words). A timestamp tells you which is *newer*; newer is not
   better — a two-minute session where you booted the game to check something is newer
   than the four-hour run on the other Mac, and Steam's timestamp-only dialog is exactly
   how people throw away the four hours. Play-time-since-fork is the only available fact
   that correlates with *value* rather than *ordering*, and it is available for free
   because Phase 3 already ships `PlaySession` with validated durations.
4. **Number of saves since then** — "across 5 saves". *Why it helps:* it disambiguates
   "3 hours idle with the game paused" from "3 hours of active progress". It costs one
   line and it is the cheap corroborant for fact 3.

If a side has no recorded sessions since the fork, fact 3 renders as **"No recorded play
here since these split."** — an honest absence, not a zero.

### Rejected, and why

| Rejected | Why |
|---|---|
| **sha256 / short digest** | True and useless. A person cannot derive meaning from a hash. Showing it is backend-guts leakage that makes the surface look technical and trustworthy without conveying anything. Available only behind the **"Details"** expert disclosure (EXPERIENCE-ETHOS §11), never in the comparison. |
| **File size in bytes** | Worse than useless: both sides are 32,768 bytes, always. Showing an identical number on both sides *implies it is a discriminator*. This is Steam's exact mistake. Hard reject, including in Details. |
| **Byte-difference count / hex diff / "87% similar"** | Actively misleading. GBA SRAM contains checksums, RNG state, and play counters that churn constantly; two nearly identical saves can differ across most of the file, and two wildly different ones can differ in a few bytes. A similarity number would be a confident lie. Hard reject. |
| **Revision ordinal ("revision 14")** | Implies a total order across a fork where none exists. Two sides can both be "revision 14". Reject. |
| **Parent pointers, journal entity kind, sync cursor, blob id, entity UUIDs** | Provider-shaped. Reject outright; not even in Details. Details shows the digest and the adapter/version identity (needed for SAVE-03's compatibility story) and nothing else. |
| **A "recommended" badge on the likelier side** | The system does not know. Any heuristic (newest, longest-played) becomes the thing people click without reading, which is the silent LWW this requirement forbids, wearing a UI costume. **Hard reject — and it is an asserted test (§14).** |
| **Screenshots of each side** | SEED-006, out of scope. The side layout leaves the slot open; nothing renders there in v1. |

### The clock-trust honesty problem (flag to area B)

Capture time is claimed by the capturing device's clock. If the two claimed capture times
contradict the order in which the server received the revisions, showing the claimed times
unqualified is a lie the UI is telling on the device's behalf. Rule: **show the claimed
time, and when it contradicts server-observed arrival order, show one extra line rather
than hiding either fact.** Area B owns whether that contradiction is detectable; G
requires that it be *exposed as a boolean* on the revision so this line can render.

### The honest summary

If area B cannot supply play-session context, the honest answer collapses to **"the user
chooses on origin and time alone"** — and we would say that plainly rather than invent an
affordance. But it can (Phase 3 shipped it), so we get one fact that actually
discriminates on value, and that fact is the reason this flow is better than Steam's.

---

## 7. Where the flow lives

**Decision: the existing Needs-attention inbox announces and enumerates it; one dedicated
comparison sheet does the comparing and choosing; three entry points reach that sheet.**

### Why the existing attention inbox, and not a new surface

I took this seriously and it is a clear yes. The inbox is, verbatim from P2 D-26, for
"items needing a human decision" — a save divergence is the purest possible instance of
that class. Reusing it buys:

- A shipped, understood pattern the user has already met (a patched file, an ambiguous
  recognition). The constitution values internal consistency; a second parallel
  "important things" list would be a taxonomy the user must learn for no gain.
- `grouping_key` and `count`, already present (verified) — the answer to "fifty conflicts
  at once" (§12).
- **No TTL and no sweep**, already guaranteed by `Attention.Item`'s moduledoc and enforced
  by the absence of any cleanup code. A conflict discovered months later is not merely
  supported, it is the *default* behaviour of the table we are reusing.
- A transactional, audited, double-apply-guarded resolution discipline
  (`with_resolution/3`, `try_transition/2`) that already matches how resolution must work.
- The library card's **rank-1 "Needs attention"** status slot, which is already the
  highest rung of a frozen ladder (P3 D-13). A divergence gets top billing on the card
  with **zero new visual vocabulary and zero new colour token**.

What the inbox does *not* give us is a comparison view — no existing attention item needs
one, and D-27's five resolutions are all small commands. So:

**The inbox item is the announcement and the entry point. The comparison is its own sheet.**

### Entry points (one surface, three doors)

1. **Needs-attention inbox** → item → **"Compare versions"** → sheet.
2. **Game detail view's save section** (area E) → **"Compare versions"** → sheet.
3. **LiveView console** → same sheet content as a full page (§9).

### What it deliberately does *not* do

- **No modal.** No notification. No badge count in the dock.
- **No launch interception.** A conflict is rare, important, and *not urgent*; putting the
  decision in the launch path is the single documented cause of Steam's data loss.
- **Not missable either:** the card wears rank-1 attention, which per the frozen ladder
  outranks everything including "downloading" and "server-only". You cannot browse your
  library without seeing it.

### Collision flag with area F (launch) — a hard requirement, not a decision

I do not decide F's question, but I constrain it: **an unresolved divergence must not
block launch, and must not be silently resolved by launching.** If the user launches with
a divergence outstanding, this device plays the side it already has, and preflight must
say so in one quiet line — see §7's copy table. Playing then extends that side; it does
not choose it. Area F owns the placement of that line.

---

## 8. Export either side (PORT-01 tie-in)

An **"Export this version…"** action sits on **each side**, available **before, during,
and after** resolution, and available on a side that is not chosen. Export is not
resolution; exporting does not acknowledge, choose, or dismiss anything.

What the flow needs from area H, conceptually and no more: *a folder containing the exact
save bytes of that one revision plus a readable manifest identifying which origin and when.*
Deterministic, sorted, timestamp-free layout is P2 D-34/D-35 and `Playstead.Export.Layout`'s
business — **area H owns the layout; I do not design it here.**

The flow-level requirement I do assert: **export must not require choosing first.** A user
who is unsure should be able to take both sides out to ordinary folders and decide with
their own eyes, in their own emulator. That is EXPERIENCE-ETHOS §12 (no lock-in, clean
exit) applied at the exact moment it matters most.

---

## 9. Not-choosing is a first-class outcome

**Yes — "Keep both" is supported, permanently, and it is a peer of the choice buttons,
not a Cancel.**

"This is my brother's playthrough" is a legitimate, common, and *good* reason to never
pick. SEED-001 says explicitly that a family member's playthrough is one of the things a
user may treasure. A product that forces a winner is a product that eventually eats
someone's sibling's save.

**State transition:** "Keep both" appends an **acknowledgement** (not a resolution
revision — no side was chosen). Effects:

1. The attention item transitions to resolved (the human decision *was* made — the
   decision was "both").
2. The card's rank-1 attention clears; the card returns to its next-highest ladder state.
3. Both heads remain heads. Neither is canonical.
4. **This device records which side it follows** — the one it already has locally, because
   that is the one it has been playing. Nothing changes on disk.
5. **We never ask about this pair again.** A *new* divergence from a *new* fork point is a
   new item; the acknowledged one is not re-raised. This is the "stops nagging" contract
   and it must be an asserted test (§14).

**What it costs — stated honestly:**

- A clean-Mac restore (SAVE-03) has no unambiguous default when there are two
  acknowledged heads. The honest answer is that the new Mac asks the same comparison
  question once, on first restore, using the same sheet. **Collision flag C-1/F-2.**
- Area D's retention/eviction must treat **every divergence parent and every acknowledged
  head as permanently retained**, exempt from any pruning rule. **Collision flag D-1 — this
  is a hard requirement, not a preference.** A retention policy that ages out an
  acknowledged branch would silently destroy the exact thing this feature promised to keep.
- The save timeline (area E) must be able to render two heads without implying one is
  stale or wrong. **Collision flag E-1.**

**SEED-001 arrives early here, deliberately and cheaply:** a permanently-kept branch *is*
"not every revision is equal". We ship the retention promise and none of the curation UI.

---

## 10. Microcopy — every string

**Locked vocabulary rules.** Player-facing copy never uses: *conflict, overwrite, lost,
wins, loser, merge, error, failed, corrupt, stale, invalid, you should have*. It never
implies the user did something wrong — **playing on two Macs is the product working, not
the user erring** (EXPERIENCE-ETHOS §5: exceptions are part of the happy path).
`conflict` survives only as the internal state name in the shared vocabulary artifact.

### The name

**"Two versions of your progress"** — generalised to **"{N} versions of your progress"**.

### Card (unchanged — the frozen ladder is not reopened)

| Element | Copy |
|---|---|
| Status slot, rank 1 | "Needs attention" *(unchanged, P3 D-13)* |
| Card accessible name | "{title} needs your attention." *(unchanged)* |

### Needs-attention inbox item

| Element | Copy |
|---|---|
| Item title | "Two versions of your progress in {title}" |
| Item title, N > 2 | "{N} versions of your progress in {title}" |
| Item body | "You played {title} on {Origin A} and {Origin B} without them syncing in between. Both versions are saved. Nothing has been overwritten." |
| Item body, N > 2 | "You played {title} on {N} devices without them syncing in between. All {N} versions are saved. Nothing has been overwritten." |
| Primary action | "Compare versions" |
| Grouped header (many games at once) | "Two versions of your progress in {N} games" |
| Grouped secondary action | "Keep both in all {N}" |

### The comparison sheet

| Element | Copy |
|---|---|
| Sheet title | "Two versions of your progress" |
| Sheet subtitle | "{title} — both versions are safe. Pick the one to continue from, or keep both." |
| Sheet subtitle, N > 2 | "{title} — all {N} versions are safe. Pick the one to continue from, or keep them all." |
| Side heading | "{Origin name}" |
| Side line 1 | "Last saved {relative time}" / after 7 days: "Last saved on {date}" |
| Side line 2 | "You played {duration} here since these split" |
| Side line 2, no sessions | "No recorded play here since these split" |
| Side line 3 | "across {N} saves" / singular: "in 1 save" |
| Side action — choose | "Continue from this one" |
| Side action — chosen state | "Currently continuing from this one" *(inline marker, plus the button remains on the other side)* |
| Side action — export | "Export this version…" |
| Clock caveat line | "{Origin} reported a time that doesn't line up with when this version reached your server. Times from that Mac may be wrong." |
| Game-not-downloaded line | "{title} isn't downloaded on this Mac. You can still choose and export." |
| Keep-both action | "Keep both" / N > 2: "Keep them all" |
| Keep-both explainer | "Both versions stay in your library. This Mac keeps playing the {Origin} version." |
| Expert disclosure | "Details" |
| Dismiss | "Done" |

### Result states

| Element | Copy |
|---|---|
| After choosing (in sheet and in the save timeline) | "Continuing from {Origin}. The {Other origin} version is still here — you can switch to it anytime." |
| After choosing, N > 2 | "Continuing from {Origin}. The other {N−1} versions are still here — you can switch to any of them anytime." |
| After keeping both | "Keeping both. This Mac plays the {Origin} version. Neither version will be removed." |
| After switching back | "Continuing from {Origin} again. The {Other origin} version is still here." |
| Export result | "Exported {title} — {Origin}, {date}. The folder has the exact save file and a manifest listing what's inside." |
| Preflight/launch line (area F places it) | "This Mac is playing the {Origin} version. The other version is untouched." |

### Explicitly absent

- **No confirmation dialog on "Continue from this one".** This is a considered call, not
  an oversight. A confirmation is honest only before irreversible harm; here there is
  none, and a confirmation would train the user to dismiss dialogs — which is *exactly*
  the Steam Cloud failure mode, imported voluntarily. The action is instant and the result
  state is persistent and reversible.
- No Undo toast (§5).
- No "recommended" badge (§6).
- No progress bars, no spinners — the data is local.

---

## 11. Accessibility and input parity

### Keyboard focus order (authored independently of the tree, per 03.5 D-19)

Sheet opens by keyboard from the inbox item / detail view. Initial focus lands on the
**sheet heading** (announced), then Tab traverses exactly:

| # | Element | Identifier |
|---|---|---|
| 1 | Side A group (focusable summary; VO reads the whole comparison sentence) | `playstead.surface.save-divergence.side` |
| 2 | Side A — "Continue from this one" | `playstead.control.save-divergence.choose` |
| 3 | Side A — "Export this version…" | `playstead.control.save-divergence.export` |
| 4 | Side B group | `playstead.surface.save-divergence.side` |
| 5 | Side B — "Continue from this one" | `playstead.control.save-divergence.choose` |
| 6 | Side B — "Export this version…" | `playstead.control.save-divergence.export` |
| 7 | "Keep both" | `playstead.control.save-divergence.keep-both` |
| 8 | "Details" (expert disclosure) | `playstead.control.save-divergence.details` |
| 9 | "Done" | `playstead.control.done` *(existing)* |

Focus wraps 9 → 1. Shift-Tab is the exact reverse. For N sides, the per-side triple
repeats before "Keep them all". Identifiers describe a product role and carry no copy,
title, origin name, or content — matching the existing `AccessibilityIdentifiers`
contract (verified).

**Escape** closes the sheet and **restores focus to the opener** (03.5 D-20). "Done"
behaves identically.

### The 03.5 D-21 lesson, applied preemptively

D-21's finding was that a drag-only affordance failed the keyboard-parity contract and
had to be retrofitted with Move Up/Move Down. So this surface ships **with no
gesture-only, hover-only, or pointer-only affordance at all**. Every action is an ordinary
button reachable by Tab. There is no drag, no swipe-to-choose, no hover-to-reveal-details,
no synchronised scroll comparison, no slider. The comparison is a list of ordinary
sections with ordinary buttons — which is also why it works on a controller.

### Non-colour-only encoding (P3 D-13 / WCAG 1.4.1)

The two sides are distinguished by **origin name (text) + ordinal position + a
"Currently continuing from this one" text marker**. **No colour is used to distinguish
the sides at all** — not a border tint, not a background, not an accent. This is the
strongest possible form of 1.4.1 compliance and it also avoids inventing a *third* colour
vocabulary, which P3 D-13 forbids on principle. The only status hue anywhere in this
feature is the existing `--status-attention` on the card, from the frozen ladder.

Asserted as a test: the sheet's rendered palette is a subset of existing design tokens and
introduces no new colour constant (§14).

### VoiceOver — whole sentences, never two fragments

Each side is **one accessibility element** exposing one complete comparison sentence, so a
VoiceOver user gets a comparable unit rather than nine disconnected labels:

> "Version 1 of 2. Saved on MacBook Pro, 2 hours ago. You played 3 hours 20 minutes on this Mac since the two versions split, across 5 saves. Actions available: continue from this one; export this version."

> "Version 2 of 2. Saved on Mac mini, 4 days ago. You played 18 minutes on this Mac since the two versions split, across 2 saves. Actions available: continue from this one; export this version."

Sheet summary, announced on open:

> "Two versions of your progress in Metroid Fusion. Both are safe. Compare them and pick one, or keep both."

Post-action announcement (polite live region / `AccessibilityNotification.Announcement`):

> "Continuing from MacBook Pro. The Mac mini version is still available."

> "Keeping both. This Mac plays the MacBook Pro version."

Chosen side's element gains the leading clause: *"Currently continuing from this one. Version 1 of 2. …"*

### Controller (P3 D-14)

D-pad up/down moves between side groups and the button row; A activates; B closes (same
as Escape, same focus restoration). No text entry is required anywhere in the flow, so
the Phase 3 "no on-screen keyboard" deferral is not touched. All targets ≥ 44×44pt.

### Reduced motion

The sheet uses the existing 150ms in-place crossfade for the chosen-state marker, replaced
by an instant swap under reduced motion (P3 D-16). Nothing else animates.

### Text scaling / long strings

Origin names are user-supplied and untrusted: clamp to 2 lines with tail truncation; the
full name is available in the accessible label. Side sections grow vertically with Dynamic
Type — the sheet scrolls; the buttons never leave the layout.

---

## 12. LiveView console parity

**Yes — and the console is arguably the better place for this decision.** A comparison
wants width, and a divergence is very often noticed while you are *not* at the Mac that
has one. The console can inspect, choose, and export. It cannot play.

Console specifics:

- Renders as a full page (route under the existing inbox), not a modal — a bigger screen
  is the point.
- **Identical strings**, with exactly two console-only additions, because the console
  cannot play and must not imply it can:
  - After choosing: "Continuing from {Origin}. Your Macs will use this version the next time they sync."
  - After keeping both: "Keeping both. Each Mac keeps playing the version it already has."
- No "Play" control appears anywhere in this flow on the console (matching P3 D-17's rule
  that a server-only card offers "Download", never a greyed "Play").
- Focus order, Escape/close semantics, and the whole-sentence accessible names are the
  same contract expressed in HEEx `aria-label`s.

### The shared vocabulary artifact (P3 D-17 — parity drift is the named top risk)

Both clients cite **one** document: a new **"Save divergence"** section in `04-UI-SPEC.md`,
structured exactly like Phase 3's Status Vocabulary table, containing:

1. the state names (`diverged`, `resolved`, `acknowledged`) — the only place the word
   `conflict` survives, as the machine-state synonym;
2. the complete locked strings table from §10, including the two console-only variants;
3. the authored focus order table from §11;
4. the accessible-name sentence templates;
5. the explicit "no new colour token" rule.

Backed by **one golden strings fixture** checked in and asserted by both the XCTest and
ExUnit suites, so a string edited on one client and not the other is a red build, not a
drift discovered in a screenshot review six weeks later.

---

## 13. Design pillars traded, in PROJECT.md's ranked order

| Pillar | How it lands | Where it won or lost |
|---|---|---|
| **1. Data safety and recoverability** | Nothing is deleted, ever. Resolution is append-only. Both parents retained by construction. Export available before choosing | **Won every conflict.** It is why there is no destructive path and no bulk "always use this Mac" |
| **2. Reliable local play and save continuity** | Launch is never blocked by an unresolved divergence; the device plays what it has and says so | Beat "force a decision". Collision constraint on F |
| **3. Clarity, accessibility, low-administration** | Whole-sentence VoiceOver, zero gesture-only affordances, no colour-only encoding, no new vocabulary | Beat **quiet-by-default**: a divergence lights rank-1 attention on the card, which is louder than "quiet". Justified — EXPERIENCE-ETHOS §3 says escalate "only when the user must decide", and this is that case. It did **not** beat quiet enough to earn a modal, a notification, or a launch prompt |
| **4. Performance and resource efficiency** | One aggregate over an already-indexed table; 32 KB per side; CAS-deduped resolution revision costs zero bytes | Lost mildly to clarity: I fetch both sides' bytes eagerly on detection so offline compare/export always works (collision flag D-2). At 32 KB this is not a tradeoff worth having |
| **5. Integrated delight** | Deliberately none. No animation beyond the existing crossfade, no celebration | Ceded entirely to clarity. A conflict is not a moment for delight |
| **6. Feature breadth** | No naming, no notes, no screenshots, no merge, no bulk winner-picking | Ceded to the phase boundary |
| **Internal consistency** | Reuses the attention inbox, the frozen status ladder, the existing resolution transaction discipline, the existing identifier convention. Adds **zero** new colour tokens and **zero** new status states | Won against "a dedicated conflict centre" |
| **Offline behaviour** | See below — the whole flow works with no server | Won against implementation simplicity |

### Offline: can a conflict be resolved with no server? Yes, and it must be.

Argued rather than assumed. In this architecture the server is the sync hub, so a
divergence is usually *detected* when a device syncs. But detection and resolution are
different moments, often days apart, and by the time the user opens the sheet the network
may be gone. Requirements:

- **Comparison metadata is already local** — origin names (pairing), capture times and
  lineage (the sync read model), play sessions (Phase 3's local curation model). Zero
  network to render.
- **Both sides' 32 KB are fetched eagerly on detection**, so compare *and export* work
  offline. At 32 KB this is free. **Collision flag D-2.**
- **Choosing is a local mutation plus one outbox entry** with `Idempotency-Key` and a
  client-generated UUIDv7 (P1 D-20). The read model updates immediately; the journal entry
  ships on reconnect. Because resolution is an append (§4), two devices resolving offline
  in opposite directions both land, and the timeline honestly shows both acts in order —
  no CAS race, no lost update, no "your resolution was rejected".
- **Zero network on the launch path is untouched** (CACH-04 / P3 D-23) — nothing in this
  flow adds a network call before Play.

---

## 14. Adversarial pass on my own recommendation

**How does this lose data?** By construction it cannot delete, but it has one real hole:
**area D's retention policy**. If eviction, dedupe, or pruning ever removes a divergence
parent or an acknowledged head, this entire feature becomes a lie told confidently. The
copy says "Nothing has been overwritten" and "Neither version will be removed" — those
strings are promises the retention layer has to keep. **This is the residual risk I rate
highest.** Mitigation: hard requirement D-1 plus a named test that a parent/acknowledged
head is exempt from every retention path.

**How does it mislead?** Play-time-since-split correlates with investment, not with
progress. A user can play three hours, die repeatedly, and end up worse off than the
18-minute side. Mitigations: (a) the word is always **"played"**, never "progress made" or
"further along"; (b) both facts (duration *and* save count) always show together;
(c) **no side is ever recommended, highlighted, sorted-to-top-by-quality, or
pre-selected** — sides are ordered by claimed capture time, descending, and that ordering
is stated implicitly by "Version 1 of 2" and nothing more. Residual risk accepted: a user
may over-weight duration. It is still strictly better than over-weighting recency, which
is what every prior-art system teaches them to do.

**How does it get clicked through thoughtlessly?** Someone hits "Continue from this one"
without reading. Cost: near zero — the other side is still on screen with a live button.
The Steam failure mode requires three ingredients (launch-time, time pressure, destructive)
and we have removed all three. Residual: a user who never opens the inbox lives with a
rank-1 attention badge forever. That is acceptable — the badge is honest and non-blocking,
and nothing degrades.

**Hostile reviewer: "you built a git DAG for a 32 KB file."** The DAG is area B's and is
mandated by SAVE-04's retain-both requirement regardless of what G decides. G adds exactly
one edge type and one append per resolution. The alternative (a) is a mutable pointer,
which is *not* simpler once you need concurrent offline resolution and a truthful timeline.

**Hostile reviewer: "the resolution revision duplicates 32 KB."** No — content-addressed
storage (P2 D-11/D-12) means it references the identical sha256 the chosen side already
has. Zero new bytes.

**Hostile reviewer: "'Keep both' is a way for users to never decide, and you'll ship a
product full of unresolved state."** Correct, and intended. Unresolved-forever is a valid
outcome (§9). What we must not ship is *un-acknowledged* state that nags — hence the
acknowledgement record and the never-re-ask contract.

### Specific adversarial scenarios

**Three-way (or N-way) divergence.** The design generalises without a new shape: the sheet
renders a vertical list of N side sections, identical anatomy, identical actions, heading
"{N} versions of your progress". Choosing appends **one** resolution revision naming
**all N heads** as parents (chosen + N−1 acknowledged), so no residual pairwise conflicts
are left behind — this is the specific reason (b) beats (a) here, since a pointer move
would leave N−2 conflicts still outstanding. "Keep both" becomes "Keep them all". The list
scrolls and is keyboard-traversable. N is bounded by device count; no artificial cap.

**Conflict on a game the user no longer has downloaded here.** Save revisions are 32 KB
and independent of game bytes, so compare, choose, and export all work fully. Only Play is
unavailable. The card already resolves correctly: rank-1 attention outranks rank-6
server-only on the frozen ladder, so the card shows attention, not "On server". The sheet
adds one quiet line: "{title} isn't downloaded on this Mac. You can still choose and export."

**Conflict discovered months later.** Fully supported by the reused table: `Attention.Item`
has no TTL and no sweep (verified in code, not assumed). Relative times degrade to absolute
dates past 7 days so "Last saved 4,312 hours ago" never happens. Nothing expires, nothing
auto-resolves.

**Fifty conflicts at once after a long offline period.** Three defences:
1. **One item per {asset set, fork point}** — never one per revision. A device that
   captured 40 revisions offline produces **one** item, not 40. Uses the existing
   `grouping_key`.
2. **Grouped inbox header** — "Two versions of your progress in 50 games", expandable,
   so the inbox is not 50 undifferentiated rows.
3. **One bulk action, and only one: "Keep both in all {N}".** It is honest because it
   chooses nothing, destroys nothing, and is individually reversible — each game's sheet
   still offers both sides afterwards. **A bulk "always use this Mac" is refused outright**;
   it is silent last-write-wins with a consent checkbox, which is precisely what SAVE-04
   forbids. This refusal is an asserted test.

**Two devices resolving the same divergence simultaneously, offline, in opposite
directions.** Both appends land. The timeline shows two resolution acts in arrival order;
the later one is current. Nothing is lost, nothing errors, and the user can see exactly
what happened. Under shape (a) this would have been a lost update or a rejected write.

**A malicious or broken device name / game title.** Untrusted display strings: clamped,
rendered as text, escaped on the console, full value only in the accessible label.

---

## 15. Options table (the flow-placement question)

| Option | Sketch | Pros | Cons | Failure modes | Reversibility | Effort |
|---|---|---|---|---|---|---|
| **Dedicated "Conflicts" surface (new sidebar entry)** | New top-level nav item | Discoverable; room to breathe | A second "important things" list beside the inbox; a sidebar entry that is empty 99.9% of the time; violates P3's frozen 8-entry sidebar order | Sidebar contract regression | Costly (nav IA) | Medium |
| **Existing attention inbox announces; dedicated sheet compares — recommended** | New `Attention.Reason`, item → "Compare versions" → sheet | Reuses a shipped, understood pattern with grouping, no-TTL, and an audited resolution discipline already built. Zero new nav, zero new colour, zero new status state | Requires adding one member to a frozen reason vocabulary; the sheet is genuinely new UI | Reason vocabulary churn if more save states want inbox entries later | Cheap | Medium |
| **A state of the save timeline only (area E)** | Timeline renders two heads; choose inline | Perfectly contextual; no new surface at all | **Missable** — the user must already be looking at one game's save timeline to discover it. Fails "must not be missable" | Silent unresolved divergence forever | Cheap | Low |
| **Prompt at launch (area F)** | Modal before Play | Impossible to miss | The documented Steam failure mode, verbatim: time pressure + a decision + click-through. Also collides with F's zero-network preflight | Data-loss-by-reflex (in a destructive design) | Costly | Low |

The recommendation composes the middle two: **inbox for enumeration, timeline for context,
one shared sheet for the decision.** Nothing is missable (the card badge), nothing
interrupts (no modal, no launch prompt).

---

## 16. Forward compatibility

| Seed | What keeps it open | What I deliberately did NOT build |
|---|---|---|
| **SEED-001** (naming/treasuring revisions; a kept branch wants a name) | The **acknowledgement record** is the anchor a future name/note/tag attaches to — it is a durable, addressable row describing "the user deliberately kept this branch". The side heading is an **origin label slot**, and the sheet's side anatomy has an unused slot above the heading where a user-given name would sit without re-layout. Player-facing noun is **"version"**, which reads naturally with or without a name ("the *Family playthrough* version") | No naming, renaming, notes, tags, treasure/protect flags, screenshots, or curation UI of any kind. No `label` column shipped unused |
| **SEED-002** (a cartridge-sourced revision as one side) | The side heading is an **origin**, not a device — copy, accessible names, and the data seam all say "origin". "Game Boy Advance cartridge" drops into the same slot with no string rewrite and no plumbing change. This is why every string above says `{Origin}` and not `{Mac}` | No cartridge read/write, no physical-medium provenance fields |
| **SEED-019** (save states arriving into the same surface without it lying) | Copy says **"your progress"**, never a bare "save", so a future save-state divergence can add a qualifier ("in-game save" vs "save state") without any existing string becoming false. The state names (`diverged`/`resolved`/`acknowledged`) are payload-kind-agnostic. The sheet's side anatomy has no field that only a battery save can populate | No save-state affordance, no kind selector, no mixed-kind comparison |
| **SEED-006** (screenshots) | The side layout reserves a slot above the origin heading; nothing renders there in v1 | No screenshots |

---

## 17. How this is proven (03.5 D-03 / D-09 / D-13 / D-14 / D-19 / D-20)

Every UAT checkpoint maps to a **named** test, proven discovered, executed, non-skipped,
and passed. No fixed sleeps, no "exited zero", no percentage-only screenshot checks.

### Deterministic test profile (03.5 D-09)

Two new members on the finite compile-gated enum: **`saveDivergenceTwoWay`** and
**`saveDivergenceThreeWay`**. Seeded **through real capture/lineage/curation APIs** —
never raw SQL, never a copied production DB — with fixed synthetic device ids, fixed
timestamps, fixed play sessions of known durations, and fixed 32,768-byte synthetic
patterns (never ROM-derived bytes, never proprietary BIOS). A third variant
`saveDivergenceClockSkew` seeds contradicting capture/arrival order to exercise the caveat
line. Test-only hooks fail closed and are provably absent from release builds (03.5 D-08).

### Mac (XCTest / XCUITest)

| Test | Proves |
|---|---|
| `SaveDivergenceSheetTests.testRendersOneSidePerHeadWithOriginTimeAndPlayContext` | Sheet rendering; one side per head; the four facts present |
| `SaveDivergenceCopyTests.testEveryStringMatchesGoldenFixtureExactly` | Exact copy assertions against the shared artifact |
| `SaveDivergenceCopyTests.testNoPlayerFacingStringContainsForbiddenVocabulary` | The words *conflict, overwrite, lost, wins, merge, error, corrupt* appear in zero player-facing strings |
| `SaveDivergenceCopyTests.testNoSideIsRecommendedHighlightedOrPreselected` | The hard reject from §6 |
| `SaveDivergenceCopyTests.testFileSizeAndDigestAreAbsentFromComparison` | No backend-guts leakage; digest only under Details |
| `SaveDivergenceStateTests.testChooseAppendsResolutionRevisionNamingBothParents` | The §4 state transition |
| `SaveDivergenceStateTests.testBothParentsRemainReadableAndExportableAfterChoosing` | Retention of the loser |
| `SaveDivergenceStateTests.testSwitchingBackIsAnotherAppendAndBothActsAppearInTimeline` | Reversibility with no Undo affordance |
| `SaveDivergenceStateTests.testKeepBothClearsAttentionAndLeavesBothHeads` | The §9 transition |
| `SaveDivergenceStateTests.testAcknowledgedDivergenceIsNeverRaisedAgain` | The stops-nagging contract |
| `SaveDivergenceStateTests.testResolutionSurvivesRelaunchAndProducesExactlyOneOutboxMutation` | Durability + no double-apply |
| `SaveDivergenceOfflineTests.testChooseWithServerUnreachableAppliesLocallyAndQueuesOneIdempotentMutation` | Offline resolution |
| `SaveDivergenceOfflineTests.testExportEitherSideSucceedsWithNoNetwork` | Offline export |
| `SaveDivergenceLadderTests.testDivergedGameRendersExactlyOneStatusSlotAtRankOne` | P3 D-13/D-14 — one slot, attention outranks server-only |
| `SaveDivergenceLadderTests.testSheetIntroducesNoNewColourConstant` | The zero-new-vocabulary rule |
| `SaveDivergenceKeyboardTests.testFocusOrderMatchesIndependentlyAuthoredSequence` | 03.5 D-19 — expected ID list authored separately from the queried tree; exactly one focused element per keypress; forward and reverse |
| `SaveDivergenceKeyboardTests.testEveryActionIsReachableWithoutPointerOrGesture` | The D-21 lesson |
| `SaveDivergenceKeyboardTests.testEscapeClosesSheetAndRestoresFocusToOpener` | 03.5 D-20 |
| `SaveDivergenceAccessibilityTests.testLiveAuditPassesAllCategoriesAfterSettle` | 03.5 D-20 live audit, no blanket handlers |
| `SaveDivergenceAccessibilityTests.testEachSideExposesOneWholeComparisonSentence` | The §11 VoiceOver contract |
| `SaveDivergenceTests.testGameNotDownloadedStillAllowsChooseAndExport` | Adversarial case |
| `SaveDivergenceTests.testThreeHeadsRenderThreeSidesAndOneResolutionNamesAllThree` | N-way |
| `SaveDivergenceTests.testClockSkewRendersTheCaveatLine` | Honesty under untrusted clocks |

### Server (ExUnit)

| Test | Proves |
|---|---|
| `Playstead.Attention.SaveDivergenceTest.test_one_item_per_asset_set_and_fork_never_one_per_revision` | Fifty-conflicts grouping |
| `Playstead.Attention.SaveDivergenceTest.test_item_never_ages_out_or_is_swept` | Months-later discovery |
| `Playstead.Attention.SaveDivergenceTest.test_concurrent_resolution_from_two_devices_both_land_as_appends` | Convergence, no lost update |
| `Playstead.Attention.SaveDivergenceTest.test_no_bulk_choose_winner_command_exists` | The refused bulk action (asserts the resolution command surface) |
| `Playstead.Attention.SaveDivergenceTest.test_resolution_writes_exactly_one_audit_entry_in_one_transaction` | Matches the existing `with_resolution/3` discipline |
| `PlaysteadWeb.SaveDivergenceLiveTest.test_console_strings_match_the_same_golden_fixture` | **Parity — the anti-drift test** |
| `PlaysteadWeb.SaveDivergenceLiveTest.test_console_offers_choose_and_export_and_never_play` | Console honesty |

### Pixel snapshots (03.5 D-13 — only genuinely visual claims)

One contact sheet: two-way sheet, three-way sheet, resolved state, kept-both state,
game-not-downloaded state, clock-caveat state. Semantic XCTest assertions carry everything
else; pixel similarity never substitutes for them.

---

## 18. Recommendation — numbered decision list

| # | Decision | Rationale | Reversibility |
|---|---|---|---|
| **D-G1** | **Choosing appends a resolution revision whose lineage names all divergent heads as parents (chosen + acknowledged), rather than moving a head pointer.** The bytes are CAS-deduped, so it costs zero new storage | Makes the one consequential act immutable and auditable; converges under concurrent offline resolution with no CAS race; makes re-resolution a truthful timeline entry; resolves N-way in one act | Cheap — undo is another append |
| **D-G2** | **No Undo affordance. The non-chosen version stays on screen with a live "Continue from this one" button, forever.** No toast, no TTL | A permanent, self-evident history is more honest and more accessible than a transient control; nothing was harmed, so implying harm would be a lie | One-way as a design stance; trivially addable later |
| **D-G3** | **Inspection shows exactly four facts per side: origin, last saved, play time since the split, saves since the split.** Digest lives under "Details"; **file size, byte-diff, similarity scores, revision ordinals, and parent pointers are never shown anywhere** | Play-time-since-split is the only available fact that correlates with *value* rather than *ordering*; file size is Steam's exact mistake and is literally constant here | Cheap |
| **D-G4** | **No side is ever recommended, highlighted, pre-selected, or sorted by quality.** Sides order by claimed capture time, descending | Any heuristic becomes the thing people click without reading — silent LWW wearing a UI costume | One-way (a recommendation would be very hard to withdraw) |
| **D-G5** | **A save divergence raises one item in the existing Needs-attention inbox** (one additive `Attention.Reason` member, `save_divergence`; one additive nullable revision reference on `attention_items`), **grouped one per {asset set, fork point}** | Reuses a shipped, understood pattern that already provides grouping, no-TTL, audited transactional resolution, and the card's rank-1 status slot — zero new nav, zero new colour, zero new status state | Costly (schema + frozen vocabulary) |
| **D-G6** | **One comparison sheet, three entry points** (inbox item, game detail save section, console page). **No modal, no notification, no launch prompt.** The library card's existing rank-1 "Needs attention" makes it un-missable | A conflict is rare, important, and not urgent; launch-time placement is the documented cause of Steam's data loss | Cheap |
| **D-G7** | **No confirmation dialog on "Continue from this one."** Instant action, persistent reversible result state | Confirmations are honest only before irreversible harm; adding one here would train click-through — importing Steam's failure mode voluntarily | Cheap |
| **D-G8** | **"Keep both" is a first-class peer of the choice buttons, not a Cancel.** It appends an acknowledgement, clears attention, leaves both heads, records which side this device follows, and **is never re-raised for that fork** | Not-choosing is legitimate and common ("my brother's playthrough"); SEED-001's "not every revision is equal" arrives early, for free | Cheap |
| **D-G9** | **"Export this version…" sits on every side and works before, during, and after resolution — exporting is never resolution.** Conceptually: a folder with the exact bytes plus a readable manifest naming the origin and date. **Layout is area H's** | EXPERIENCE-ETHOS §12 clean exit, at the moment it matters most; lets an unsure user decide with their own eyes | Cheap |
| **D-G10** | **The whole flow works with no server**: metadata is local, both sides' 32 KB are fetched eagerly on detection, and choosing is a local mutation plus one idempotent outbox entry | Both sides may be local and the network is often gone by the time the user opens the sheet; at 32 KB the eager fetch is free | Cheap |
| **D-G11** | **The word "conflict" never appears in player-facing copy.** The feature is named **"Two versions of your progress"**. `conflict` survives only as the machine state name. All strings in §10 are locked | The user did nothing wrong by playing on two Macs; the copy must not imply they did (EXPERIENCE-ETHOS §5) | Cheap |
| **D-G12** | **Zero gesture-only, hover-only, or pointer-only affordances; zero colour used to distinguish the sides.** Sides differ by origin name + ordinal + a text marker. Authored focus order per §11, Escape restores focus to the opener | 03.5 D-21's lesson applied before shipping rather than after; strongest form of WCAG 1.4.1; avoids inventing a third colour vocabulary (P3 D-13) | Cheap |
| **D-G13** | **Each side is one accessibility element exposing one complete comparison sentence**, per the §11 templates; post-action announcements are polite live regions | Two fragments per side is not a comparison for a VoiceOver user | Cheap |
| **D-G14** | **Full LiveView console parity, with two console-only result strings** ("Your Macs will use this version the next time they sync"), and **no Play control anywhere in the flow** | The console is the better screen for a comparison and is often where the user is; honesty about what the console can do | Cheap |
| **D-G15** | **One shared vocabulary artifact — a "Save divergence" section in `04-UI-SPEC.md` plus one golden strings fixture asserted by both suites** | P3 D-17; parity drift is the named top long-term risk, and a golden fixture turns drift into a red build | Cheap |
| **D-G16** | **The only bulk action is "Keep both in all {N}". A bulk "always use this Mac" is refused outright** and asserted absent by test | The refused action is silent last-write-wins with a consent checkbox — exactly what SAVE-04 forbids; the offered one destroys nothing and is individually reversible | One-way (refusal) |
| **D-G17** | **N-way divergence uses the same anatomy** — N side sections, one resolution naming all N heads, "{N} versions of your progress", "Keep them all" | Falls out of D-G1 for free; a pointer move would leave N−2 conflicts outstanding | Cheap |

---

## 19. Coherence notes — what I assume of other areas, and where I collide

| Flag | Area | Assumption / collision | Severity |
|---|---|---|---|
| **B-1** | **B — lineage & detection** | D-G1 **requires lineage to permit ≥2 parents on a revision** and to distinguish `chosen_parent` from acknowledged parents. If B models parentage as a single nullable pointer, D-G1 is blocked and we fall back to shape (a) with its concurrency and timeline costs | **Blocking** |
| **B-2** | **B** | I require a **fork point** ("when these split") to be computable and exposed, since "play time since the split" and "saves since then" both depend on it | **Blocking** |
| **B-3** | **B** | **Clock trust is B's.** I require a boolean on each revision indicating whether its claimed capture time contradicts server-observed arrival order, so §10's caveat line can render. If B cannot supply it, I show claimed times unqualified — which is a small, stated honesty debt | High |
| **B-4** | **B** | Detection must produce **one event per {asset set, fork point}**, not one per revision, or the inbox floods | High |
| **C-1** | **C — restore compatibility gate** | With two acknowledged heads and no chosen one, a clean-Mac restore has **no unambiguous default**. My answer: the new Mac asks the same comparison question once, on first restore, reusing this sheet. C must not silently pick newest | High |
| **C-2** | **C** | The comparison sheet must not offer "Continue from this one" for a side the compatibility gate would reject; if a side is incompatible with the local adapter, the sheet still shows and **exports** it, but the choose button carries C's remedy copy instead. C owns that string | Medium |
| **D-1** | **D — retention/dedupe/storage** | **Hard requirement: every divergence parent and every acknowledged head is permanently retained and exempt from all eviction, pruning, and dedupe-collapse paths.** The locked copy ("Nothing has been overwritten", "Neither version will be removed") is a promise D has to keep. **This is my highest residual risk** | **Blocking** |
| **D-2** | **D** | Both sides' 32 KB should be **fetched eagerly on detection** so offline compare and export always work | High |
| **D-3** | **D** | The resolution revision must **CAS-dedupe to the chosen side's existing sha256** and cost zero new bytes. If D's model would store a second physical copy, D-G1's cost argument weakens (though it still holds at 32 KB) | Low |
| **E-1** | **E — save state surfacing vs the frozen ladder** | E's save timeline must render **two (or N) heads** without implying one is stale, and must render **resolution and acknowledgement acts as timeline entries**. E also owns the "Compare versions" entry point in the game detail save section | High |
| **E-2** | **E** | I assert a divergence maps to the frozen ladder's **rank 1 "Needs attention"** with unchanged copy and unchanged accessible name — **no new ladder state, no new colour token**. If E wants a distinct save-conflict rung, we collide and P3 D-13 arbitrates | High |
| **F-1** | **F — launch readiness & preflight** | **Hard constraint, not a decision:** an unresolved divergence **must not block launch** and **must not be silently resolved by launching**. The device plays the side it has; preflight states it in one quiet line (copy in §10). F owns placement. **F must not put the choice in the launch path** | **Blocking** |
| **F-2** | **F** | On a device with an acknowledged (never-chosen) divergence, F's readiness must state which side this Mac follows | Medium |
| **F-3** | **F** | Nothing in this flow may add a network call to the launch path (CACH-04 / P3 D-23). My eager 32 KB fetch happens at **detection**, not at launch | Medium |
| **H-1** | **H — export shape** | I need one thing: **export a single named revision** (not just "the current save"), from a non-chosen side, reachable from this sheet, producing a folder whose manifest identifies origin and capture time in human-readable form. **H owns the layout entirely** | High |
| **H-2** | **H** | The export result string in §10 ("The folder has the exact save file and a manifest listing what's inside") is a promise about H's output; if H's manifest is named or shaped differently, H owns amending that one string in the shared artifact | Low |
| **A-1** | **A — capture trigger & loss window** | The ~24 s flush window means the last moments before a divergent quit may not be in either side. Copy never claims a version contains everything the user played — hence "You **played** {duration} here", never "{duration} of progress is in this version" | Medium |
| **A-2** | **A** | "Saves since then" counts captures, which A defines. If A coalesces captures aggressively, that count shrinks and becomes a weaker corroborant — acceptable, not blocking | Low |

---

## 20. Residual risks (honest)

1. **Retention betrayal (highest).** Every promise in this flow's copy is a promise area D
   must keep. A future pruning rule that touches a divergence parent turns the product's
   most trust-critical screen into a lie. Mitigation is D-1 plus a named exemption test —
   but the risk is organisational, not technical, and it persists past Phase 4.
2. **Play-time is a proxy, not a truth.** A user can over-weight three hours of futile
   grinding. Mitigated by wording and by showing two facts, not eliminated. Accepted:
   still strictly better than recency-only, which is what every prior-art system teaches.
3. **Adding to a frozen vocabulary.** `Attention.Reason` calls itself frozen; adding
   `save_divergence` is additive and safe, but if Phase 4 later wants three save-related
   reasons the vocabulary starts to sprawl. Mitigation: exactly one reason for this whole
   feature — divergence, not "save failed", not "save incompatible" (those are A's and C's
   surfaces).
4. **"Keep both" leaves permanent ambiguity that later features must handle.** Restore
   (C-1), a third device, and any future automation all inherit "there is no canonical
   head". This is correct behaviour and a real ongoing tax.
5. **Console/Mac string drift** is the named top long-term risk and the golden fixture is a
   mitigation, not a guarantee — a new string added to one client and not the fixture
   escapes. Mitigation: the copy test asserts the fixture is *exhaustive* for the surface,
   not merely that present strings match.
6. **Nobody may ever hit this in Phase 4 UAT with real bytes.** Checkpoint 7 is blocked on
   real emulator + real bytes; the deterministic profile proves the flow, not the physics.
   The divergence *detection* half (area B) carries that risk; G's surface is fully
   provable against seeded state.

## 21. Open questions

None blocking. The three things I would have asked are decided with a stated assumption
instead: B can express multi-parent lineage (B-1 — if not, fall back to shape (a) and
accept the timeline/concurrency cost); B can compute a fork point (B-2 — required by
SAVE-04 regardless); and D will exempt divergence parents from retention (D-1 — if not,
the feature's copy must be weakened before ship, and I would rather change the design than
the promise).
