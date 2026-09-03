---
id: SEED-030
status: dormant
planted: 2026-09-03
planted_during: v1.0 / Phase 04 planning — fan-out research into prior art
trigger_when: before designing any feature that writes to, renames, moves, or reorganizes user files; before import onboarding work; when disc/multi-track grouping is designed
scope: reference material — informs design across many phases rather than producing one deliverable
related: SEED-029 (format normalization), SEED-028 (reference-pack onboarding), SEED-022 (collection reconciliation)
---

# SEED-030: What every ROM manager got wrong, and the two things to steal

Prior-art research (Sept 2026) across clrmamepro, RomVault, RomCenter, igir, ROMM,
Retool, EmuDeck, RetroDECK, LaunchBox, Skraper, and ES-DE. Evidence is from official
docs, wikis, and bug trackers rather than forum sentiment.

## The finding that matters most

**Destructive-by-default is the norm in this category, and even the best-designed
tool failed at it.**

- **clrmamepro, RomVault, RomCenter** all treat "conform the folder to the DAT" —
  rename, move, re-archive, delete — as the *normal* path, not an opt-in. None has a
  global dry-run. Safety nets exist but require proactive configuration.
- **RomVault** has a *confirmed* data-loss bug: mismatched internal-vs-external CHD
  hash types across two DATs caused it to permanently delete a unique 203 MB file it
  wrongly judged unneeded. Its wiki carries multiple dedicated "Delete Check" guard
  messages — the maintainers know the deletion logic is fragile.
- **RomCenter** moved all files into a working directory and re-zipped them *with
  "Rename files" disabled*; the developer did not dispute it, and declined to fix v3.
- **igir is the best-designed tool in the set** — explicit philosophy: *"Igir will
  never take surprise actions you did not specify."* Non-destructive `copy`,
  opt-in `clean`, a documented golden rule. It still produced a user report reading
  **"Kinda blew away 8TiB of ROMs doing this."** A separate issue documents repeated
  identical runs deleting progressively more files each time — non-idempotent
  deletion.

**The lesson is not "be careful."** igir was careful, stated it as policy, and lost
8TiB anyway. Non-destructive has to be a *structural* property that no flag
combination can widen — which is why the `./inbox:ro` read-only bind mount is worth
more than any amount of documented intent. A kernel guarantee cannot be argued out of
by a flag interaction.

## The sharpest cautionary tale: ROMM

ROMM is the closest direct competitor (self-hosted web library, scan → identify →
browse). Its **scanner is genuinely read-only** — docs state it does not modify,
rename, move, or delete files. But the *product* ships mutating features:

- a Rename button that corrupted filenames containing colons, and desynced DB/disk;
- a "remove from filesystem" delete that orphaned DB rows until patched;
- a rigid, case-sensitive folder convention (`n64dd/` silently fails; IGDB slug
  requires `64dd`) that led a user to restructure their library — and lose games,
  metadata, and save states on rescan.

**"The automatic path is safe" is a materially weaker claim than "no code path
touches source files,"** and users do not distinguish the two until it bites them.
Playstead currently holds the stronger line. That must stay an *invariant*, not a
habit — the moment a convenience feature writes to the inbox, the guarantee is gone
and the marketing claim becomes the ROMM claim.

Corollary: **forcing a folder convention is itself a destructive act**, even with
zero direct writes, because the user performs the destruction on the tool's behalf.
Onboarding must adapt to the user's existing layout.

## Two things to steal outright

1. **igir's dual-hashing of headered formats.** It computes *both* headered and
   headerless checksums for NES/SNES/Lynx/FDS/A78, which structurally eliminates the
   single most common "why doesn't my ROM match" complaint in the entire ecosystem.
   Playstead's `blob_fingerprints` headerless writer (02-10) is the same idea —
   computing both is the completion of it.
2. **igir's hierarchical hash escalation.** CRC32+size as a cheap baseline, escalating
   to MD5/SHA1/SHA256 only as the DAT requires. The most rigorous identification model
   found, and cheap.

Worth noting but lower priority: `link` mode (symlink/hardlink/reflink) as a
non-destructive way to build an organized *view* — though EmuDeck and RetroDECK both
demonstrate that path durability is the hard part (symlinks silently broken by
updates; a metadata-folder rename destroyed days of scrape work).

## Onboarding lessons

- **The fusion point is where users get burned.** Bad tools conflate "tell me what I
  have" with "fix my folder to match" into one irreversible step. Good ones separate
  identification from action absolutely. Playstead's import → receipt → attention flow
  is already the right shape.
- **Multi-disc / multi-track handling is the universal new-user drop-off**, across
  LaunchBox, igir, ROMM, and EmuDeck. Every ecosystem converged on M3U playlists, and
  "imports every `.bin` track as a separate game" is the canonical beginner disaster.
  **Playstead should group disc sets automatically at identification time** rather than
  requiring users to learn M3U conventions. This is a concrete, high-value design note
  for whenever disc systems are properly supported.
- **Hash-first identification with filename as a visibly-lower-confidence fallback**
  is measurably more robust than filename matching, which degrades badly on real-world
  names (fan translations, odd region tags, nonstandard revision markers). Playstead
  already does this; the research confirms it is the right call.
- **Self-hosted deployment friction is itself an onboarding failure mode.** ROMM's
  largest issue cluster is Docker/DB migrations, secrets not passing through compose,
  and total data loss on redeploy from unmounted volumes — plus OIDC/SSO breaking
  across nearly every provider. Relevant twice over: it is exactly the class of
  problem hit during this session's first cold start, and it is a warning about
  SEED-025's SSO ambitions.

## Notes

Requested by the owner as a fan-out: *"there's like some existing ROM manager tools
that might've already handled a lot of this — could reuse them or take lessons
learned, pros cons examples footguns anti-patterns."*

The net read: Playstead's core custody architecture is already better than every tool
surveyed, and the risk is not that the design is wrong — it is that a future
convenience feature quietly relaxes it, which is precisely how ROMM ended up with a
read-only scanner and a data-corrupting rename button in the same application.
