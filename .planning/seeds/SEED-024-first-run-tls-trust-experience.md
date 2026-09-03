---
id: SEED-024
status: dormant
planted: 2026-09-03
planted_during: v1.0 / Phase 04 (Persistent Save Continuity) planning
trigger_when: when writing self-hoster onboarding, revising docs/DEPLOY.md, or planning the setup wizard's first-contact experience
scope: small-to-medium — documentation plus an optional trust-helper command; touches the pairing fingerprint story
related: SEED-017 (progressive deployment modes), SEED-021 (staged dogfooding ladder)
---

# SEED-024: Make the first-run certificate warning an answered question, not a scary page

## Why This Matters

The very first thing a self-hoster sees after `docker compose up -d` and opening
the console is a browser interstitial: **"certificate authority invalid."** They
must click through a red warning page that browsers deliberately design to feel
dangerous, in order to reach a product whose entire pitch is *custody, safety,
and trust*.

That is a bad first impression for any product, and an actively contradictory
one for this product. The owner hit it immediately and asked the obvious
question — *"is there a way to fix that? It's kind of the first obvious question
anyone would have."* He is right that it is the first obvious question, and
right that it deserves an answer better than "click through."

What makes it worse: clicking through the warning is exactly the habit an
attacker needs a user to have. Teaching a self-hoster, on day one, that
Playstead is the app where you bypass certificate errors is teaching precisely
the wrong reflex — and this project already treats certificate identity as
load-bearing elsewhere (D-13 mounts `caddy_data:/caddy_data:ro` into the app
specifically so the Devices page can display the root-CA fingerprint for
pairing-time client pinning).

So the infrastructure for a good answer already exists; it just is not pointed
at the browser. The root CA is sitting in the `caddy_data` volume at
`/data/caddy/pki/authorities/local/root.crt`, and the app can already read it.

## Questions to Explore

- **Ship a trust helper.** A documented one-liner (or a `make trust` / small
  script) that extracts Caddy's root certificate and adds it to the OS trust
  store — macOS Keychain, Linux `ca-certificates`, Windows cert store. Extracting
  it is a single `docker compose cp`; the platform-specific trust step is the
  only real work. Verified working on macOS:
  `security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain <root.crt>`
- **Show the fingerprint where it can be compared.** Print the root CA's SHA-256
  fingerprint at first boot alongside the setup token, so a user can verify the
  certificate their browser is objecting to is genuinely the one their own
  server just generated. That turns "click through a warning" into "confirm a
  fingerprint" — the same discipline the pairing flow already uses for the Mac
  client, extended to the browser.
- **Say it before they hit it.** `docs/DEPLOY.md` step 4 sends the user to
  `https://localhost/setup` without warning them that the browser will object or
  explaining why it is expected. One paragraph at that exact point, plus the
  trust command, removes the entire surprise.
- **Distinguish the two legitimate paths.** Caddy's internal CA (localhost/LAN,
  needs manual trust) versus a real domain with a publicly trusted certificate
  (`PLAYSTEAD_DOMAIN`, no warning at all). The docs already support both; the
  onboarding does not make the tradeoff visible at the moment it matters.
- **Does the Mac client care?** It pins the root CA fingerprint deliberately, so
  it is unaffected — but the *asymmetry* is worth documenting: the native client
  has a rigorous trust story while the browser has a click-through. Explaining
  why is reassuring rather than embarrassing.

## When to Surface

Surface when writing self-hoster onboarding, or immediately if anyone else
starts using this. It is cheap — mostly documentation plus a small helper — and
it is the literal first interaction a new user has with the product.

## Notes

Captured from the owner's own first run during Phase 4 planning, on a stack
brought up at `https://localhost:18443`. He accepted the browser risk page to
proceed, which is exactly the behaviour this seed exists to make unnecessary.

Practical detail for whoever implements it: the certificate lives in the
`caddy_data` volume and can be pulled with
`docker compose cp caddy:/data/caddy/pki/authorities/local/root.crt <dest>`.
Its subject is `CN=Caddy Local Authority - <year> ECC Root`, and it is
regenerated whenever the `caddy_data` volume is destroyed — so any documented
trust step must be repeatable, and must say so.
