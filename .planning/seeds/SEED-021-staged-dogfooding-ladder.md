---
id: SEED-021
status: dormant
planted: 2026-09-03
planted_during: v1.0 / Phase 04 (Persistent Save Continuity) planning
trigger_when: when the owner asks "can I use this yet", when planning Phase 5 exit criteria, or when writing self-hoster onboarding
scope: small-to-medium — a documented trust ladder plus the checks that let a stage be entered honestly
related: SEED-017 (progressive deployment modes), SEED-020 (Steam Deck / Linux second client)
---

# SEED-021: Define the staged dogfooding ladder — what earns the right to be the only copy

## Why This Matters

During Phase 4 planning the owner asked a question the roadmap could not answer
directly: *when can I actually start using this?* The roadmap tracks phases and
requirements, not adoption readiness, so answering required reading four
documents and reasoning about which completed capability implies which safe use.
That reasoning should be recorded once rather than re-derived every time the
question comes up — and it will come up for every self-hoster, not just the
owner.

The insight worth keeping: **usable, trustworthy, and sole-copy-worthy are three
different milestones, and they are reached in that order.** Conflating them is
how self-hosted projects lose people's data. A user who reads "Phase 2 complete:
import and export" reasonably concludes the system is ready to hold their
library; nothing in the roadmap tells them that backup and restore are still two
phases away.

The ladder as it stood at Phase 4 planning:

| Stage | What it means | Gate |
|---|---|---|
| **Additive library of record** | Import a *copy* of the collection, curate it, exercise provenance and Needs Attention on real messy data. Zero risk: import is non-destructive by contract — source untouched, storage use shown before commit. | Phases 1–2 (complete) |
| **Play from it** | Browse, download, cache, launch a proven adapter path offline on the Mac. | Phase 3 — code executed, but the real-emulator/real-bytes and signing/notarization UAT checkpoints are still `blocked` |
| **Keep progress in it** | Saves captured, queued offline, restored on a clean Mac, conflicts surfaced without last-write-wins. | Phase 4 |
| **Only copy** | Independent backup to a user-controlled destination, verified by a clean-environment restore drill. | Phase 5 — *this* is the gate, not Phase 4 |
| **Replace the incumbent** | Migrate off the existing setup (EmuDeck on the Steam Deck) for daily play. | SEED-020 second client |

The non-obvious line is the fourth one. Phase 4 makes saves *safe*; it does not
make the system a safe *sole custodian*. Only the Phase 5 restore drill does
that, because until a restore has actually been performed into a clean
environment, "backed up" is a claim rather than evidence — which is the same
distinction Phase 5's own rationale draws ("do not count a started container or
a single repository volume as successful recovery").

## Questions to Explore

- Should this ladder be surfaced *in the product* — a setup-console readiness
  panel that says which stage the deployment has earned — rather than living
  only in planning docs? The health/backup-freshness evidence Phase 5 builds is
  most of the input already.
- Can each stage's gate be a machine check rather than a human judgement? "Has a
  restore drill been completed against this deployment's actual backups, and
  when?" is answerable, and answering it in the UI is far more honest than a
  docs page.
- What does the ladder look like for a self-hoster who arrives at v1.0 with
  every phase already complete? The stages collapse into onboarding steps, but
  the sole-copy gate should still require *their* restore drill, not the
  project's.
- Does the export path (PORT-01/02) deserve a first-class role as the always-
  available escape hatch at every stage — the thing that makes entering a stage
  reversible?

## When to Surface

Surface when writing Phase 5's exit criteria and self-hoster onboarding. The
ladder is cheap to document now and expensive to retrofit after someone has
trusted the system one stage too early.

## Notes

Captured during Phase 4 planning from the owner's dogfooding question and the
answer assembled for it. The immediate practical recommendation given at the
time — start importing a *copy* of the collection now, keep playing on the
existing setup, and treat the Phase 5 restore drill as the migration gate — is
the ladder in miniature and should survive into whatever onboarding doc this
becomes.
