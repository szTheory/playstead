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
