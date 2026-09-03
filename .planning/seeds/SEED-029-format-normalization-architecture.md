---
id: SEED-029
status: dormant
planted: 2026-09-03
planted_during: v1.0 / Phase 04 planning — owner imported a .chd and a .zip, neither identifiable
trigger_when: when supporting formats beyond the six raw validators, when the archive-security gate is scheduled, or whenever a user asks why their CHD/ZIP is "not identified"
scope: medium — identification-only support is tractable; persisted conversion is larger and mostly unnecessary
related: SEED-022 (collection reconciliation), SEED-028 (reference-pack onboarding), SEED-030 (ROM manager prior art)
---

# SEED-029: Support the formats people actually have — without ever converting their bytes

## The problem, concretely

The owner's first two real imports both landed in deliberately-unsupported containers:

| File | Reason | Root cause |
|---|---|---|
| `WipEout 3 … .chd` | `no_reference_installed` | `.chd` is not among the six validators (`gb`, `gba`, `md`, `nes`, `psx_cue`, `snes`), and Redump hashes raw per-track BIN data — never the CHD container. **No datfile can ever match it as-is.** |
| `EarthBound (USA).zip` | `archive_not_opened` | Archives are detected and deliberately never opened, pending the Phase 2 archive-security gate (adversarial corpus + isolated CPU/memory/path/recursion/expanded-size limits). |

Both behaved correctly. Both are also, from the user's chair, a library that cannot
identify the files they actually own. CHD is the dominant distribution format for
disc systems and ZIP is the dominant one for cartridges — "we only understand raw
dumps" is not a viable long-term posture.

## The decided answer: identify without converting

Research into conversion formats (Sept 2026) produced an unusually clean
architectural answer, and it is the one this codebase already implements for
other reasons: **store the original bytes immutably; treat every derived form as
disposable cache; never convert on ingest.**

Applied to identification, the key insight is that **matching a datfile hash does
not require persisting a conversion**:

- Decompress to a temp stream, compute the canonical hash, record the hash,
  discard the derived bytes.
- The *hash* becomes the artifact of record. It is always re-derivable from the
  untouched original.
- No converted file is ever stored, so no converted file can ever become the only
  copy.

That last point is the whole game. The cautionary tale is **NKit**: it advertises
near-lossless GameCube/Wii compression but strips "junk" padding and depends on
separately-distributed recovery data to rebuild the original. Users who kept only
NKit files without matching recovery data **cannot get their exact original ISO
back — permanently.** Any design where a converted form can become the sole copy
eventually produces that outcome.

## What is and is not bit-exact (matters for what we may claim)

- **Bit-exact reversible**: CHD ↔ BIN/CUE (track data), PSP CSO/CISO ↔ ISO, ZIP ↔
  contained files (contents, *not* container bytes — plain ZIP is non-deterministic;
  that is why TorrentZip exists as a canonicalization discipline).
- **Functionally lossless but requires trusting reconstruction logic**: RVZ/WIA ↔ ISO
  (Dolphin stores Wii partitions decrypted with hash-exceptions and stores disc
  padding as a PRNG seed — reconstruction is computed, not stored).
- **Genuinely lossy**: NKit without complete recovery data. Treat like a lossy codec;
  never accept as a substitute for original bytes, and say so to the user.

Also documented: CHD → BIN/CUE reproduces track data faithfully but the regenerated
`.cue` **text** can differ from Redump's, because CHD's schema cannot represent every
cue metadata field. Exact-file comparison of the cue will produce false mismatches;
compare track hashes, not cue text.

## Sequencing

1. **Raw formats first** — already work; this is where headerless fingerprinting fires.
2. **ZIP identification** — gated on the archive-security gate, which is protecting
   against zip bombs and path traversal. That gate is doing real work and should not
   be short-circuited to make identification convenient. Identification-in-a-sandbox
   is the deliverable, not "open archives."
3. **CHD identification** — no security gate needed (it is not an arbitrary-content
   container in the same way), but needs `chdman`-equivalent extraction to a temp
   stream plus per-track hashing. Pin the tool version: chdman has had version- and
   platform-specific corruption bugs (network shares, PSP-specific, Dreamcast).
4. **Persisted conversion** — probably never, or only as an explicitly-labeled derived
   artifact recording tool+version+parameters, never as the only copy.

## Cost notes

Peak disk during identification is ~1x original + 1x derived, transiently. Hunk/block
formats (CHD, CSO, RVZ) parallelize naturally because units compress independently;
`chdman` exposes `--numprocessors`. Solid archives (7z/RAR) do not — the whole solid
block must be processed to read one member, which is also why they are a poor fit for
per-member verification.

## Notes

Owner's framing: *"that's the file I was downloading, people will have CHD files
right — does that mean we need some kind of mechanism for converting files... does
that take CPU, disk space, memory?"* Yes on all three, which is exactly why the
answer is to convert transiently for identification and never persist.

The pleasant surprise from the research: the recommended architecture for a product
guaranteeing exact original bytes is the architecture Playstead already has. This
seed is about extending *understanding*, not relaxing *custody*.
