---
id: SEED-031
status: dormant
planted: 2026-09-03
planted_during: v1.0 / Phase 04 (Persistent Save Continuity) execution
trigger_when: when planning any milestone that touches the adapter/emulator process boundary, per-game media, sharing, or social features; revisit before committing to an adapter IPC contract, since retrofitting frame access later is far more expensive than reserving for it
scope: large — spans the adapter boundary, a media pipeline, storage/quota policy, rights and privacy posture, and whatever social surface the sharing side implies
related: SEED-006 (save-progress screenshots and per-game hub), SEED-018 (attract mode and media screensaver), SEED-008 (metadata, screenshots, manuals), SEED-005 (playtime and last-played stats), SEED-004 (household player profiles)
---

# SEED-031: Optional background recording buffer, and the curation/sharing it unlocks

Owner idea, captured during Phase 04 execution. Two layers, and they should be
judged separately even though the second is the reason to want the first.

## The capability

An **optional** background frame buffer that continuously records recent gameplay
without the player having to decide in advance that a moment mattered. The
familiar shape is a rolling ring buffer — the last N seconds always in memory, and
a "save that" action that writes it out. It supports three different audiences at
once:

- **Streaming / content creation** — a clean capture path that does not require
  the player to run OBS alongside the app.
- **Clip capture** — the thing that just happened was great and nobody was
  recording. This is the case a rolling buffer uniquely solves, and the reason it
  beats a plain "start recording" button.
- **Screenshots and moments** — the same pipeline at one frame, feeding the
  progress media that SEED-006 and SEED-018 both already want.

## The part that makes it interesting

Recording is the mechanism. **Curation and sharing is the point.** The owner's
framing: this is what makes playing and curating *fun* — capturing moments,
building a collection of them, and sharing in a way that has some social texture
rather than being a dump of files. A library that remembers what happened in a
game is a different object from a library that remembers only that you own it.

That reframes recording from a utility feature into part of Playstead's actual
character, and it composes with several seeds already planted: per-game hubs
(SEED-006), ambient/attract media (SEED-018), playtime and last-played stats
(SEED-005), household profiles (SEED-004 — whose moment is it?), and eventually
federation (SEED-014 — where does a shared moment go, and under whose name?).

## The constraint that decides feasibility

**Playstead does not own the frame buffer today, and that is the whole problem.**

`AdapterHost` spawns the emulator as a separate `Process()` with a pinned,
digest-verified executable (`playstead-mac/Playstead/Adapter/AdapterHost.swift`).
There is no rendering or frame-capture code anywhere under
`playstead-mac/Playstead/` — the app orchestrates an emulator, it does not draw
the game. So every approach costs something different:

- **Adapter-side capture** — the adapter exposes frames over the IPC boundary.
  Cleanest data, but it means an adapter capability contract, and every adapter
  has to implement it or honestly declare it cannot. Consistent with how the
  project already treats adapter capabilities as declared rather than assumed.
- **Window/display capture** (`ScreenCaptureKit`) — works without adapter
  cooperation and without touching the pinned-executable trust boundary, but it
  is OS-permission-gated, captures whatever is on screen including overlays, and
  ties quality to display state.
- **Do nothing until an adapter needs it anyway** — plausible, but the trigger
  above exists because the adapter IPC contract is the cheap moment to reserve
  for this. Retrofitting frame access into a frozen contract is the expensive
  path.

## Open questions worth answering before this becomes a phase

- **Rights and distribution.** A clip is a derivative of copyrighted game content.
  Local capture is one posture; a sharing surface hosted by a Playstead server is
  a materially different one, and SEED-014's lawful-federation constraints apply.
  Answer this *before* designing the social layer, not after.
- **Privacy and consent.** Always-on recording in a household context (SEED-004)
  needs to be opt-in, visibly indicated while active, and scoped per profile.
- **Cost.** A rolling buffer is continuous CPU/GPU/memory/disk pressure during
  play. Phase 04 has already established that this project takes disk budget
  seriously — cache directories are excluded from Time Machine precisely because
  they are reconstructable, and saves are not. Clips are a third category: not
  reconstructable, but also not irreplaceable. They need their own quota and
  their own backup posture, decided deliberately rather than inherited.
- **Save states vs. clips.** SEED-019 already draws the line between system saves
  and save states. A clip is a third artifact with a third portability contract —
  it is the only one of the three that is *meant* to leave the machine.

## Breadcrumbs

- `playstead-mac/Playstead/Adapter/AdapterHost.swift` — the process boundary any
  adapter-side capture must cross; also where the pinned-digest trust model lives
- `playstead-mac/Playstead/Curation/PlaySessionRecorder.swift` — already records
  per-session continuity data; the natural place to hang "and this is when the
  interesting thing happened"
- `playstead-mac/Playstead/Cache/QuotaManager.swift` — existing quota machinery a
  clip budget would extend rather than duplicate
- `.planning/seeds/SEED-006-save-progress-screenshots-and-game-hub.md` — wants the
  single-frame version of exactly this pipeline
- `.planning/seeds/SEED-018-attract-mode-screensaver-media.md` — wants captured
  media as ambient playback; same source, different surface

## Notes

Captured verbatim-in-spirit from an owner aside during Phase 04 Wave 2. Explicitly
**not** for v1.0 and not to be pulled into Phase 04 — roadmap consideration for a
future milestone. The recording capability and the social/sharing surface should
be scoped as separate phases if this is ever picked up; the first is a bounded
technical problem, the second is a product and legal one.
