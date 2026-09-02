---
id: SEED-017
status: dormant
planted: 2026-09-02
planted_during: v1.0 / Phase 03.5 (Mac Verification Automation)
trigger_when: when planning self-hosting onboarding, backup/restore UX, deployment adapters, or hosted operations
scope: medium-to-large — deployment UX, reliability, backup, networking, and upgrade paths
related: SEED-014 (lawful federation and content distribution)
---

# SEED-017: Offer progressive deployment modes with trustworthy defaults

## Why This Matters

Playstead should serve different levels of commitment without forcing every
person into the most complex topology. A newcomer may want a private server on
their own computer; another user may want a stable service reachable across the
home network; an advanced operator may want remote DNS, independent backup
destinations, or higher availability. The product should make the simplest
useful path turnkey while allowing deliberate scale-up and scale-down later.

Explore explicit local-only, LAN, and remote deployment modes, with honest
tradeoffs for reachability, security, cost, maintenance, availability, and
offline behavior. Backups should be easy to enable, independently stored, and
verified as restorable rather than merely reported as successful. Migration and
rollback guidance must remain understandable at every mode.

## Questions to Explore

- What is the minimum local-only setup and how can it be upgraded to LAN or
  remote access without changing the user's canonical data or client contract?
- Which defaults reduce administration safely: loopback binding, LAN discovery,
  TLS, authentication, firewall guidance, encrypted backup, retention, and
  restore drills?
- How should the UI explain “server on this computer,” “home-network server,”
  and “remote deployment” without implying high availability or managed hosting?
- Can every supported mode expose the same health, backup freshness, restore,
  capacity, and upgrade-preflight evidence?
- What are the safe paths to scale down, disable remote exposure, or recover a
  failed host while preserving exact bytes, manifests, saves, and audit history?

## When to Surface

Surface during self-hosting onboarding or the operations/backup milestone.
Start with a narrow local-to-LAN path and a verified backup/restore exercise;
defer hosted multi-tenant complexity until its separate legal, security, cost,
and SRE readiness exists.

## Notes

Captured from the owner's request for simple local, LAN, and remote deployment
choices with progressive complexity, strong defaults, and dependable automatic
restore capability. This is a planning seed, not a request to expand the current
Mac verification phase.
