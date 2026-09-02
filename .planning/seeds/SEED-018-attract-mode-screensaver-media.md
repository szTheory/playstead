---
id: SEED-018
status: dormant
planted: 2026-09-02
planted_during: v1.0 / Phase 03.5 (Mac Verification Automation)
trigger_when: when planning client home screens, idle states, ambient playback, or game media capture
scope: medium — client UX, metadata rights, media storage, playback, and accessibility
related: SEED-008 (metadata, screenshots, manuals, and smart caching), SEED-006 (game hub and progress media), SEED-007 (EmuDeck study)
---

# SEED-018: Explore an optional Playstead attract mode and media screensaver

## Why This Matters

Some Playstead clients could make an idle library feel inviting through an
optional screensaver or “attract mode,” similar to an arcade front end. It might
play short trailers or gameplay clips supplied by an explicitly permitted
metadata source, or clips the user deliberately captured while playing. This
could make the home screen useful even before a player chooses a game, while
remaining subordinate to fast navigation and offline ownership.

## Questions to Explore

- Which clients and contexts benefit from ambient video, and what is the default
  for battery, bandwidth, privacy, accessibility, and quiet environments?
- How are rights, attribution, download consent, retention, and deletion handled
  for metadata-provider clips versus user-captured media?
- Can clips be cached as optional, bounded media without entering the launch
  critical path or making a game appear playable when it is not?
- Should the experience be called **Attract Mode**, **Ambient Library**, or
  something clearer for non-arcade users? Align it with domain-language audits.
- Provide reduced-motion, captions, mute, controller/keyboard escape, and no-
  autoplay settings; never let ambient playback obscure ownership or controls.

## When to Surface

Surface during a future client home/idle UX or media-enrichment phase. Start with
one small, rights-clear fixture or user-owned clip and an explicit opt-in before
adding provider integrations or automatic capture.

## Notes

Captured from the owner's idea for an EmuDeck/ES-DE-like screensaver or arcade
attract mode using permitted metadata videos and/or clips captured from Playstead
gameplay. This is a future UX seed, not a change to the current verification work.
