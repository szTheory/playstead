# Naming Decision: Playstead

**Checked:** 2026-08-26  
**Status:** **Playstead selected** as the project and ecosystem family name by the project owner on 2026-08-26.
**Scope:** preliminary product, search, GitHub, app-store, package-ecosystem, and obvious trademark-collision screening. This is **not** trademark, company-name, domain, or legal clearance.

## Decision

Use **Playstead** as the project name, workspace name, and shared family for first-party components:

```
playstead/
  playstead-server/
  playstead-mac/
```

The protocol remains part of the server boundary until a stable contract and another proven consumer justify `playstead-protocol`. Likewise, web delivery remains inside the Phoenix server unless an independent deployment boundary emerges. The family name does not force a multi-repository architecture.

**Rationale:** after several deliberately varied naming tournaments, the owner preferred Playstead over the remaining candidates. It is a short, pronounceable real-word construction that suggests a place set aside for play without saying ROM, retro, cloud, archive, or a specific platform. It supports descriptive component names while leaving the product subtitle to explain the literal value.

**Provenance:** direct project-owner decision in the project discovery conversation, 2026-08-26. Earlier recommendations and their retractions remain below so future work can audit rather than repeat the failed screening process.

**Clearance boundary:** this decision authorizes internal project and folder naming. Before a public GitHub organization, package namespace, app listing, marketing site, or commercial offering, rerun live namespace, domain, app-store, and relevant trademark checks. This document does not claim legal availability.

## Retraction of the prior recommendation

The earlier version of this document recommended **Ludessa**, with **Rellia** and **Asterism** as alternatives. That recommendation is withdrawn in full. Independent verification found disqualifying exact-name collisions that the first pass failed to catch:

| Retracted name | Disqualifying finding | Decision |
|---|---|---|
| **Ludessa** | Current 2026 dating app and an EU-registered mark. | Reject. Do not use in a product, organization, repository, package, or app name. |
| **Rellia** | Active health-tech and real-estate software companies; `github.com/rellia` occupied. | Reject. Exact GitHub identity alone makes it unsuitable for this repository family. |
| **Asterism** | Multiple active open-source projects, including game-engine research work. | Reject. Too crowded in the exact technical/game neighborhood. |

The original pass gave too much weight to superficial web absence. It did not reliably establish GitHub identities, current app presence, and non-web registry results. Nothing in that prior shortlist should be treated as available.

## Stricter acceptance rule

A name may enter a public shortlist only if this preliminary screen finds **none** of the following:

1. an active exact-name commercial app or company;
2. an exact GitHub user or organization that would obstruct the parent identity or expected repo family;
3. a current open-source software/game project using the exact name;
4. an obvious software/game trademark collision; or
5. a search result so dominated by an existing product, game, or package that users would not find this project reliably.

Every surviving candidate would additionally need a live, manual check of GitHub, npm, Hex, crates.io, PyPI, App Store, Google Play, desired domains, and relevant trademark registries. Absence from a search index is never proof of availability.

## Historical result before the Playstead decision

Under the stricter rule, this research cannot responsibly nominate even one public name. The candidate pool was intentionally reset rather than padded with loosely screened, invented “SaaS-like” names. A mark that only looks clean in a search result is not a useful family name when it must support `-server`, `-mac`, and `-protocol` repositories and, eventually, an app and a hosted offer.

**Superseded working-name decision:** the research initially retained **`emu-server`** for the Mac spike and internal code. The owner subsequently selected Playstead. The caution against creating a public organization, package namespace, marketing site, app listing, or paid offering without a fresh clearance pass remains active.

## Product-fit guidance for the next naming sprint

The eventual name should be one coherent parent with a descriptive subtitle, not a set of brands:

> **[Family] — your personal game library**

or:

> **[Family] — your games, ready where you are**

Use a simple technical family only after the boundary is real:

```
<family>-server
<family>-mac
<family>-protocol       # only after the protocol stabilizes
<family>-adapter-retroarch
<family>-docs
```

The name should evoke a personal place, a return, a considered collection, or continuity **without** saying ROM, retro, download, archive, vault, cloud, ownership, or preservation. Prefer a confident, natural compound or an uncommon real word over a stream of soft pseudo-Latin names. The subtitle can do the literal explaining; the mark must carry recall and distinction.

### Directions worth developing, not candidates

These are semantic territories, deliberately **not** recommendations or cleared names:

