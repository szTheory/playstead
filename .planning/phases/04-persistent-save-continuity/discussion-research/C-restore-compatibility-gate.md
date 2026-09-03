# Area C — Restore Compatibility Gate (SAVE-03)

**Question:** what makes a save revision "compatible" with a game on this Mac,
what is checked before restoring it, and what happens when a check fails.

**Requirement, verbatim:** SAVE-03 — "A user can restore a compatible
checksummed persistent-save revision and continue the game on a clean paired
Mac installation."

---

## 0. What I verified in the repo before deciding anything

Grepped, not assumed:

- **`Playstead.Blobs.Fingerprints.fingerprint_kind/1` maps GBA to `nil`.**
  Only `:nes` (`nes_header_skip16`, offset 16) and `:snes` with
  `%{copier_header: true}` (`snes_copier_skip512`, offset 512) produce a
  `BlobFingerprint` row. *"Every other format result — a GBA, GB, MD, or PSX
  match, a container, and `:unknown` — maps to no kind."* **For the only system
  Phase 4 ships, content identity and byte identity are the same thing.** There
  is no header to strip from a `.gba` ROM; the GBA cartridge header lives at
  offset 0 and is part of the addressed ROM. This kills an entire branch of this
  decision before it starts, and it is a fact about this codebase, not an
  inference.
- **`Playstead.Recognition.ReferenceMatch.recognize/2`** returns
  `:matched | :variant | :no_match` with `confidence: :exact` and an
  `evidence` map carrying `dat_pack_id, crc32, md5, sha1`. Only a reference
  match may promote a possible-variant reading (D-17). This is the *only*
  machinery in the codebase that can say "these two different byte streams are
  the same game", and I use exactly it — I invent no second heuristic.
- **`Playstead.Recognition.NoIntroName.parse/1`** already decomposes
  `Title (Region) (Languages) (Version) (Devstatus) (Additional) [Status]` into
  `region / languages / version / dev_status / additional / status`. Region and
  revision are already first-class parsed facts, not something I have to build.
- **`Playstead.Catalogue.AssetSet`** is user-scoped with `system_id`,
  `member_fingerprint` (natural key), `provenance :map`.
  **`AssetMember`** has a frozen role vocabulary `~w(descriptor track primary
  disc patch parent companion)` — note there is **no `save` role**, and
  `role` is validated by `validate_inclusion`. A save is *not* an asset member.
- **`Playstead.Attention.Reason`** is a **frozen nine-value vocabulary** whose
  moduledoc says so explicitly. I do not extend it (see D-C11).
- **`PlaysteadWeb.ErrorCodes`** registry has no save codes yet; adding is
  additive (P1 D-18/D-22).
- **`PreflightChecker`** implements the P3 D-23 cheap check
  (`size == && inode == && mtime ==` against `cas.verifyRecord`) with a full
  `rehash` fallback, and `ReadinessBlocker.reason` is
  `"missing" | "unreadable" | "corrupted" | "invalid_digest"`.
- **`ReadinessCheckKind`** is a six-case `String`-backed `CaseIterable` enum:
  `gameAssets, cacheVerification, emulator, bios, controllerAndInput,
  saveDirectory`. **A `saveDirectory` check and a `.repairSaveDirectory`
  remedy already exist.** `ReadinessOutcome` is `.ready | .warning(String) |
  .blocked(String)`; `RemedyAction` has five cases.
- **`AdapterSaveContract`** (Swift) decodes five keys, all **non-optional
  `let`s**: `artifact_glob, directory_key, flush_triggers,
  on_demand_flush_supported, worst_case_loss_seconds`. Any addition must be
  `Optional` or defaulted or it breaks decoding of the shipped
  `03-ADAPTER-PIN.json`.
- **`StreamingSHA256`** exposes `update/finalizeHex` and
  `resume(from:chunkSize:)` which re-reads from byte zero. There is
  deliberately **no serialized mid-stream checkpoint** (D-18) — the on-disk
  prefix is always truth.
- **`docs/SUPPORT-MATRIX.md`** exists and is written in exactly the honest
  register this area must extend: one proven combination, deferred things
  named as deferred.

---

## 1. Role lenses applied

**Domain modeller.** The gate is a pure function over two value objects and
returns a verdict. It belongs in a `SaveBinding` value type owned by the save
domain, with **zero** dependency on the CAS, the network, the emulator process,
or SwiftUI. The adapter pin is *data* it reads, not a collaborator.
One-way flow: `SaveBinding × LocalGameIdentity → RestoreVerdict`.

**Distributed-systems / offline-sync.** Every field the gate reads must be
denormalized into the `save` journal payload at capture time on the device that
captured it. If the gate ever needs a join the client cannot perform offline,
clean-Mac restore breaks in exactly the situation SAVE-03 names. This is the
single strongest constraint in the area and it is what forces D-C5.

**Elixir/Phoenix.** Server-side this is a `Playstead.Saves` context function,
additive `save` journal payload fields (P1 D-18), two new registered error codes
(P1 D-22), forward-only migration. The server **never decides** the verdict for
a client — it publishes binding facts; the client evaluates. That keeps the
zero-network rule structurally true rather than politely honoured.

**Swift/macOS.** Restore is: capture-current → write temp in the destination
directory → `fsync` → re-hash → `rename(2)` over the target. `rename` within a
volume is atomic; a crash leaves either the old file or the new one, never a
torn `.sav`. The launch dir is a `clonefile` materialization (P3 D-20) — the
emulator writes through it, never into the CAS — which is what makes an
override tier survivable at all.

**Filesystem/durability.** 32 KB is one to two APFS blocks. Arguing about
whether to re-hash it is a waste of thought; see D-C8.

**Security.** The revision blob is untrusted bytes. It is never parsed, never
interpreted, never used to build a path. Its digest names its CAS object; its
destination filename comes from the *local* `romBaseName` via the pin's
`artifact_glob`, never from anything inside or attached to the revision. A
size cap of `max_artifact_bytes` from the pin bounds the write. No ROM name, no
digest, no title appears in a log line or CI evidence artifact.

**SRE.** The gate emits one counter per verdict tier and nothing else. An
incompatible restore attempt is a *user* event, not an alert.

