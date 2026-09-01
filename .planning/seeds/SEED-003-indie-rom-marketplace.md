---
id: SEED-003
status: dormant
planted: 2026-08-31
planted_during: v1.0 / Phase 3 (mac-offline-play-vertical-slice) UAT
trigger_when: any milestone or phase that touches catalogue provenance, asset acquisition/sources, multi-user or account identity, payments, or community/social surfaces (reviews, ratings) — also surface during `/gsd-new-milestone` requirements gathering for any post-v1.0 milestone
scope: large — new business model, likely a separate product surface
---

# SEED-003: Indie/homebrew ROM marketplace — "Gumroad for indie retro ROMs"

## Why This Matters

Owner-stated intent (2026-08-31, during Phase 3 UAT): Playstead is accidentally
building most of the platform an indie/homebrew retro-console storefront would
need. The idea: make it easy for Playstead users to **buy homebrew and indie
games for retro consoles**, give developers a distribution channel, add reviews
and discovery, and create a funding path for Playstead itself.

Framing the owner used: *"kind of like Gumroad but for ROMs for indie ROMs"* —
explicitly **not** Steam-style DRM, because there is no DRM story for a ROM.
The sale is of a file plus goodwill, patronage-style, not of an enforcement
mechanism.

**Hard constraint stated at the same time:** Playstead stays **open-source
first**. Any monetization must not compromise that. This is a possibility being
recorded, not a commitment — treat it as an option to evaluate, and never let it
retroactively justify closing down parts of the core product.

## Why Playstead Is Unusually Well-Positioned

The custody spine built in Phases 1–3 is most of the hard part of a ROM
storefront, and it was built for other reasons:

- **Content-addressed, digest-verified assets** — a purchased ROM is just
  another verified blob; integrity and "you got the exact bytes" are solved.
- **Provenance recorded as a client-supplied claim** (Phase 2 import receipts) —
  already models "where did this file come from," which a storefront needs to
  extend with "purchased from developer X on date Y."
- **The change-journal / snapshot / cursor spine** — entitlements and library
  additions are just another entity kind on an existing sync path.
- **Curation nouns already exist** (Favorites, Collections, Queue, Continue,
  Recent) — reviews/ratings would join that vocabulary rather than invent one.
- **Per-user scoping is already enforced** (Phase 3, 03-04) — every curation
  query and mutation is scoped to the owning user, with cross-user access
  returning 404.

## Open Questions (answer when this surfaces)

**Market / scene**
- Does this scene already exist? Check itch.io's retro/homebrew categories,
  romhacking.net's homebrew sections, Nintendo Age / AtariAge storefronts, the
  physical-cart homebrew publishers (Limited Run, Broke Studio, Mega Cat),
  and PICO-8/TIC-80 adjacent communities. **Is Playstead solving distribution
  or just re-listing itch.io?**
- Who is the actual customer — the player who already self-hosts, or the
  developer looking for reach? Those imply very different products.
- Could an optional ecosystem help homebrew become a more professional and
  economically viable publishing path without turning Playstead into a generic
  content dump? Study the quality-versus-quantity and discovery problems faced
  by large stores, including how to discourage shovelware without creating an
  opaque or exclusionary gate.
- Developer incentives depend on credible demand. Do not recruit publishers or
  build payment infrastructure until Playstead can demonstrate an audience large
  and engaged enough to justify their release, support, and compliance costs.

**Product**
- Is this inside Playstead, or a separate service Playstead can *connect* to?
  A federated/optional source keeps the open-source core clean.
- Without DRM, what is actually sold — the file, a support relationship, or
  status/updates? What stops resale, and do we care?
- Reviews and ratings: a new social surface with moderation costs. Is that in
  scope, or do we lean on an existing community?
- What mix of editorial curation, transparent quality signals, refunds, demos,
  update history, compatibility evidence, community reporting, and developer
  reputation could preserve discovery quality without promising that every
  listed title is good or safe?
- How does a purchased ROM differ from an imported one in the library? Does it
  get a distinct provenance badge and status-ladder treatment?

**Business / legal**
- Payment rails, payouts, taxes, refunds for a non-refundable file.
- Liability and curation duty for user-uploaded ROMs (DMCA-adjacent risk if
  anything non-homebrew slips in). This is the biggest unpriced risk.
- How does revenue flow back to Playstead development without conflicting with
  open-source-first? (Sponsorship? A cut? Optional hosted service?)

**Relationship to existing seeds**
- [[SEED-001]] save-file curation — a purchased-game library and a treasured-save
  library are the same "things I care about" surface.
- [[SEED-002]] physical cartridge save continuity — the homebrew scene overlaps
  heavily with physical-cart publishers; same audience.

## Scope Estimate

**Large.** Touches catalogue provenance, a new entitlement entity kind on the
sync spine, accounts/identity beyond a single self-hosted owner, payments, and a
community moderation surface. Almost certainly its own milestone (or its own
product) rather than a phase inside the current one.

## Breadcrumbs

- `.planning/PROJECT.md` — core value: bytes stay under the user's control; check
  any storefront design against this before committing
- `playstead-server/lib/playstead/curation.ex` — the five curation nouns reviews
  and purchased-library entries would join
- Phase 2 import receipts / provenance-as-client-claim — the provenance model a
  purchase record would extend
- `.planning/phases/03-mac-offline-play-vertical-slice/03-04-SUMMARY.md` — per-user
  scoping already proven (D4), the foundation multi-user would build on

## Notes

Captured verbatim-in-spirit from an owner remark during Phase 3 UAT. Explicitly
a "loose thought" — the owner flagged it as a possibility, not a plan. Enrich
with `/gsd-capture --seed --enrich SEED-003` if the market research above firms
it up.

Owner follow-up (2026-09-01, Phase 03.5): EmuDeck's store made the opportunity
feel more concrete, but also highlighted that this is a distinct ecosystem and
go-to-market problem. Any future exploration should explicitly test publisher
incentives, audience critical mass, catalogue quality, shovelware resistance,
and whether a separate interoperable project is healthier than embedding a
store in Playstead.