| Direction | Product meaning | Guardrail |
|---|---|---|
| **A return to a familiar place** | Resume a game and progress on a new machine | Avoid direct “replay,” “reprise,” “return,” or “savepoint” words—they are crowded. |
| **A small, curated room / cabinet** | A personal library, not an infinite public catalogue | Avoid archive/vault/collection metaphors that imply permanent custody or generic storage. |
| **A dependable relay** | The system carries exact files and proven saves between devices | Do not promise universal sync, availability, or preservation in the mark. |
| **A quiet instrument** | Polished, local-first software that stays out of the way | Avoid music terms already used by media and developer tools. |
| **A constellation of chosen things** | Favorites, collections, devices, and adapters forming a coherent whole | Avoid astronomy nouns already occupied by open-source or game projects. |

## Previously screened names now rejected

| Name(s) | Reason |
|---|---|
| Ludessa, Rellia, Asterism | Retracted; see above. |
| Veyra | Current game, Discord RPG work, technology studio, and apps. |
| Meldra | Current GitHub coding-agent project. |
| Calyra | Current App Store health app and AI/technology companies. |
| Dulora | Active lighting brand/direct domain. |
| Avenori | Current consumer brands/domain use. |
| Orlune | Active skincare brand. |
| Virelia | Active domain plus US trademark application. |
| Sereva | Multiple active consumer brands and domain use. |
| Ludora, Ludra | Current open-source game tool, iGaming, mobile-game, and HR/industrial products. |
| Averune | Current mobile RPG, B2B software, and GitHub coding agent. |
| Kivora, Noreva, Havelo | Active software/consumer companies. |
| Cairnwood | Active registered trademark/company use; fails exact-company/mark rule. |
| Cadenza, Tessera, Continuo, Reprise, Keepsake | Ordinary or highly reused words; poor search and clearance economics. |

## Evidence ledger

All entries were checked on **2026-08-26**. These sources support specific collision findings; they do not establish availability for any other name.

| Check | Evidence |
|---|---|
| Ludessa retraction | Independent verification reported a current dating app and EU-registered mark; re-run a formal EUIPO search before any future reconsideration. |
| Rellia retraction | Independent verification reported active health-tech and real-estate software companies and the occupied GitHub identity; direct GitHub identity must be checked before any future reconsideration. |
| Asterism retraction | Independent verification found several active open-source projects, including game-engine research; exact technical overlap is disqualifying. |
| Veyra | [itch.io game](https://mrderpface.itch.io/veyra), [GitHub project](https://github.com/Sylver-Icy/Veyra), [technology studio](https://www.veyradev.com/) |
| Meldra | [Active GitHub repository](https://github.com/ruhuang2001/meldra) |
| Calyra | [App Store app](https://apps.apple.com/us/app/calyra-ai-calorie-tracker/id6748324995), [technology studio](https://calyratech.com/) |
| Dulora | [Active direct-domain brand](https://dulora.com/) |
| Avenori | [Active consumer brand](https://avenori.shop/) |
| Orlune | [Active skincare brand](https://www.orlunecare.com/story) |
| Virelia | [Active domain](https://virelia.ai/), [trademark application record](https://trademarks.justia.com/992/92/virelia-99292767.html) |
| Sereva | [Active consumer brand](https://buysereva.com/), [registered-domain evidence](https://ro.namespedia.com/details/Sereva) |
| Ludora / Ludra | [Open-source game-tool suite](https://www.ludora.studio/terms.html?v=c2456bd0), [iGaming software](https://ludora.tech/), [HR SaaS](https://ludra.com.br/) |
| Averune | [Mobile RPG](https://play.google.com/store/apps/details?id=com.averune.game), [B2B SaaS](https://averune.tech/), [GitHub coding agent](https://github.com/con-tinue/Averune) |
| Cairnwood | [Registered trademark](https://trademarks.justia.com/880/45/cairnwood-88045689.html), [active company](https://find-and-update.company-information.service.gov.uk/company/NI721996) |
| Candidate package/identity check surface | [GitHub repository search](https://github.com/search?q=NAME&type=repositories), [npm](https://www.npmjs.com/search?q=NAME), [Hex](https://hex.pm/packages?search=NAME), [crates.io](https://crates.io/search?q=NAME), [PyPI](https://pypi.org/search/?q=NAME) — replace `NAME` with each finalist and record a dated result. |

## Required next step before public release

Run a focused Playstead clearance pass before public release, with a trademark professional or specialist where commercial use is contemplated. Record:

1. exact and confusingly similar results in the applicable trademark classes/jurisdictions;
2. `.com` and acceptable alternate-domain status;
3. GitHub organization/user plus the expected `playstead-server`, `playstead-mac`, and possible `playstead-protocol` slugs;
4. npm, Hex, crates.io, and PyPI name status;
5. Apple and Google app-store exact-name results; and
6. an audio/spelling test with people who are not emulation enthusiasts.

If a material collision appears, revisit the public mark without undoing the technical architecture or losing this decision history.