**Product / first-adopter.** The person has one job: get their Pokémon file
onto the new laptop. Every ceremony I add either prevents a real loss or is
tax. I budget exactly one ceremony (the same-title acknowledgement) and justify
it with a specific, documented destruction path.

**UI/UX + microcopy.** This area has a surface: the verdict text and the
override sheet. Strings are written out in §8, not gestured at.

**Accessibility.** Verdicts are text-first with an SF Symbol and a
`StatusToken` hue — never colour-only (P3 D-13 / WCAG 1.4.1). The override
sheet's destructive-ish action is keyboard-reachable and its VoiceOver label is
a full sentence.

**Performance.** SHA-256 of 32 KB on Apple silicon with the SHA extensions is
tens of microseconds. Any design that tries to avoid it is worse code for no
gain.

**Test/verification.** §10.

**QA adversarial.** §9.

*Not applied:* nothing material — every lens has a claim here.

---

## 2. The technology argument: what actually binds a battery save to a game

This is the crux, and most emulator-ecosystem intuition about it is imported
from save **states** and is wrong here.

A GBA battery save is **written by the game's own code** into cartridge backup
media (SRAM, Flash, or EEPROM). The emulator is a bus. It contributes no
struct layout, no serialization format, no version stamp. The consequences:

- **A `.sav` is portable across emulators and across a real cartridge.** mGBA,
  VBA-M, and a hardware cart dumper all produce the same bytes for the same
  medium. This is precisely SEED-019's distinction and it is why SEED-002
  (cartridge ↔ emulated) is even conceivable.
- **Therefore `emulator_id`, `emulator_version`, `core_version`, and the
  adapter pin digest are NOT compatibility fields.** Gating on them would be
  cargo-culted save-state thinking. They are *provenance* (SEED-001 wants them
  recorded) and I record all four — but they never produce a verdict.

What genuinely binds:

| Candidate field | Verdict | Evidence |
|---|---|---|
| `system_id` | **Bind, hard** | A GB `.sav` in a GBA save dir is not a near-miss, it is a category error. Free to check. |
| `save_kind` (`battery` / `state`) | **Bind, hard** | Phase 4 only produces `battery`. Freezing the vocabulary now is what stops SEED-019's surface from lying later. |
| `medium_id` + `bytes` | **Bind, hard — the field that earns its keep** | GBA has six backup media: EEPROM 512 B, EEPROM 8 KB, SRAM 32 KB, Flash 64 KB, Flash 128 KB, none. They occupy the *same memory-map space* through different hardware interfaces, so an emulator must pick one before boot. mGBA infers it from SDK signature strings in the ROM (`SRAM_V`, `FLASH_V`, `FLASH512_V`, `FLASH1M_V`, `EEPROM_V`) plus an override database. **The medium is a property of the ROM bytes.** Different regional or revision dumps of the same title can therefore carry different media — the 32 KB-SRAM-vs-64 KB-Flash case in the prompt is real, and it is the exact case a naive title-level match would wave through into data loss. |
| ROM `content_sha256` | **Bind, as the exact tier** | For GBA this *is* content identity — `Fingerprints` maps GBA to no headerless kind because there is no copier/iNES header to skip (verified above). Trimmed-vs-untrimmed and patched dumps produce different sha256 and are correctly *not* the exact tier. |
| DAT/reference title identity | **Bind, as the widened tier only** | `ReferenceMatch` with `status: :matched, confidence: :exact` on **both** sides. A `:variant` or `:no_match` reading never widens. |
| `asset_set_id` | **Routing key, not a gate** | It is the user-scoped hanger the save timeline lives on. Two asset sets can hold the same game; one asset set survives a re-import that changes the underlying blob. Using it as the compatibility check would be provider-shaped and would silently accept a ROM swap. |
| `emulator_id` / `emulator_version` / `core_version` / `adapter_pin_sha256` | **Provenance only, never gate** | See the argument above. Recorded for SEED-001 and to make a *future* save-state binding declarable. |
| ROM byte size / headered-ness | **Out** | Meaningless for GBA; redundant with sha256 everywhere else. |
| `origin` (`emulated` / `cartridge`) | **Recorded, not gated in v1** | Only `emulated` exists in Phase 4. It is SEED-002's door. |

**The tuple, then:**

```
SaveBinding = {
  system_id,            # "gba"                       — gate
  save_kind,            # "battery"                   — gate
  medium_id,            # "sram_32k"                  — gate
  artifact_bytes,       # 32768                       — gate (must equal medium's bytes)
  rom_sha256,           # exact-tier identity          — gate (tiering)
  title_identity,       # {dat_pack_id, entry_name, crc32} or null — widening only
  origin,               # "emulated"                  — recorded (SEED-002 door)
  provenance: {emulator, emulator_version, core_version|null,
               adapter_pin_sha256, captured_at, device_id}  — never gates
}
```

