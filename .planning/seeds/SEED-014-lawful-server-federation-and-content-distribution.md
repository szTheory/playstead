---
id: SEED-014
status: dormant
planted: 2026-09-01
planted_during: v1.0 / Phase 03.5 (Mac Verification Automation)
trigger_when: when planning multi-server discovery, library federation, lawful homebrew distribution, shared backup, or non-origin blob transfer
scope: large — protocol, trust, privacy, abuse, legal, and distributed-systems research programme
related: SEED-003 (indie/homebrew marketplace), SEED-013 (real-device compatibility lab)
---

# SEED-014: Explore lawful Playstead server federation and content-addressed peer distribution

## Why This Matters

Independent Playstead owners may eventually want to connect servers for selected
purposes: discover another person's public homebrew catalogue, follow a trusted
publisher, share explicitly authorized metadata or save-independent library
records, mirror public redistributable artifacts, or help replicate a user's own
export and backup. Content digests already provide integrity evidence, so a future
transfer plan could theoretically resolve an authorized blob from more than one
source, including an origin server, trusted mirrors, or a BitTorrent-style swarm.

That transport possibility must not become a copyrighted-ROM search, tracker,
magnet-link catalogue, ownership-circumvention story, or implicit permission to
redistribute private content. The current user-supplied/private-content posture
remains the default. Any experiment should begin only with artifacts whose
redistribution rights are explicit—such as project-owned fixtures, permissively
licensed homebrew, publisher-authorized releases, or a user's own encrypted
backup—and should keep discovery, authorization, integrity, and transport as
separate contracts.

Federation also exposes more than bytes. Server addresses, collection membership,
content hashes, peer IP addresses, availability timing, and download behavior can
reveal a person's interests or possession claims. A content hash is not anonymous,
proof of ownership, proof of legality, or authorization. Private-library hashes
must not be broadcast or used as global discovery keys by default.

The product shape may need to distinguish two legitimate personas: a **collector**
who wants to maintain and archive a broad library, and a **player** who wants a
small set of known-good games available quickly. A future, explicitly authorized
**depot** could address that difference by exposing signed manifests and
checksum-verified transfers from a user's own server, a paired server, or a
lawful publisher/homebrew source. A per-artifact magnet or other swarm transport
is only a possible adapter—not a license, discovery catalogue, or acquisition
workflow—and must preserve rights declarations, authorization, privacy, quotas,
and local full-byte verification.

## Research Questions

### Product boundaries

- What does “connect servers” mean: follow public publisher feeds, browse a
  friend-approved catalogue, transfer an explicitly shared artifact, replicate
  an encrypted backup, or merge identities/curation? Treat these as different
  capabilities rather than one federation toggle.
- Which records stay server-local, which may be selectively disclosed, and can a
  user preview and revoke every disclosure without breaking their local library?
- Does federation belong in Playstead core, an optional adapter, or a separate
  service that speaks a narrow signed manifest protocol?

### Trust and security

- Define mutual authentication, per-peer capability grants, key rotation,
  revocation, replay protection, signed manifests, quotas, rate limits, and
  durable audit receipts before remote fetch is possible.
- Treat peer URLs, redirects, DNS changes, manifests, filenames, archives, and
  claimed hashes as untrusted. Model SSRF, DNS rebinding, request smuggling,
  decompression bombs, parser exploits, malicious peers, eclipse/Sybil attacks,
  amplification, disk exhaustion, and poisoned availability claims.
- Verify exact bytes locally before commit; never let peer agreement replace the
  canonical full-stream digest and size checks.

### Privacy, law, and abuse

- Model what a tracker, DHT, peer, ISP, server operator, and observer can infer.
  Investigate private swarms, encrypted payloads, capability URLs, relays, and
  origin-only modes without describing any as anonymous by default.
- Establish rights declarations, publisher signatures, takedown and revocation
  propagation, repeat-abuse handling, jurisdiction, logs/retention, and a response
  when an authorized release later becomes unavailable or compromised.
- Keep BIOS files, private imports, saves, credentials, and personal curation out
  of public discovery and public swarms.

### Prior art and failure modes

- Study BitTorrent trackers/DHT/private torrents, IPFS-style content addressing,
  Syncthing-style trusted replication, Tahoe-LAFS-style capability/encryption
  models, OCI/Nix-style signed artifact distribution, ActivityPub federation,
  package registries, Linux distribution mirrors, and lawful game/homebrew stores.
- For each, record what scaled, what leaked metadata, how identity and revocation
  worked, which incentives attracted healthy seeders, how abandoned content was
  handled, and where moderation, abuse, centralization, compatibility, or user
  experience failed.
- Look specifically for operational postmortems and community experience, not
  just protocol descriptions or enthusiastic launch material.

## When to Surface

**Trigger:** when planning multi-server discovery, library federation, lawful
homebrew distribution, shared backup, or non-origin blob transfer.

Surface only after the single-server custody, export, authorization, backup, and
client convergence contracts are proven. Require a threat model and a narrow
legal-content spike before adding peer discovery or distributed transfer to any
roadmap.

## Scope Estimate

**Large.** The first useful step is a research/spec milestone that separates
federated metadata, authorized sharing, backup replication, and multi-source
transport. Any implementation should start with two explicitly paired servers
and signed manifests for project-owned test artifacts—not an open public DHT.

## Breadcrumbs

- `.planning/PROJECT.md` — private user-supplied content, exact-byte custody,
  export, security, compatibility, and commercialization constraints
- `.planning/research/PITFALLS.md` — explicit warning against allowing a private
  organizer to drift into public sharing/search/acquisition or hosted distribution
- `.planning/discovery/TECHNICAL-RISKS.md` — full-stream digest identity,
  bounded transfer, authorization, and untrusted-input boundaries
- `.planning/research/ARCHITECTURE.md` — local storage first and deliberate
  avoidance of early distributed-system complexity
- `.planning/seeds/SEED-003-indie-rom-marketplace.md` — possible lawful
  publisher/homebrew source and the separate-product question

## Notes

Captured during Phase 03.5 from the owner's question about connecting independent
Playstead servers and optionally using torrent-hash-style multi-source delivery.
This is a research seed, not approval to build an acquisition feature or relax
the project's content posture.
