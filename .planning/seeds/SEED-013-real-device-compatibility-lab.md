---
id: SEED-013
status: dormant
planted: 2026-09-01
planted_during: v1.0 / Phase 03.5 (Mac Verification Automation)
trigger_when: when planning a second client or adapter, publishing compatibility claims, or supporting handheld, living-room, or homebrew hardware
scope: large — staged compatibility programme plus optional physical device lab
related: SEED-007 (EmuDeck study and relationship options)
---

# SEED-013: Build an evidence-backed real-device compatibility matrix and hardware lab

## Why This Matters

Playstead's long-term client family may span common PC handhelds, Steam Deck,
ROG-class devices, Retroid-class Android handhelds, and homebrew-capable PSP or
Vita hardware. The market is proliferating too quickly for a vague "works on
handhelds" promise to stay trustworthy. A public compatibility matrix should
name the exact device, operating-system image/version, Playstead client, emulator
or core, controller/input path, system, content type, BIOS posture, save type,
and tested result.

Most of that matrix can begin with contract tests, emulated environments, and a
small number of deliberately supported reference configurations. Later, if user
demand and maintenance capacity justify it, a physical device lab could run
automated smoke journeys on real hardware: pair, synchronize catalogue state,
download and verify legal homebrew content, launch offline, exercise controller
navigation, capture a persistent save, reconnect, and prove restoration. Manual
exploratory checks should remain part of the evidence where hardware behavior
cannot be automated honestly.

The lab must not become a promise to support every device SKU. Prioritize devices
using observed adoption, architectural diversity, community maintainability,
accessibility/controller risk, and the value of proving a genuinely independent
client boundary. Accept community-contributed results only with reproducible
environment fingerprints and a clear distinction between Playstead-verified,
community-reported, degraded, experimental, and unsupported configurations.

ArmadaOS provides useful information-architecture prior art: its supported-device
surface groups devices by manufacturer, records each device's SoC, and adds a
model-specific page only where installation, usage, or troubleshooting guidance
actually differs. Playstead should investigate that layered approach so the
matrix stays navigable as device counts grow, while adding Playstead-specific
evidence such as client/OS build, adapter fingerprint, controller path, tested
journeys, last verification date, and evidence authority. Reuse the pattern only
after current license/trademark/content review; do not copy its catalogue or
infer that an ArmadaOS-supported device is Playstead-compatible.

## When to Surface

**Trigger:** when planning a second client or adapter, publishing compatibility
claims, or supporting handheld, living-room, or homebrew hardware.

Surface before extracting shared SDKs or advertising broad platform support. A
small matrix should precede a hardware lab; the lab should grow only when its
ongoing device acquisition, secure provisioning, update control, flake triage,
power/network isolation, and maintenance costs are explicitly owned.

## Scope Estimate

**Large.** Start as a versioned compatibility-record schema and release-gate
policy. A real CI hardware farm is later infrastructure work requiring secure
device enrollment, reproducible images, remote reset/recovery, artifact capture,
physical power/USB control, test-content licensing, and a budget for device churn.

## Breadcrumbs

- `https://www.goretroid.com/collections/frontpage/products/retroid-pocket-6-handheld`
  — owner-provided example of the expanding handheld target landscape; inclusion
  here is a research breadcrumb, not a compatibility claim or purchase decision
- `https://armadaos.dev/devices/supported-devices/` — owner-provided prior-art
  breadcrumb for a manufacturer → model/SoC → conditional model-documentation
  hierarchy; research its maintenance and evidence model before adopting it
- `.planning/PROJECT.md` — long-term Steam Deck, PSP/Vita-class, arcade,
  living-room, desktop, and web client vision; broad v1 support is out of scope
- `.planning/ROADMAP.md` — current contract requires explicit client/emulator/
  core/system/version matrices and a second adapter before portability claims
- `.planning/discovery/TECHNICAL-RISKS.md` — adapter fingerprints, controller
  profile variability, and the prohibition on aspirational universal support
- `.planning/research/FEATURES.md` — second client/adapter is the deliberate
  v1.x pressure test for the protocol boundary
- `.planning/seeds/SEED-007-emudeck-study-and-relationship-options.md` — related
  launcher/appliance ecosystem study

## Notes

Captured during Phase 03.5 from the owner's idea of eventually using real devices
as an automated compatibility farm. Keep it out of the current Mac verification
phase. The first follow-up should define evidence levels and the matrix schema,
not buy a room full of hardware.