`medium_id` is derived at capture time from the observed artifact byte size via
the pin's `media` table (D-C10). A size not in the table yields
`medium_id: "unknown"` — the revision is still **captured** (never lose bytes;
that is area A's rule and I do not weaken it) but is `binding_status: unbound`
and **not restorable** until identified.

---

## 3. Byte-identity vs content-identity — the exact rule

**Three verdict tiers. The gate is not a boolean.**

| Tier | Condition | Outcome |
|---|---|---|
| `exact` | `system_id`, `save_kind`, `medium_id`, `artifact_bytes` all equal **and** `rom_sha256` equals the sha256 of the local primary member | Restore proceeds. No ceremony beyond the mandatory pre-restore capture. |
| `same_title` | Gate fields all equal, `rom_sha256` differs, **and** both the revision's `title_identity` and the local blob's current reference match are `:matched` with `confidence: :exact` against the same DAT entry title group | **Blocked by default, releasable by an explicit typed-context acknowledgement.** |
| `incompatible` | Anything else: different system, different `save_kind`, different `medium_id`/`artifact_bytes`, `binding_status: unbound`, or no `:matched` title link on either side | **Hard block. No override. No affordance offered.** |

Defence, against the constitution's priority order:

1. **Data safety #1** puts `medium_id` mismatch in the hard-block bucket with no
   escape hatch, because the failure is *destructive*, not merely useless
   (§4).
2. **The honesty constraint** — never claim aspirational compatibility — is why
   the widened tier requires a *positive certain* DAT match on both sides
   rather than a filename or title-string similarity. If we have no reference
   pack installed, we do not guess; we say so and offer only the exact tier.
   That is the honest degradation, and it is exactly what happens on a fresh
   clean Mac.
3. **Not permissive on "close enough".** A trimmed dump, a patched ROM, a ROM
   hack, and a translation patch all land in `same_title` at best and usually
   in `incompatible` (a hacked ROM will not carry a `:matched` DAT reading).
   That is correct: a ROM hack's save layout can differ arbitrarily from its
   base game.

**Why `same_title` is override-able rather than hard-blocked:** the legitimate
case is overwhelmingly common. The user's clean Mac downloaded the copy the
server holds; their original save was captured against a differently-trimmed or
differently-revisioned dump of the same title with the same backup medium.
Same-medium USA/Europe and rev-0/rev-1 GBA saves are usually interchangeable.
Hard-blocking that would fail SAVE-03's own headline scenario for a large
fraction of real users while pointing at nothing they can fix.

**Why it is not a quiet warning either:** see §4.

---

## 4. Hard block vs warn-and-proceed, per failure mode

The decisive fact: a GBA game that reads backup media it cannot parse typically
shows *"The save file is corrupted. The previous save file will be loaded"* or
*"The 1MB save file has been erased"*-class messaging and **offers, or simply
performs, an erase**. Permissiveness here does not produce a confusing
experience; it produces a game that deletes the user's file for us. That is a
data-loss path *created by our own leniency*, and it is why a warning banner is
not a defensible design.

But the erase only ever reaches the **working copy in the clonefile-materialized
launch dir** (P3 D-20). It cannot reach the CAS object or any captured
revision. So the true risk of a permitted `same_title` restore is: *the attempt
is wasted and the working file is destroyed* — **provided** the pre-restore
state was captured as a revision first. Which is D-C4, and which is what makes
the override tier ethical rather than reckless.

| Failure mode | Decision | Why |
|---|---|---|
| Different `system_id` | **Hard block**, no override | Category error, zero legitimate case. |
| Different `save_kind` (state vs battery) | **Hard block**, no override | Not producible in v1; freezing the rule now prevents SEED-019's surface from lying. |
| Different `medium_id` or `artifact_bytes` | **Hard block, no override** | The destructive case. There is no legitimate "I know what I'm doing" here — a 32 KB SRAM image is not a 64 KB Flash image and no user acknowledgement makes it one. |
| `binding_status: unbound` (unknown size) | **Hard block**, no override, revision still visible and exportable | Never lose it; never gamble with it. PORT-01 still gets it out (area H). |
| `rom_sha256` differs, both sides `:matched` to same title | **Block with explicit acknowledgement**, one sheet, plain language, no dark pattern | Common legitimate case; bounded blast radius given D-C4. |
| `rom_sha256` differs, no certain title link either side | **Hard block**, no override; remedy is "install a reference pack" or "restore onto the exact copy this save came from" | Honesty constraint: we do not guess. |
| Revision blob not present locally | **Not a compatibility failure** — a download | Distinct remedy, distinct copy. |
| Revision blob digest mismatch | **Hard block**, quarantine + redownload | §5. |
| Pre-restore capture fails | **Abort the restore entirely** | Data safety #1 outranks the user's request. |

---

## 5. The "checksummed" half — what is verified, and when

SAVE-03 says *compatible **checksummed*** revision. Specification:

1. **At capture:** the client hashes the `.sav` while copying it into the CAS
   (existing `StreamingSHA256` path). The digest is the revision's identity and
   goes in the `save` journal payload.
2. **At upload/download:** the server verifies on ingest (existing blob-store
   read-back verify, P2 D-11); the client verifies on download-completion
   (existing CAS path). No new machinery.
3. **At restore time: always full re-hash. Never the cheap check.**
   P3 D-23's `size + inode + mtime` shortcut exists to avoid re-reading
   hundred-megabyte ROMs in a launch-latency-sensitive path. A save revision is
   at most `max_artifact_bytes` = 131072 bytes. Full SHA-256 of 128 KB is well
   under a millisecond and involves no seek beyond one or two extents. Reusing
   the cheap check here buys nothing measurable and costs a whole
   staleness-reasoning surface (inode reuse, mtime granularity, clock
   adjustments). **Simpler code, strictly stronger guarantee, no cost.** The
   cheap check stays where it belongs, on ROMs.
4. **After writing, before launch:** re-hash the file just written to the launch
   dir and compare to the revision digest, *before* the `rename(2)`. Catches a
   torn write or a failing disk at the only moment we can still do something
   about it. Then `fsync` the file, `rename`, `fsync` the directory.

**On digest mismatch:** the local CAS object is **quarantined** (moved out of
the verified index, retained on disk under a quarantine prefix — nothing is
silently deleted, P3 D-21), the revision is marked needs-redownload, and the
user gets a no-blame message with a one-click redownload — mirroring P3 D-23's
corruption handling and `ReadinessBlocker(reason: "corrupted")`'s existing
"Redownload the affected file" remedy. If offline, the block stands with an
explicit "this needs the server" and **no override** — a known-bad 32 KB blob
written into a save slot is the worst outcome available in this phase.

New registered problem codes (additive, P1 D-22):
`save_revision_digest_mismatch` (422), `save_binding_incompatible` (422).

---

## 6. Clean-Mac restore as a complete flow

The tenth step of PROJECT.md's First End-to-End Proof. Where the gate appears:

| # | Step | Gate appearance | What the user sees | How it fails |
|---|---|---|---|---|
| 1 | Fresh install | none | — | — |
| 2 | Pair | none | — | — |
| 3 | First sync | Binding fields arrive denormalized on `save` journal rows. **No gate evaluation yet.** | Library populates; cards show save presence per area E | 410 resync (P1 D-21) — existing path |
| 4 | Browse | none (a card's status slot is area E's, and P3 D-13 gives it exactly one slot) | — | — |
| 5 | Download the game | none | Existing download UI | Existing |
| 6 | **Open the save timeline** | **Gate evaluated for every revision, locally, on ROM-blob-present.** Each row carries its verdict. | Restorable rows are plain; `same_title` rows are marked and explained; `incompatible` rows are dimmed with a reason sentence | Reference pack absent → widened tier unavailable → say so plainly, do not imply the save is broken |
| 7 | Download the revision blob (if absent) | none (this is a download) | Progress | Offline → "not on this Mac yet" |
| 8 | **Restore** | Gate re-evaluated at the moment of action (never trust a stale row); digest re-verified; pre-restore capture; atomic write | Confirmation naming what is being replaced and that the current state was kept | §4/§5 |
| 9 | Preflight | **`saveContinuity` check — informational only, never blocking** | "A save from *MacBook Air* is available for this game" + Restore remedy, or silence | — |
| 10 | Launch → continue | none | The game | The human half — §10 |

**Where restore lives:** an **explicit user action on the save timeline**
(step 8), plus a **non-blocking offer** at preflight (step 9). **Never
automatic.** Auto-restoring on first launch would silently overwrite whatever a
user had started locally, which is exactly "silently discard save conflicts" —
a named constitutional prohibition.

> **⚠ COLLISION FLAG — area F.** Whether a seventh `ReadinessCheckKind`
> (`saveContinuity`) is added to the frozen six-case enum, and where it sits in
> the declared order (which is also the severity tie-break order), is **F's
> decision, not mine.** My assumption, stated so F can overrule it: a
> `saveContinuity` case is added **last** in the enum order and its outcome is
> restricted to `.ready` or `.warning(String)` — **never `.blocked`**. A save
> problem must never prevent launching a game you can legitimately start from
> scratch (constitution #2, reliable local play). If F decides preflight stays
> six checks and the offer lives elsewhere, nothing in this area breaks; only
> step 9 moves.

---

## 7. The zero-network constraint (P3 D-23 / CACH-04)

Everything the gate reads is already local:

| Fact | Local source |
|---|---|
| `system_id`, `save_kind`, `medium_id`, `artifact_bytes`, `rom_sha256`, `title_identity` | `save` journal rows in `LocalStore` (SQLite), synced ahead of time |
| Local ROM sha256 | `LocalStore` catalogue |
| Local title identity | **Denormalized onto the local asset member at sync time** — never queried live |
| Revision blob presence + digest | `CASManager` |

**The one design move that makes this work: `title_identity` is denormalized
into the `save` journal payload at capture time by the server, and onto the
local asset member by the catalogue sync.** The client must never need to
consult a DAT pack, or the server, to evaluate a verdict. If it did, the
widened tier would evaporate on a clean offline Mac — the exact scenario
SAVE-03 names.

Consequences, stated honestly: a title-identity fact that changes on the server
after a device synced is stale on that device until it syncs. For a DAT-derived
identity that is near-immutable, this is acceptable; the failure mode is a
*narrower* gate (a widened restore not offered), never a *wider* one. The gate
degrades toward strictness under staleness. That is the correct direction.

A fully offline clean Mac with the game downloaded and the revision downloaded
restores with **zero network calls**. Proven by a named test (§10).

---

## 8. The honest matrix and the actual strings

### Support matrix addition (`playstead-mac/docs/SUPPORT-MATRIX.md`)

```markdown
## Save restore support

| Fact | Value |
|---|---|
| Save kinds supported | Persistent battery saves only. **Save states are not supported** and are not captured, synced, restored, or exported. |
| Backup media recognised | SRAM 32 KB (`sram_32k`) — the only medium observed and proven by the plan 03-01 spike. EEPROM 512 B / 8 KB and Flash 64 KB / 128 KB are **declared in the adapter pin and captured, but no restore of them has been proven on real hardware in this environment.** |
| Restore requires | Same system, same save kind, same backup medium and exact byte size, and either the exact same game file the save was made with, or a different copy of the same game confirmed by an installed reference pack. |
| Restore across different copies of a game | Permitted **only** with an installed reference pack that identifies both copies as the same title with certainty, and only behind an explicit confirmation. Never automatic. |
| Restore across emulators | A GBA battery save is written by the game, not the emulator, so these files are portable in principle. Playstead does not claim, and has not tested, restore into any emulator other than the pinned one. |
| Restore from a physical cartridge | Not supported. No cartridge hardware path exists. |
| Integrity | Every save revision is verified by full SHA-256 re-hash at restore time, and the written file is re-hashed before it is put in place. |
| Overwrite behaviour | Restore never overwrites in place. The save currently on this Mac is captured as its own revision first; if that capture fails, the restore does not run. |
```

### Microcopy — the actual strings

**Explain, never blame. No exclamation marks. No "Error:". No "invalid".**

`same_title` row badge (timeline):
> **Different copy of this game**

`same_title` sheet:
> **This save was made with a different copy of *{title}***
>
> The copy on this Mac isn't byte-for-byte the same file. Both are recognised
> as *{title}*, and they use the same 32 KB save chip, so this save will very
> likely load — but some regional and revised copies of a game store their
> saves differently, and if this one does, *{title}* may treat the save as
> damaged and offer to erase it.
>
> Your current save on this Mac is kept as its own revision before anything is
> replaced, so nothing here is permanent.
>
> `[ Cancel ]` `[ Restore anyway ]`

Medium mismatch (hard block):
> **This save can't be restored here**
>
> It's a 32 KB SRAM save, and the copy of *{title}* on this Mac uses a 64 KB
> Flash save chip. These are different kinds of storage inside the cartridge —
> the game can't read one as the other, and trying would likely make it erase
> the file.
>
> This save is safe, and you can export it at any time. To use it, restore it
> onto the copy of *{title}* it was made with.

No certain title link (hard block):
> **This save can't be restored here**
>
> It was made with a different copy of a game, and Playstead can't confirm that
> copy and the one on this Mac are the same title. Installing a reference pack
> would let it check.
>
> `[ Install a reference pack ]`

Unbound revision (hard block):
> **Playstead doesn't recognise this save's format**
>
> It's {n} bytes, which doesn't match any save chip the pinned emulator
> describes. It's kept and it can be exported, but Playstead won't put a file
> it can't identify into a game's save slot.

Digest mismatch (quarantine):
> **This save revision didn't arrive intact**
>
> The copy on this Mac doesn't match its checksum, so Playstead set it aside
> rather than use it. The revision on the server is fine — download it again.
>
> `[ Download again ]`

Digest mismatch, offline:
> **This save revision didn't arrive intact**
>
> Playstead set the local copy aside. Getting a good copy needs the server, so
> this will resume when this Mac is back online.

Preflight offer (non-blocking):
> **A save for *{title}* is available from *{deviceName}***, from {relativeTime}.
> This Mac doesn't have one yet.
> `[ Restore it ]`

Post-restore confirmation:
> **Restored.** The save that was on this Mac is kept as a revision from
> {timestamp} — nothing was thrown away.

VoiceOver labels (full sentences, never a bare badge):
- `"Different copy of this game. Restoring is possible but needs confirmation."`
- `"Cannot be restored on this Mac. Different save chip type."`

Accessibility: every verdict is a text sentence plus an SF Symbol plus a hue.
Never hue alone (P3 D-13, WCAG 1.4.1). Reduced-motion: the sheet's presentation
uses the existing `MotionPreference` fade equivalent.

**Consumer-shaped, not provider-shaped.** No string above shows a SHA-256, a
cursor, a journal kind, a DAT pack id, or the word "binding". The one place a
raw number leaks is the unbound revision's byte count — justified because it is
the only fact that lets a user or a maintainer diagnose it, and it is a
property of *their* file, not our internals.

---

## 9. Prior art

| System | What to copy | Documented footgun to avoid |
|---|---|---|
| **mGBA** — save-type detection from SDK strings + override DB; `Tools → Game Overrides` ([PR #2582](https://github.com/mgba-emu/mgba/pull/2582), [EmuDesk](https://emudesk.com/issues/mgba-game-not-saving-save-type-fix)) | Medium is a property of the **ROM**, so detection is deterministic per byte stream. Human-visible override exists for when detection is wrong. | Detection "occasionally guesses wrong — especially on licensed re-releases, ROM hacks, or less-common titles… bytes go to the wrong addresses and the save corrupts." We must not build a second, worse detector. We read the **observed artifact size** as ground truth instead of predicting it. |
| **GBA backup media** ([Screwtape](https://zork.net/~st/jottings/GBA_saves.html), [GBA ROM Patcher](https://gbarompatcher.com/blog/gba-save-types-explained/), [Dillon Beliveau](https://dillonbeliveau.com/2020/06/05/GBA-FLASH.html)) | Six media at the same memory-map addresses through different interfaces; the emulator must choose before boot. Two EEPROM sizes share one signature string. Flash manufacturer codes vary and games accept only specific ones. | This is exactly why `medium_id` is a **hard gate with no override**. Also why we never try to convert between media. |
| **RetroArch `.srm`** ([#15788](https://github.com/libretro/RetroArch/issues/15788), [#14530](https://github.com/libretro/RetroArch/issues/14530)) | Nothing to copy in the matching model. | Save matching is **by filename string**: "even a single character difference matters." Toggling *Sort saves by content directory* orphans existing saves — users lose track of files that still exist. **Filename is not identity.** We bind to digests and never let a filename decide anything. |
| **Ludusavi / ludusavi-manifest** ([manifest](https://github.com/mtkennerly/ludusavi-manifest), [custom games](https://github.com/mtkennerly/ludusavi/blob/master/docs/help/custom-games.md)) | A **declarative, versioned, external manifest** of where saves live per game, with `<storeGameId>` placeholders — data, not code. Directly the model for our adapter-declared `save_contract` (D-C10). | The manifest is community-curated and can be wrong or absent; Ludusavi's answer is user-authored custom-game overrides. Our analogue must eventually be a human-visible override — deliberately **not built** in Phase 4 (§11). |
| **Nintendo Switch Online cloud saves** ([Nintendo Life](https://www.nintendolife.com/guides/which-nintendo-switch-games-do-not-support-cloud-saves), [TechRadar](https://www.techradar.com/news/some-nintendo-switch-games-wont-work-with-the-upcoming-cloud-save-feature)) | **Publishing an explicit exclusion list rather than claiming universal support** — the exact posture SUPPORT-MATRIX.md already takes. Nintendo names the games and the reasons. | The exclusions are *policy* (anti-time-travel, competitive fairness), not technical. We must not smuggle policy into a technical gate; our exclusions are all mechanical and each has a stated mechanism. |
| **Steam Cloud** | Per-app file matching by declared path patterns, and a conflict dialog that shows both sides with timestamps and device names. Device name and time are the two facts a human actually reasons with — used in our preflight string. | The canonical bad half: the dialog appears at launch, under time pressure, with one side about to be lost, and "Upload to Steam"/"Download from Steam" does not say what is *inside* either. Our gate deliberately runs on a **timeline the user opened**, not in a launch-time modal. |
| **Time Machine local snapshots / borg / restic** | Restoring is always *additive* — the current state becomes a snapshot before the restore lands. Directly D-C4. | — |
| **Dropbox "conflicted copy" / Syncthing conflict files** | Never destroy either side. | The conflict file is a filename convention with no provenance — the user must forensically work out which is which. Our revisions carry device, time, and origin. |
| **Git** | Content-addressed identity, and refusing to proceed with a dirty working tree until it is dealt with — the shape of "capture before restore". | — |

*Mutable sources needing revalidation before the plan is locked:* the mGBA
override-database behaviour and the NSO exclusion list are both live and can
change; neither is load-bearing for a decision here, only for the rationale.

---

## 10. Options considered

| Option | Sketch | Pros | Cons | Failure modes | Reversibility | Effort |
|---|---|---|---|---|---|---|
| **1. Byte-exact only** — restore only onto the identical `rom_sha256` | one equality check | Trivially correct; zero false accepts; zero DAT dependency | Fails SAVE-03's real scenario whenever the clean Mac's copy differs at all (trimmed vs untrimmed, rev 1.0 vs 1.1) | User with a legitimate save is stonewalled with no remedy | Cheap to widen later | S |
| **2. Title-level match** — any two blobs the catalogue calls the same title | display-title / asset-set comparison | Almost always "just works" | Waves through medium mismatches → the erase path; display titles are user-editable | Real data loss | Costly (users learn to trust it) | S |
| **3. Emulator-version-bound** — gate on emulator+version too | pin digest equality | Feels safe | **Technically wrong** — battery saves are game-written and emulator-independent. Would block correct restores after every adapter bump and would forbid SEED-002 forever | False rejects; forecloses a seed | Cheap but pointless | S |
| **4. Three-tier: exact / same-title-with-DAT-certainty / incompatible** ← **chosen** | §3 | Correct per the technology; strict where destruction is possible; permissive where it is merely uncertain and recoverable; reuses `ReferenceMatch` rather than inventing a heuristic; degrades to tier 1 offline/without packs | One extra sheet in one case; requires denormalizing `title_identity` | Widened tier depends on reference-pack coverage | Cheap either way — thresholds are data | M |
| **5. Tier 4 + user-authored per-title override** | Ludusavi custom games | Escape hatch for the wrong cases | New persisted user-authored config surface, new sync entity, new UX, in a phase with no room for it | Overrides rot silently | Additive later | L — **deferred, not foreclosed** |

Chosen: **4**, with 5 explicitly named as the additive successor.

---

## 11. Adversarial pass on my own recommendation

**"Your widened tier will eat somebody's save."** Partly true. Some same-title,
same-medium regional pairs *do* store saves incompatibly, and the game will
offer to erase. My mitigations: (a) the pre-restore capture (D-C4) is
mandatory and blocking, so the destroyed thing is a working copy, never a
revision; (b) the erase can only reach the clonefile launch dir, never the CAS
(P3 D-20); (c) the sheet says exactly this in plain words rather than a generic
"are you sure". **Residual risk accepted and recorded:** a user who ignores the
sheet loses playtime and gets a confusing in-game message. They do not lose
data.

**"You hard-block medium mismatch with no override — some expert will want it."**
Yes, and I am refusing. There is no case where writing a 32 KB SRAM image into
a 64 KB Flash slot is what anyone wants; the correct expert workflow is export
(PORT-01) and use an external tool. The escape hatch already exists and it is
called PORT-01. **Not a residual risk — a stance.**

**"Denormalized `title_identity` will go stale and you'll reject valid
restores."** True. The direction of failure is toward strictness, the remedy is
"sync", and it is stated in the matrix. **Residual risk accepted.**

**"The gate silently depends on reference-pack coverage, so restore behaviour
varies by machine."** True and it is the most uncomfortable property here. A
user with packs installed gets more restores than one without, for the same
files. Mitigated by saying so in the exact-string microcopy ("Installing a
reference pack would let it check") and in the matrix. **Residual risk
accepted, honestly surfaced.**

**"You added a seventh readiness check to a frozen six-case enum."** Flagged as
F's call, not mine (§6), and restricted to non-blocking.

**"Always re-hashing is inconsistent with P3 D-23."** It is a *deliberate,
argued* divergence justified by a 4000× size difference, not an oversight, and
it is recorded as such so nobody 'fixes' it later.

**"`Attention.Reason` is frozen and you have an unbound-revision state with
nowhere to go."** Correct, and I chose **not** to extend the frozen vocabulary
(D-C11). The cost: an unbound revision is visible only on its own save
timeline, not in the global Needs Attention inbox. Accepted for Phase 4;
extending the vocabulary later is additive.

---

## 12. Recommendation — numbered decisions

**D-C1. The compatibility tuple is `{system_id, save_kind, medium_id,
artifact_bytes, rom_sha256, title_identity, origin}` plus a non-gating
`provenance` map.** *Rationale:* a battery save is written by the game, so
emulator/core/version are provenance, never gates — gating on them would be
save-state thinking applied to the wrong artifact. *Reversibility:* cheap —
fields are additive journal payload; promoting a provenance field to a gate is
a policy change, not a migration.

**D-C2. The gate returns three tiers — `exact`, `same_title`, `incompatible` —
not a boolean.** *Rationale:* the binary framings are each wrong in one
direction (byte-exact stonewalls the real scenario; title-level enables the
erase path). *Reversibility:* cheap — thresholds are data.

**D-C3. `medium_id` and `artifact_bytes` mismatch is a hard block with no
override, ever.** *Rationale:* GBA backup media share memory-map space through
incompatible interfaces; a mismatched write is the documented path to a game
erasing the save. *Reversibility:* one-way in practice — do not soften it.

**D-C4. Restore never overwrites in place: the current on-disk `.sav` is
captured as its own revision first, and a failed capture aborts the restore.**
*Rationale:* it is what converts every override from a data-loss gamble into a
recoverable attempt, and it is what the constitution's #1 priority demands.
*Reversibility:* cheap to keep, catastrophic to remove.

**D-C5. Every gate input is denormalized onto the `save` journal payload at
capture time; the client evaluates the verdict locally with zero network
calls, ever.** *Rationale:* SAVE-03's scenario is a clean Mac, which may be
offline; a gate needing a server join fails precisely when it matters, and
CACH-04 forbids it at preflight regardless. *Reversibility:* costly — retrofit
would require a backfill.

**D-C6. The `same_title` tier requires a `ReferenceMatch` `:matched` /
`confidence: :exact` reading on both sides against the same DAT title; a
`:variant`, `:no_match`, or absent reading never widens the gate.**
*Rationale:* reuses Phase 2's only real identity mechanism instead of inventing
a filename or title-string heuristic, and satisfies the honesty constraint by
degrading to byte-exact when we do not actually know. *Reversibility:* cheap.

**D-C7. Restore is an explicit action on the save timeline, never automatic,
plus a non-blocking offer at preflight.** *Rationale:* auto-restore on first
launch would silently overwrite local work — a named constitutional
prohibition. *Reversibility:* cheap. **Assumes area F's answer; see §6.**

**D-C8. Save revisions are always fully re-hashed at restore time; the P3 D-23
size+inode+mtime cheap check is deliberately not used here.** *Rationale:* the
cheap check exists for hundred-megabyte ROMs; on a ≤128 KB file it buys
nothing measurable and costs a whole staleness-reasoning surface.
*Reversibility:* cheap; record the reasoning so it is not "optimised" later.

**D-C9. Digest mismatch quarantines the local object (never deletes),
raises a no-blame redownload remedy, and blocks with no override when offline.**
*Rationale:* mirrors P3 D-23 corruption handling and P3 D-21's no-silent-deletion
rule; a known-bad blob in a save slot is the worst outcome available here.
*Reversibility:* cheap.

**D-C10. The compatibility rule is adapter-declared. Add these `save_contract`
fields to `03-ADAPTER-PIN.json`, all additive and all decoded as Swift
`Optional`s with defaults so the shipped pin still decodes:**

```json
"save_kind": "battery",
"media": [
  {"id": "eeprom_512",  "bytes": 512},
  {"id": "eeprom_8k",   "bytes": 8192},
  {"id": "sram_32k",    "bytes": 32768},
  {"id": "flash_64k",   "bytes": 65536},
  {"id": "flash_128k",  "bytes": 131072}
],
"medium_detection": "emulator_infers_from_rom_bytes",
"size_is_medium_identity": true,
"accepts_foreign_medium": false,
"portable_across_emulators": true,
"max_artifact_bytes": 131072,
"proven_media": ["sram_32k"],
"binding_fields": ["system", "save_kind", "medium_id", "artifact_bytes", "rom_sha256"],
"provenance_fields": ["emulator", "emulator_version", "core_version", "adapter_pin_sha256"]
}
```

*Rationale:* `binding_fields` vs `provenance_fields` is the whole seam — shared
client logic evaluates equality over whatever the pin says binds, and knows
nothing about GBA. `proven_media` keeps the support matrix honest about the one
medium the spike actually observed. *Reversibility:* cheap (additive); the
`AdapterSaveContract` struct must gain optionals, not required fields.

**D-C11. Do not extend the frozen `Attention.Reason` vocabulary. An
unidentifiable revision carries `binding_status: :unbound` and surfaces on its
own save timeline only.** *Rationale:* the frozen vocabulary is a deliberate P2
constraint; a save-format question is not an import-inbox question.
*Reversibility:* cheap — adding a reason later is additive.

**D-C12. Two new registered problem codes: `save_binding_incompatible` (422)
and `save_revision_digest_mismatch` (422).** *Rationale:* P1 D-22 — clients key
microcopy off `code` only. *Reversibility:* cheap.

**D-C13. Extend `docs/SUPPORT-MATRIX.md` with the save-restore section in §8
verbatim, including `proven_media: ["sram_32k"]` stated as the only proven
medium.** *Rationale:* the honesty constraint; the file already models the right
register. *Reversibility:* cheap.

---

## 13. Forward compatibility — the exact fields

| Seed | The field that keeps the door open | What I deliberately did **not** build |
|---|---|---|
| **SEED-019** (system saves vs save states) | **`save_kind`** on the binding, and **`binding_fields` in the pin.** A future save-state adapter entry declares `save_kind: "state"` with `binding_fields` including `emulator_version` and `adapter_pin_sha256` — the *same* client gate code then correctly refuses a state across emulator builds, with **zero client change**. The gate is generic over the pin's declaration. | No save-state capture, storage, surface, or vocabulary beyond the enum value. |
| **SEED-002** (physical cartridge) | **`origin`** (`emulated` / `cartridge`) plus the fact that the gate's identity fields are *content* facts, not emulator facts. A cartridge-sourced save has `origin: "cartridge"`, no `rom_sha256` (there is no ROM blob), and would resolve identity through a third tier keyed on the cartridge header game code — added as a new tier, not a reshaping of the tuple. `portable_across_emulators: true` in the pin is the standing assertion that makes this coherent. | No hardware path, no game-code identity tier, no dump/write flow. |
| **SEED-001** (save curation) | The **`provenance` map** — `emulator, emulator_version, core_version, adapter_pin_sha256, captured_at, device_id, origin` — plus `binding_status` distinguishing known from inferred. SEED-001's list (origin device, import method, emulator/core+version, content fingerprint, format identity, capture time, revision ancestry, conversion history, known-vs-inferred) is a superset with `import_method`, ancestry (area B), and `conversion_history` as the only gaps; the map is open. | No naming, notes, tags, treasuring, or any curation surface. |
| **Ludusavi-style user override** | The pin's `save_contract` is data, so a per-title override table is an additive layer above it. | Not built (option 5). |

---

## 14. How this is proven (03.5 D-03: named, discovered, executed, non-skipped)

**Runnable now with synthetic fixtures** — a 32768-byte pseudorandom file is a
perfectly valid `sram_32k` artifact for every test below; none of them need a
real ROM or a real emulator. Fixtures are generated (03.5 D-09 — no copyrighted
ROMs, no BIOS).

| Test | What it proves |
|---|---|
| `SaveBindingGateTests.testExactTierRestoresWithoutAcknowledgement` | Happy path |
| `SaveBindingGateTests.testDifferentSystemIsHardBlockedWithNoOverrideAffordance` | Asserts the override action is **absent**, not merely unused |
| `SaveBindingGateTests.testDifferentSaveKindIsHardBlocked` | SEED-019 door held shut |
| `SaveBindingGateTests.testMediumMismatch32KSramInto64KFlashIsHardBlockedWithNoOverride` | **The destructive case.** Asserts no override affordance exists |
| `SaveBindingGateTests.testSizeNotInPinMediaTableYieldsUnboundAndIsNotRestorable` | Unbound handling |
| `SaveBindingGateTests.testSameTitleWithCertainDatMatchOnBothSidesRequiresAcknowledgement` | Widened tier, gated |
| `SaveBindingGateTests.testSameTitleWithVariantOrNoMatchReadingIsHardBlocked` | Honesty constraint |
| `SaveBindingGateTests.testGateIsGenericOverPinDeclaredBindingFields` | Feeds a synthetic pin with `binding_fields` including `emulator_version` and asserts the gate then rejects an emulator-version mismatch — **the SEED-019 seam, proven without building save states** |
| `SaveRestoreTests.testPreRestoreStateIsCapturedAsRevisionBeforeAnyWrite` | D-C4 ordering |
| `SaveRestoreTests.testFailedPreRestoreCaptureAbortsRestoreAndLeavesTargetUntouched` | D-C4's failure branch — the one that actually protects data |
| `SaveRestoreTests.testRestoreIsAtomicWriteTempThenRename` | Torn-write safety; asserts the target is never observed partial |
| `SaveRestoreTests.testWrittenFileIsRehashedBeforeRenameAndMismatchAborts` | Post-write verification |
| `SaveRevisionDigestTests.testRestoreAlwaysFullyRehashesRegardlessOfCheapCheckState` | D-C8 — deliberately asserts the cheap check is **not** consulted (stale inode/mtime fixture still triggers a full hash) |
| `SaveRevisionDigestTests.testDigestMismatchQuarantinesObjectRetainsBytesAndOffersRedownload` | D-C9; asserts the bytes still exist on disk |
| `SaveRevisionDigestTests.testDigestMismatchOfflineBlocksWithNoOverride` | D-C9 offline branch |
| `SaveRestoreOfflineTests.testCleanMacRestoreMakesZeroNetworkCalls` | **CACH-04.** Injected URL protocol that fails the test on any request; end-to-end restore against a pre-seeded LocalStore + CAS |
| `SaveRestoreOfflineTests.testTitleIdentityIsReadFromLocalStoreNotFetched` | D-C5 |
| `AdapterPinTests.testShippedPinDecodesWithNewOptionalSaveContractFields` | Additive-contract guarantee |
| `SaveRestoreCopyTests.testEveryVerdictHasNonEmptyFindingAndBlockingOnesHaveRemedy` | Mirrors the existing readiness invariant — no blocking state ships without a remedy |
| `SaveRestoreA11yTests.testVerdictIsNeverConveyedByColourAlone` | WCAG 1.4.1 / P3 D-13 |
| `SaveBindingServerTest` (ExUnit) | `save_binding_incompatible` / `save_revision_digest_mismatch` are registered, return 422 problem+json, and the payload round-trips additively |

**What remains blocked on checkpoint 7 (real emulator + real game bytes):**
that a restored `.sav` is *accepted by the running game* — that the emulator
picks up the file, the title screen offers Continue, and the player's progress
is there.

**The closest honest automated proxy**, and I am explicit that it is a proxy:

> `SaveRoundTripTests.testCapturedRevisionRestoresToByteIdenticalArtifactInLaunchDir`
> — capture a `.sav` from a launch dir, restore it into a fresh launch dir on a
> simulated clean machine, assert the bytes at the emulator's exact
> `artifact_glob` path are byte-identical and the file's mode and size are
> right.

That proves the *file* half of SAVE-03 completely. It does **not** prove the
*game* half. "Continue the game" is a human observation and I will not dress a
byte comparison up as one.

**Named blocked checkpoint (carry forward, do not quietly close):**

> **CP7-SAVE-C — clean-Mac restore, human-observed.** On a second Mac with a
> fresh install: pair, sync, download the game, restore the save revision from
> the timeline, launch mGBA 0.10.5, and observe the game's own Continue/Load
> screen showing the restored progress. Blocked on real emulator + real game
> bytes, exactly like the rest of checkpoint 7. Evidence: a screen recording
> and the revision digest. Not automatable; not to be marked passed by any
> test above.

---

## 15. Coherence notes — what I assume of the other areas

- **A (capture trigger / loss window):** I assume capture produces the full
  `SaveBinding` at capture time — A owns *when*, I own *what is recorded*. If A
  captures opportunistically from a not-yet-flushed file, `artifact_bytes` is
  still the file's true size, so `medium_id` derivation is unaffected. **No
  collision, one dependency:** A must call the binding builder.
- **B (lineage / conflict detection):** the gate is orthogonal to ancestry —
  it never reads a parent pointer. **⚠ Collision risk:** if B makes lineage
  edges load-bearing for *which* revision is offered, my "restore never
  overwrites, capture first" rule creates a new revision on every restore and
  B must decide its parent. **My assumption:** the pre-restore capture's parent
  is the current local head, and the restored file's revision (if B models one)
  descends from the restored revision. B decides; I need only that the capture
  happens.
- **D (retention / dedupe / storage):** I depend on **content-addressed
  dedupe**, or D-C4 creates a redundant 32 KB object on every restore.
  **⚠ Collision:** D must guarantee a pre-restore capture that is
  byte-identical to an existing revision costs zero bytes and does not clutter
  the timeline. Also: **a quarantined revision object must be exempt from
  eviction** (D-C9 retains bytes; P3 D-21 forbids silent deletion anyway).
- **E (status ladder / one status slot):** I add **no** card status. Every
  verdict lives on the save timeline row, not the library card. **⚠ Collision
  if E decides otherwise:** P3 D-13's single slot cannot express three verdict
  tiers, and I explicitly do not ask it to.
- **F (launch readiness / preflight):** **⚠ Loudest collision.** See §6. I
  assume a seventh non-blocking `saveContinuity` `ReadinessCheckKind`, last in
  order, `.ready`/`.warning` only. F may overrule; only step 9 of the flow
  moves.
- **G (conflict resolution UX):** G's flow will almost certainly *end* in a
  restore, so **G must route through this gate** rather than writing a `.sav`
  directly. **⚠ Collision:** if G's "keep theirs" writes a file, it inherits
  D-C3, D-C4, and D-C8 unconditionally. Stated loudly.
- **H (export shape):** an `unbound` or `incompatible` revision is still fully
  exportable — PORT-01 has no compatibility gate and must not grow one. **I
  also assume H exports the `SaveBinding` and `provenance` into the sidecar**;
  that is what makes an exported save self-describing and is SEED-001's
  substrate. H owns the layout.

## 16. Open questions

None that block a plan. The two nearest calls I made rather than deferred, with
the assumption stated: (a) F's readiness-check shape (§6), (b) whether an
unbound revision reaches the Needs Attention inbox — I said no rather than
extend a frozen vocabulary (D-C11).
