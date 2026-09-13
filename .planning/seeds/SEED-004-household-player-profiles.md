---
id: SEED-004
status: dormant
planted: 2026-08-31
planted_during: v1.0 / Phase 3.5 (mac-verification-automation)
trigger_when: when relevant
scope: unknown
---

# SEED-004: Household and multiple-player profiles

## Why This Matters

Owner-stated future idea: allow other people to play through one Playstead
installation while keeping each person's experience distinct. This might mean
lightweight profiles beneath one owner account, separate authenticated user
accounts, or a deliberate combination of both.

This is intentionally **not** part of Phase 3.5. The current single-owner model
should remain simple until a later milestone explicitly chooses an identity,
authorization, sharing, and data-ownership model.

## Questions to Resolve When This Surfaces

- Are household players profiles owned by one account, full accounts, or both?
- Which data is per-player: favorites, collection membership/order, queue,
  recent/continue state, play history, controller mappings, and saves?
- Is the imported library shared by default, and can the owner restrict games
  or systems for a profile?
- Who owns and can export save data created by another player?
- How do device pairing, offline access, revocation, and profile switching work
  without weakening the existing security boundary?
- Do guests need durable identities, PINs, parental controls, privacy between
  profiles, or conflict handling when two players use the same game?
- How should this evolve from today's user-wide, cross-system collections
  without forcing unnecessary migrations or changing their current meaning?

## Breadcrumbs

- `playstead-server/priv/repo/migrations/20260830000001_create_curation_ordered_lists.exs`
  — current collections and members are scoped directly to `user_id`
- `playstead-server/priv/repo/migrations/20260830000000_create_curation_favorites.exs`
  — current favorites are scoped directly to `user_id`
- `playstead-server/lib/playstead_web/router.ex` — current curation mutation
  boundary
- `.planning/PROJECT.md` — data ownership, offline, security, and export
  constraints that any profile model must preserve

## Notes

Captured from an owner remark while reviewing the curation schema. Resurface
only when a future milestone touches household identity, authorization,
per-player saves/history, or shared-library policy. Treat profile-versus-account
as an open product and security decision, not an implementation assumption.

## Owner restatement, 2026-09-13 (Phase 03 UAT session)

Re-raised unprompted while hand-testing save capture, which is telling: the
concrete pain is **save collision**, not account management. The owner's framing:

- **Nintendo Switch-style profile switching** is the mental model — pick who is
  playing, then play.
- **Separate logins are explicitly NOT assumed necessary.** "I don't know if it
  really needs separate logins" — lightweight local profiles under the one owner
  account may be enough. Do not let this drift into a full auth project by default.
- The driving scenario is two people in one household playing the same game on the
  same installation, and their saves not colliding — "namespaced by the user
  somehow."
- **Explicitly requested for when this surfaces:** research prior art before
  designing. Best practices, anti-patterns, pitfalls and lessons learned from other
  ROM launchers, frontends and the consoles themselves (Switch, Steam Deck / Steam
  Cloud per-user saves, EmuDeck, Playnite, LaunchBox, RetroArch playlists/profiles).
  See also SEED-007 (EmuDeck study) — the two should probably be researched together.

### Why the save dimension is the sharp end

Today a battery save has exactly one home per title, with no player dimension in
the path at all:

    ~/Library/Application Support/Playstead/saves/<asset_set_id>/<rom name>.sav

Two players on one install therefore overwrite each other's progress, silently,
with the existing save-continuity machinery working exactly as designed. The
capture/revision/conflict lane (Phase 04) records `save_revision` and
`save_line` rows with no notion of who authored them, so retrofitting a player
dimension later means a migration of save history, not just a new column on a
profile table. That ordering argument is the main reason to think about this
before the save model hardens further, even if the feature ships much later.

### Additional questions this restatement raises

- Can a profile be chosen at **launch time** (a Switch-style picker) rather than
  being a logged-in session, and what is the least mechanism that makes saves
  correct?
- Does a profile need to exist on the **server** at all, or can it be
  device-local, with the server only seeing per-profile save lines?
- What happens to the **existing single-player saves** on upgrade — do they become
  the owner's profile silently, and can that be undone?
- Is a profile allowed to play **offline** on a device paired by the owner, and
  does revoking a profile revoke its saves?
