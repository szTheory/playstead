---
id: SEED-028
status: dormant
planted: 2026-09-03
planted_during: v1.0 / Phase 04 planning — owner's first real import on a clean stack
trigger_when: whenever there is appetite for a small console UI change, or when import onboarding is revisited
scope: small for the copy and empty state; medium if pack acquisition is ever assisted
related: SEED-022 (collection reconciliation), SEED-024 (first-run TLS trust), SEED-025 (credential UX)
---

# SEED-028: `/reference-packs` explains its errors beautifully and its purpose not at all

## Why This Matters

On his first real import the owner copied a game in, saw
`no_reference_installed` on the receipt, navigated to `/reference-packs`, and
could not tell what he was supposed to do:

> "I'm at /reference-packs — I'm not really sure what to do there. Should it be
> more self-explanatory? Do we have to connect to a reference pack? Could this
> be automated, or onboarding for this made simpler?"

This is a first-run comprehension gap, not a functionality gap. The page works.
The problem is that **all of its written copy is failure copy**. Every message
on the screen is about what went wrong:

- "Choose a reference pack file first."
- "This file is larger than Playstead will read as a reference pack. Nothing was stored."
- "This file doesn't look like a valid reference pack. Nothing was stored."
- "This file could not be read as a reference pack. Nothing was stored."

That error copy is genuinely excellent — precise, honest, and it always says
what happened to the user's data. But nothing on the page answers the three
questions a new user actually has, *before* they have a file to upload:

1. **What is a reference pack?** (A datfile of known-good names and hashes that
   lets Playstead identify what a blob actually is, independent of its filename.)
2. **Where do I get one?** (No-Intro and Redump publish them; the format is
   Logiqx XML — `Playstead.Recognition.LogiqxHandler`.)
3. **Why isn't one included?** (D-18: nothing is ever fetched, bundled, or
   committed; packs are administrator-supplied and never reach the network.)

Point 3 matters most, because the absence looks like an oversight rather than a
deliberate posture. A user who does not know it is deliberate reasonably
concludes the feature is broken or unfinished.

The receipt reason `no_reference_installed` is well-named and already tells the
user the right thing — but it is a dead end. It names a missing prerequisite
without linking to the page that satisfies it, or explaining what satisfying it
involves.

## What Would Fix It (small, in rough value order)

- **A real empty state on `/reference-packs`.** One short paragraph answering
  the three questions above, shown when no packs are installed. This alone
  probably closes the gap.
- **Link `no_reference_installed` to `/reference-packs`.** The receipt names
  the prerequisite; it should route there.
- **Name the expected format visibly** — Logiqx XML datfile — with a note that
  `.dat` and `.xml` are both normal extensions for it.
- **Say what a pack does and does not change.** It adds identification evidence;
  it never modifies stored bytes. Users who have been burned by ROM managers
  that rename and reorganize files will assume the worst unless told.
- **State the privacy posture as a feature.** "Playstead never fetches packs;
  you supply them" is reassuring once said out loud, and invisible until then.

## The automation question (open, and legitimately separate)

The owner asked whether pack installation could be automated, and reasoned that
fetching a *datfile* is a materially different act from fetching a game. That
distinction is real and worth recording plainly: **a datfile is metadata — names,
sizes, and hashes — not game content.** Auto-fetching one is not the excluded
behaviour in `PROJECT.md`'s Out of Scope list, which is about ROM/BIOS
distribution and acquisition assistance.

What would still need deciding before automating it:

- **The no-network posture (D-18) is deliberate**, and currently absolute for
  this subsystem. Introducing a fetch means an outbound dependency, a trust
  decision about the source, and a supply-chain question (what if the fetched
  pack is tampered with?). Pinning by hash, as the project already does for the
  emulator adapter, is the obvious mitigation.
- **The datfiles have their own terms.** No-Intro and Redump publish under their
  own conditions; redistributing or auto-fetching them is a licensing question
  about *their* work, independent of any ROM question.
- **A middle path exists and may be the right one:** do not fetch, but make
  supplying a pack trivial — name the exact file to get, link where to get it,
  accept a drag-and-drop, and verify it clearly. That preserves the posture and
  removes almost all of the friction, which is what the owner actually asked for.

## Notes

Captured during the owner's first real import. Worth pairing with the finding
from that same session: he imported a PlayStation `.chd`, which no reference
pack can identify regardless — `.chd` is not among the six supported validators
(`gb`, `gba`, `md`, `nes`, `psx_cue`, `snes`), and Redump datfiles hash raw disc
tracks rather than the CHD container. So "install a pack" would not have helped
that particular file, and a user could reasonably install one, see the same
result, and conclude the feature is broken. The empty state should set
expectations about *which* content packs can identify.
