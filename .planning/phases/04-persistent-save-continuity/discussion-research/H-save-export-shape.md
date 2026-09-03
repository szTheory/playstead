# H — Save Export Shape in the Deterministic Layout (PORT-01)

**Scope:** where save revisions land in the existing Phase 2 BagIt export, what the
manifest says about them, and how a person verifies and reuses them.
**Not in scope:** how revisions are captured (A), how lineage/conflict is modelled (B),
the restore gate (C), retention/storage (D), status surfacing (E), preflight (F),
the conflict-resolution UX (G). This file consumes those; it does not decide them.

---

## 0. The single most important finding: Phase 2 already built the socket

Grepped, not assumed. Phase 2 did not just leave room for saves — it cut the hole
and labelled it. Three live reservations exist in shipped code:

| Reservation | Location | Current value |
|---|---|---|
| Per-set `saves/` subfolder path | `export/layout.ex:123` — `saves_path: Path.join(relative_dir, "saves")` | computed on every set plan, never written |
| Reserved `saves` key in root **and** per-set sidecar | `export/sidecar.ex:32,50` | `%{"kind" => "reserved", "entries" => []}` |
| `saves` as a reserved filename | `export/sanitize.ex:77` `reserved_saves_name?/1`; `layout.ex:133` renames a member that collides | live, with a passing test (`layout_test.exs:87`) |

P2 **D-39** states this verbatim: *"the root manifest reserves `saves[]`; every set
folder reserves a `saves/` subfolder (a member literally named `saves` is renamed by
the sanitize rule)... **Reversibility: one-way** for the reserved names, schema id,
and endpoints."*

**Consequence for this area:** question 1 ("folder shape") is not open. It was
decided in Phase 2 as a one-way decision and the code already computes the path.
My job is to fill the reservation, not to relitigate it. I spend the argument budget
below on what is genuinely open: what goes *inside* `saves/`, how files are named,
what determinism means against a moving head, and what the manifest says.

Two drift notes found while grepping (implementation is truth, docs are stale):
`02-CONTEXT.md` D-34 says `playstead-manifest.json`, `_unsorted/`, `_quarantined/`;
the code writes `playstead-bag.json`, `unsorted/`, `quarantine/`. Phase 4 follows the
code. Someone should fix the Phase 2 context doc, but not in this phase.

---

## 1. JTBD framing

**Who / when / where.** A self-hoster, six months into a playthrough, sitting at the
server's web console — or standing over a machine they are about to reformat, sell,
or migrate off Playstead entirely.

**Four distinct jobs, and they pull in opposite directions:**

| # | Job (user's words) | What they need | What they get back |
|---|---|---|---|
| J1 | "Get my save out so I can play this on my Steam Deck tonight." | One file, named what the other emulator expects, sitting somewhere obvious. | A drop-in `.sav`. |
| J2 | "I want off Playstead. Give me *everything*." | Every byte, no editorial. | Full revision history. |
| J3 | "Which of these two conflicting saves is my real progress?" | Both branches visible as branches, with device and time. | A legible history. |
| J4 | "Prove this export is intact five years from now." | Digests, standard tools, no Playstead binary. | `sha256sum -c`. |

**J1 and J2 are in direct tension and this is the whole design problem.** J1 wants a
folder with one file in it. J2 wants a folder with four hundred. Every mediocre answer
in the prior art picks one and loses the other. The two-tier shape in D-H1 is the
answer: J1's file at eye level, J2's history exactly one folder down.

**Domain nouns/verbs/events falling out:** *slot* (a save location within a set —
one for the pinned GBA adapter), *revision* (immutable bytes + lineage position),
*branch* (a divergent line within a slot), *drop-in copy* (the plain-named convenience
byte-copy of a linear slot's head), *export a set*, *verify an export*.

**Consumer-shaped, not provider-shaped.** Two backend guts leak into the user's view
and each needs a justification:
- **sha256 prefix in filenames.** Forced. It is the collision tiebreaker of last
  resort and the thing that makes a filename checkable by eye against
  `manifest-sha256.txt`. J4 cannot be served without it. Kept to 8 hex chars.
- **sequence numbers in filenames.** Forced by D-34's no-timestamp rule (§4). A
  human reads `000007` as "the seventh save" without instruction; this is arguably
  *more* consumer-shaped than an ISO timestamp.
- Deliberately **not** leaked: revision UUIDs, journal cursors, blob store paths,
  idempotency keys, `member_fingerprint`, parent pointers *as filenames* (parents
  appear in the sidecar, where they are data, not navigation).

---

## 2. Prior art

Researched this session unless marked. Mutable sources flagged.

### Fetched and verified this session

**BagIt / RFC 8493** — https://www.rfc-editor.org/rfc/rfc8493.html
- *Right:* `data/` "MAY be organized in arbitrary subdirectory structures... such
  subdirectory structures and filenames have no given meaning." A `saves/` subfolder
  is unambiguously legal; no profile change needed.
- *Right:* tag manifests must list every payload manifest and must not list tag
  manifests. Our writer already obeys this. Save sidecar content added to
  `playstead-set.json` is automatically covered — **zero writer changes for tag
  coverage.**
- **Documented footgun we must refuse:** `fetch.txt`. It exists precisely for "payload
  files listed in manifests but absent locally, available at a URL." It is the
  syntactically obvious home for a local-only-on-a-Mac revision. **Do not use it.** A
  bag with `fetch.txt` is an *incomplete bag*: it fails validation until the fetch is
  performed, and `sha256sum -c manifest-sha256.txt` — the exact command our
  `README.txt` tells the user to run — fails loudly on the missing file. There is
  also no URL to put there (an offline Mac is not an origin server). Using it would
  trade an honest gap for a broken export. See D-H7.
- *Also:* `Bagging-Date`, `Bag-Size`, `External-Description`,
  `Internal-Sender-Description` are reserved `bag-info.txt` elements. We already write
  `Bagging-Date`. Noted for §4's determinism carve-out.

**Ludusavi** — https://github.com/mtkennerly/ludusavi/blob/master/docs/help/backup-structure.md
The closest prior art in this exact domain (game-save backup to ordinary folders).
- *Right:* one subfolder per game, named from the game's title with invalid characters
  replaced by `_`, with a `ludusavi-renamed-<ENCODED>` fallback when the whole name
  sanitizes away. This is **the same design our `Sanitize.component/1` +
  `fallback_if_empty("unnamed")` already implements** — independent convergence is a
  good sign we are not being clever.
- *Right:* a per-game metadata file (`mapping.yaml`) *inside the game's folder*, so
  the metadata travels with the bytes.
- *Divergence we accept deliberately:* Ludusavi's metadata is **in the payload folder**;
  ours is a tag file under `tags/`, because Phase 2 already put `playstead-set.json`
  there and consistency with a shipped one-way decision beats local optimisation. See
  D-H5 and the adversarial pass, where this is the weakest point of my recommendation.
- *Footgun:* `mapping.yaml` stores **absolute source paths** and restore defaults to
  them (https://github.com/mtkennerly/ludusavi/discussions/321 — *seen in search
  results, not fetched; treat as unverified*). Absolute paths make a backup
  machine-specific and are a traversal vector on restore. Our sidecar records only
  bag-relative forward-slash paths, exactly as Phase 2 already does for members
  (`Path.join("data", m.relative)`).
- *Footgun:* Ludusavi's docs describe format *variants* (simple vs zip, drive folders)
  but the fetched doc says nothing about how multiple backup generations are named or
  distinguished. A backup tool whose own documentation cannot explain its versioning
  layout is the failure mode PORT-01's "readable manifest" exists to prevent.

**RetroArch save naming** — https://github.com/libretro/RetroArch/issues/15960,
https://github.com/libretro/RetroArch/issues/13746
- The convention is hard: `{romBaseName}.srm` beside/under the save dir; RetroArch
  derives it from the ROM filename at launch.
- *Footgun, twice documented:* the base name is derived from **the launch path**, so a
  ROM launched from inside an archive, via a command line, or via a subsystem
  (SGB) produces a *different* save filename and the user silently gets a fresh save.
  Real users lose progress to this. **Design consequence:** our drop-in copy must be
  named from the **set's primary member's recorded original basename** — the same
  string the launch materializer uses — not from the display title, or we reproduce
  this bug in export form.
- mGBA standalone (our pinned adapter, `03-ADAPTER-PIN.json`) writes `.sav`;
  the RetroArch mGBA core writes `.srm`. For a **raw** 32 KB SRAM battery file these
  are byte-identical content under two extensions; conversion guides that say "just
  rename" are correct *for this case* and wrong in general (they break for formats
  with headers or RTC footers). We ship `.sav` — the extension the producing adapter
  actually wrote — and record `format` in the sidecar so a future converter never has
  to guess. We do **not** ship a `.srm` alias: two names for the same bytes in one
  folder is the kind of helpfulness that becomes a support burden.

### From knowledge, not refetched this session (mark as such)

- **borg / restic:** content-addressed chunk stores with an opaque repository layout.
  *Right:* dedupe and immutability. *Wrong for us:* you cannot open a restic repo in
  Finder and see your save. PORT-01's "ordinary folders" is an explicit rejection of
  this model. Our answer is closer to `git bundle`/`fast-export`: a single artifact
  containing enough to reconstruct, in a documented format.
- **git:** DAG-with-parents is exactly the lineage shape (area B's problem, not mine),
  and `git log --graph`'s legibility is the bar for `saves.txt`. Notably git does
  *not* put commit history in filenames — history is in metadata, filenames are the
  working tree. Our two-tier shape mirrors that: `saves/{name}.sav` is the working
  tree; `saves/revisions/` + the sidecar are the history.
- **Google Takeout:** the canonical readability complaint — deep nested folders,
  machine-named files, JSON sidecars with no narrative, no way to tell what you have
  without writing a script. The specific failure is that *the metadata is complete and
  the experience is unusable*. `saves.txt` (D-H5) exists solely to not be Takeout.
- **Obsidian:** plain files, one concept per file, no database required to read your
  own data. This is the philosophy Phase 2 already adopted; saves inherit it.
- **Dropbox "conflicted copy" / Syncthing `.sync-conflict-*`:** both encode conflict
  in the *filename*, with a timestamp and a device name. *Right:* the conflict is
  visible without opening anything. *Wrong for us:* timestamps in filenames are
  banned by D-34, and device names are mutable user strings — renaming your Mac must
  not rewrite a past export. We encode branch as a stable letter and put the device
  name in the sidecar where it belongs. See D-H3.
- **Archival practice (BagIt-adjacent, e.g. Library of Congress bag guidance):**
  human-readable accompanying documentation is expected to be a plain-text file that
  a person can read with no tooling. `README.txt` already exists (D-40); `saves.txt`
  extends it per-set.

---

## 3. Options

### Option set 1 — What lives inside `saves/`

| # | Shape | Sketch | Pros | Cons | Failure modes | Reversibility | Effort |
|---|---|---|---|---|---|---|---|
| 1a | Flat: every revision directly in `saves/` | `saves/000001-a1b2c3d4.sav` … ×400 | Simplest plan; one code path | J1 destroyed — no obvious file to grab; 400-entry folder | User grabs the wrong (oldest, first-sorted) file and loses six months | cheap | S |
| 1b | Current only, in `saves/` | `saves/Pokemon Emerald (USA).sav` | Perfect for J1 | Violates PORT-01's "revisions" plural and criterion 4's "revision evidence"; silent lock-in | User believes they exported everything; history is stranded on the server | cheap | S |
| **1c** | **Two-tier: drop-in copy at eye level, history one level down** | `saves/{stem}.sav` + `saves/revisions/000001-….sav` + `tags/…/saves.txt` | Serves J1 and J2 simultaneously; self-explanatory in Finder; 32 KB duplication cost is nothing | One file's bytes appear twice in the payload manifest | A conflicted slot has no legitimate "current" — must be handled, not papered over (it is: D-H3) | costly (folder shape) | M |
| 1d | Parallel top-level `saves/` tree beside `data/<system>/` | `data/saves/gba/Pokemon…/` | Saves visible as a category | Contradicts P2 D-39 (one-way); divorces a save from its ROM, so J1 needs two folders open | Users copy the ROM folder and silently leave saves behind | one-way to undo | M |

**Chosen: 1c.** 1d is foreclosed by D-39 regardless.

### Option set 2 — Revision filename anatomy (no timestamps allowed, D-34)

| # | Scheme | Example | Pros | Cons | Failure modes | Rev. | Effort |
|---|---|---|---|---|---|---|---|
| 2a | Full digest only | `a1b2…64hex.sav` | Trivially unique and deterministic | Unsortable, unreadable, no history | User cannot tell newest from oldest; picks at random | cheap | S |
| 2b | Sequence only | `000007.sav` | Sortable, readable | Not unique across conflict branches; a lineage bug silently overwrites a revision in the plan | Two revisions plan to one path → one is lost at write time | cheap | S |
| **2c** | **`{seq:06}[-{branch}]-{digest8}.{ext}`** | `000007-a1b2c3d4.sav`, `000012-b-9f8e7d6c.sav` | Sortable, readable, unique, self-checkable against the manifest by eye, deterministic | Slightly noisy; needs a branch-letter rule | Digest-prefix collision (astronomically unlikely, handled by deterministic extension) | costly | M |
| 2d | 2c + device name | `000007-jons-macbook-a1b2.sav` | Conflict side obvious in the name | Device names are mutable and untrusted → renaming a Mac rewrites a past export; breaks append-only stability; new sanitization surface | Silent full-tree churn on a device rename | costly | M |

**Chosen: 2c.** 2d's mutability is disqualifying — see the Syncthing footgun above.

### Option set 3 — Where the readable narrative lives

| # | Placement | Pros | Cons | Rev. | Effort |
|---|---|---|---|---|---|
| 3a | `data/<sys>/<set>/saves/saves.txt` (payload) | Found instantly in Finder; Ludusavi's choice | Dilutes the shipped promise that `manifest-sha256.txt` is "exactly the set of game bytes"; derived metadata in the payload | costly | S |
| **3b** | **`tags/<sys>/<set>/saves.txt` (tag file)** | Exactly where `playstead-set.json` already lives; tagmanifest coverage is automatic; payload manifest stays pure game+save bytes | One folder away from the saves; needs a `README.txt` pointer | costly | S |
| 3c | JSON sidecar only, no text file | No new file kind | This is precisely the Google Takeout failure; "readable manifest" in PORT-01 is not satisfied by JSON alone | cheap | XS |

**Chosen: 3b**, plus a `README.txt` paragraph. This is the decision I am least
certain about; see the adversarial pass.

---

## 4. Determinism against a moving head (question 4, answered as a testable property)

Game bytes are immutable; the save head is not. "The export is deterministic" is
therefore three separate claims and only the first two are true.

**P1 — Plan purity (holds).** `Layout.plan/2` is a pure function of its inputs. Given
two structurally equal input lists — including equal save inputs, where a save input
is `{slot_id, sequence, branch_key, sha256, size_bytes}` — `plan/2` returns equal
plans. This is exactly the property `layout_test.exs:35` already asserts for members,
extended.

**P2 — Write reproducibility (holds, with a pre-existing carve-out).** Two
`write_bag/2` runs over the same plan produce byte-identical trees **except**
`bag-info.txt` and the single `tagmanifest-sha256.txt` line covering it, because
`bagit_writer.ex:46` writes `Bagging-Date: #{Date.utc_today()}`. **This carve-out
already exists in shipped Phase 2 code** — I am not introducing it, and RFC 8493
reserves `Bagging-Date` for exactly this volatile purpose. The test assertion is:

> hash every file in tree A and tree B into maps; after deleting the `bag-info.txt`
> and `tagmanifest-sha256.txt` keys, the maps are equal.

**P3 — Library stability over time (does NOT hold, and must not be claimed).** Adding
a revision changes the export. This is correct and unavoidable. What we *can*
guarantee is the strictly weaker and far more useful **append-only stability**:

> **Adding revisions to a slot never changes the path or bytes of any previously
> exported revision file.**

This holds because `sequence` is monotonic and `digest8` is per-revision. It has
exactly three honest exceptions, all of which must be documented and tested:
1. `saves/{stem}.sav` — the drop-in copy tracks the head. That is its job.
2. A slot going from one branch to two adds branch letters to the *new* branch's
   files; existing linear files keep no letter (D-H3's rule assigns letters only
   within a forked slot). Files at sequences at or after the fork point change.
3. A set gaining a second slot introduces the slot path segment (D-H3).

Exception 2 and 3 are the same inherited property as Phase 2's title-collision
suffix: `layout.ex:92` renames an existing set's folder the moment a second set
collides with it. I am not making the export less stable than it already is; I am
using the same idiom. Recorded as residual risk R3.

**Verifier needs no changes.** `verifier.ex` reads `manifest-sha256.txt` and
`tagmanifest-sha256.txt` and re-hashes whatever they list. Save revisions written
through the existing `write_member!`-shaped path land in `manifest-sha256.txt`
automatically, and the sidecar changes land in the tagmanifest automatically. The
"can `Verifier` express it?" question answers itself: it already does, because the
property is stated in terms of manifested files rather than in terms of saves.

---

## 5. Recommendation — numbered decisions

### D-H1 — Fill Phase 2's reservation exactly; do not invent a new tree

Save revisions live at `data/<system>/<set folder>/saves/`, the path
`Layout.plan_set/2` already computes as `saves_path`. Root and per-set sidecar
`"saves"` keys are filled in place. No new top-level folder, no BagIt profile change.

> *Rationale:* P2 D-39 declared these reserved names one-way; the code already
> computes the path and already renames a member called `saves`.
> *Reversibility:* one-way (inherited from D-39, not newly incurred).

### D-H2 — Two-tier interior; default `saves_scope: :all`, persisted on the export record

```
data/gba/Pokemon Emerald (USA)/
  Pokemon Emerald (USA).gba              <- member, original basename (unchanged)
  saves/
    Pokemon Emerald (USA).sav            <- drop-in copy of the head (D-H3)
    revisions/
      000001-3f9a21c4.sav
      000002-b7e0114d.sav
      000012-a-1122aabb.sav              <- conflict branch a
      000012-b-77c9d310.sav              <- conflict branch b
tags/gba/Pokemon Emerald (USA)/
  playstead-set.json                     <- gains a populated "saves" object
  saves.txt                              <- the readable history
```

`Layout.plan/2` gains `opts[:saves]` ∈ `:all | :current | :none`, read with
`Keyword.get(opts, :saves, :all)` — **the identical mechanism as
`include_excluded`** (`layout.ex:52`), not a new options system. Unlike
`include_excluded`, it is **persisted** as `ExportRecord.saves_scope` (string,
default `"all"`, validated by inclusion like `scope`) because it is a user choice and
`Export.Worker.build_layout/1` must reproduce the same plan on a resumed or
re-enqueued job. `include_excluded` can stay hardcoded per-scope because it is
derived from scope, not chosen.

> *Rationale:* PORT-01 says "revisions" plural and criterion 4 says "revision
> evidence"; a save-export tool that omits history by default is the lock-in the
> constitution forbids. 400 revisions × 32 KB = 12.8 MB — the "folder no human wants"
> problem is a *layout* problem, solved by the second tier, not a volume problem.
> *Reversibility:* costly (folder shape); the option itself is cheap.

### D-H3 — Filename anatomy: `{seq:06}[-{branch}]-{digest8}.{ext}`, slot segment only when needed

- **`seq`** — the per-slot monotonic sequence from area B's lineage, zero-padded to 6.
  Fixed width so lexicographic order equals chronological order without a special
  sort; 6 digits removes any realistic overflow worry given the 24 s flush cadence.
- **`branch`** — present **only** when the slot has more than one branch. A single
  lowercase letter assigned by sorting the slot's distinct `branch_key`s ascending
  (`a`, `b`, `c`, …). It is derived from a stable lineage key, **never** from a device
  name, so renaming a Mac does not rewrite the export.
- **`digest8`** — first 8 lowercase hex of the revision's sha256. Uniqueness backstop
  and eye-checkable against `manifest-sha256.txt`. On collision within a slot the
  prefix extends deterministically for the whole colliding group only: 8 → 12 → 16 →
  64. This is `Sanitize`/`Layout`'s existing collision idiom (`layout.ex:85-97`).
- **`ext`** — the adapter-declared artifact extension, `.sav` for the pinned mGBA GBA
  battery save. No `.srm` alias.
- **Slot path segment** — omitted when the set has exactly one slot; when it has more
  than one, revisions go under `saves/revisions/<sanitized slot label>/`. Same
  "suffix only on collision" idiom as set folders.

**The drop-in copy: yes, ship it — with one hard rule.** `saves/{stem}.sav`, where
`stem` is `Path.rootname/1` of the **primary member's recorded original basename**
(not the display title — see the RetroArch §2 footgun), passed through
`Sanitize.component/1`. It is a byte-copy of the slot head, appearing in
`manifest-sha256.txt` with the same digest as its `revisions/` twin, which
`sha256sum -c` handles without complaint.

> **The hard rule: a conflicted slot gets no drop-in copy.** A conflicted slot has no
> "current". Silently picking one would be exactly the last-write-wins the
> constitution and SAVE-04 forbid, performed by the export tool, in a file the user
> then copies onto their Steam Deck. Instead the sidecar carries
> `"current_path": null, "current_reason": "conflicted"` and `saves.txt` opens with
> the conflict. The same rule applies when a set has more than one slot: no
> unambiguous single drop-in name exists, so none is written.

> *Rationale:* J1 is a real, frequent job and a folder of `000007-…` files does not
> serve it; but the convenience file must never assert a resolution the system has not
> made. *Reversibility:* costly (filenames become user muscle memory and appear in
> manifests).

### D-H4 — Determinism is P1 + P2 + append-only stability, with three named exceptions

Adopt §4 verbatim as the specification. Claim exactly P1, P2, and append-only
stability with exceptions 1–3. Do **not** claim that a library exports identically
forever.

> *Rationale:* an overclaimed determinism property is a test that gets deleted the
> first time someone adds a revision. *Reversibility:* cheap (it is a test contract).

### D-H5 — Manifest: populate the reserved sidecar key with a nested branch structure, plus one plain-text `saves.txt`

**Per-set `playstead-set.json`** — `"saves"` goes from `{"kind":"reserved","entries":[]}`
to a populated object. Additive within schema major 1, exactly as D-35 permits.

```json
"saves": {
  "kind": "saves",
  "slots": [{
    "slot_id": "battery",
    "kind": "system_save",
    "label": "Battery save",
    "format": "raw_sram",
    "byte_size": 32768,
    "adapter": {"id": "mgba", "version": "0.10.5", "system": "gba"},
    "state": "conflicted",
    "current_path": null,
    "current_reason": "conflicted",
    "branches": [{
      "branch": "a",
      "head_sequence": 12,
      "revisions": [{
        "sequence": 12,
        "path": "data/gba/Pokemon Emerald (USA)/saves/revisions/000012-a-1122aabb.sav",
        "sha256": "1122aabb…",
        "size_bytes": 32768,
        "parent_sha256": "b7e0114d…",
        "bytes": "present",
        "captured_at": "2026-08-14T21:03:11Z",
        "device": {"id": "<uuid>", "name": "Jon's MacBook"},
        "play_context": {"session_minutes": 47},
        "label": null
      }]
    }, { "branch": "b", "head_sequence": 12, "revisions": [ … ] }]
  }]
}
```

- **`branches` is always present, even when linear** (one entry, `"branch": null`).
  A conflicted slot is therefore *structurally* incapable of serialising as a flat
  list that implies a single history — the requirement in question 5 is met by the
  schema, not by a convention a future writer can forget.
- **`captured_at` is not a D-35 violation.** D-35 bans *export-run* timestamps because
  they make a canonical file byte-unstable. `captured_at` is a fact *about the
  revision* — immutable content, identical on every re-export. Worth stating
  explicitly because it looks like a violation at a glance.
- Lineage/provenance fields (`parent_sha256`, `device`, `captured_at`,
  `play_context`) are **area B's vocabulary**, consumed here verbatim. See §7.

**Root `playstead-bag.json`** — counts only, keeping the canonical root file small
and byte-stable: `{"kind":"saves","slot_count":N,"revision_count":M,
"conflicted_slot_count":K,"missing_bytes_count":X}`.

**`tags/<sys>/<set>/saves.txt`** — the "readable" in "readable manifest". Plain text,
no tooling, `git log --graph` as the legibility bar and Google Takeout as the
anti-pattern:

```
Save history — Pokemon Emerald (USA)

Battery save (32 KB, raw SRAM, written by mGBA 0.10.5)
  This slot is CONFLICTED. Two devices saved from the same point.
  No drop-in copy was written; choose a side yourself.

  Branch a — last saved on Jon's MacBook, 14 Aug 2026 21:03
    12  000012-a-1122aabb.sav  1122aabb…  32768 bytes
    11  000011-3f9a21c4.sav    3f9a21c4…  32768 bytes
  Branch b — last saved on Studio Mini, 14 Aug 2026 20:58
    12  000012-b-77c9d310.sav  77c9d310…  32768 bytes
  Shared history before the split
    11 …

Verify every file: sha256sum -c manifest-sha256.txt   (from the export's top folder)
```

**`README.txt`** gains one paragraph naming `saves/`, the drop-in file, and where the
history lives. Its text already lives in `priv/static/export-readme.txt` (D-40) — the
single-source rule holds.

> *Rationale:* the JSON satisfies machines and a future importer; the text file
> satisfies the human PORT-01 is written for; the nested `branches` makes the
> conflicted case unlieable. *Reversibility:* one-way for the sidecar shape (it is
> published schema); cheap for `saves.txt` wording.

### D-H6 — Save **reimport is out of scope for Phase 4**, and the export is built so it stays possible

Roadmap criterion 4 says *"verify the exported bytes and revision evidence"* — it does
not say reimport. PORT-02 (verify + reimport, no byte changes) is already `[x]`
Complete against Phase 2's game bytes.

**What Phase 4 guarantees:** exported save bytes are the exact stored bytes; every
exported revision is listed in `manifest-sha256.txt` in `sha256sum -c` format and
re-verified by `Verifier`; the sidecar carries the complete lineage.

**What Phase 4 explicitly does NOT guarantee:** that reimporting an export
reconstitutes save revisions, reattaches them to a set, or preserves the lineage DAG.
Phase 2's `Import` path treats an unrecognised file as an opaque blob and will
continue to do so for `.sav` files. This must be stated in `README.txt` in one
sentence rather than left for a user to discover.

**How the door stays open, and is tested:** the sidecar carries every field a future
importer needs — `slot_id`, `sequence`, `branch`, `parent_sha256`, `sha256`,
`captured_at`, `device`, `format`, `adapter`. A `round_trip_test` assertion checks
those keys are present, so the forward-compatibility claim is a passing test rather
than a comment (03.5 D-03).

> *Rationale:* overclaiming reimport widens the phase and risks a half-built importer
> that silently duplicates a user's history. *Reversibility:* cheap — reimport is
> purely additive later.

### D-H7 — A revision whose bytes the server lacks: named in the manifest, raised as attention, never `fetch.txt`, never blocking

Ordered rules:
1. **Never silently omit.** The revision appears in the sidecar with
   `"bytes": "missing"`, no `path`, and a `reason`, and in `saves.txt` as an explicit
   line: `  9  (not on this server — only on Studio Mini)`.
2. **Not in `manifest-sha256.txt`** (there is no file to verify) and **not in
   `fetch.txt`** — §2 explains why: it would make the bag *incomplete* per RFC 8493
   and break the `sha256sum -c` command our own README tells the user to run, in
   exchange for a URL that does not exist.
3. **Raise one `Playstead.Attention` item** (existing context, existing inbox, P2
   D-26 grouping): *"3 save revisions are only on Studio Mini and were not exported.
   Connect that Mac and export again to include them."* One item per export, grouped —
   not one per revision.
4. **Do not block.** The export still reaches `verified`. Refusing to export a
   library because one revision is stranded on an offline laptop denies the user the
   other 99% at the exact moment they are trying to get their data out. Constitution
   priority 1 (data safety) argues for honest-and-loud over blocked.
5. Root sidecar carries `missing_bytes_count` so the gap is machine-detectable, and
   because it is deterministic it belongs there rather than in `bag-info.txt`.

> *Rationale:* an export that quietly drops rows is the failure this whole
> requirement exists to prevent; an export that refuses to run is a worse one.
> *Reversibility:* cheap.
> **Collision with area D — see §7. If D guarantees the server holds bytes for every
> revision it has a record of, rules 1–5 become dead code that still must exist as a
> tested invariant.**

### D-H8 — Security: reuse, do not add, filesystem primitives

- **Every** saves path component goes through `Sanitize.component/1`, and every write
  goes through `Sanitize.safe_join/2` — the second, independent check. The drop-in
  stem and any slot label are the only two components derived from untrusted strings;
  `seq`, `branch`, and `digest8` are machine-generated and have no traversal surface.
  A hostile display title is already handled at the set-folder level by shipped Phase 2
  code and needs no new work — **the saves plan introduces no new filesystem
  primitive**, which is the security argument, not a mitigation list.
- **Free-space preflight.** `Playstead.Readiness` has `free_bytes/1` (`readiness.ex:328`)
  and an `:exports` row (`:219`). The preflight sum must include save revision bytes
  **plus** the drop-in copies (the head's bytes are written twice). At 32 KB per
  revision this never dominates, but a sum that silently omits a category is the kind
  of gate that rots (see the 03.5 fail-open lesson in project memory).
- **No secrets, no PII beyond the user's own data.** Sidecar carries `device.id` as an
  opaque UUID and `device.name` as the user's own chosen label — their data, in their
  export. It must **not** carry: pairing secrets, auth tokens, HMAC journal cursors,
  `Idempotency-Key`s, hardware serials/UDIDs, or absolute filesystem paths from the
  Mac (the Ludusavi `mapping.yaml` footgun). Digests are not secrets and are the point.
- Untrusted bytes are never parsed. A `.sav` is copied byte-for-byte; nothing in the
  export path opens or interprets save content.

> *Reversibility:* cheap.

### D-H9 — The seam: `Export.Layout` is handed save data and never reaches into the saves context

The P2 D-12 rule ("storage adapters stay free of format knowledge") maps onto:
**`Export.Layout` gets data, never a query.** Concretely:

```
Playstead.Saves            — owns revisions/lineage (areas B, D). Exposes
  export_inputs(user_id, asset_set_ids) -> %{asset_set_id => [save_input]}
      where save_input = %{slot_id:, slot_label:, kind:, format:, byte_size:,
                           sequence:, branch_key:, sha256:, size_bytes:,
                           parent_sha256:, captured_at:, device:, play_context:,
                           bytes: :present | :missing}

Playstead.Export           — the ONLY module that calls Playstead.Saves.
  to_layout_input/2 gains a :saves key, populated by the caller, exactly as
  :members already is (export.ex:63).

Playstead.Export.SavesPlan — NEW. Pure. Turns [save_input] into planned file
  entries: sequence padding, branch letters, digest-prefix collision extension,
  slot segmentation, drop-in eligibility. No Repo, no Saves, no filesystem.

Playstead.Export.Layout    — calls SavesPlan with the data already in the set map.
  Never aliases Playstead.Saves.

Playstead.Export.BagitWriter — unchanged shape: saves flow through the existing
  write_member!-style path. Bytes come from Playstead.Blobs.stream/2 (export.ex's
  moduledoc rule: never Blobs.Store directly).
```

`SavesPlan` as its own module — rather than 120 more lines in `Layout` — mirrors
`Sanitize`: the naming rules are the subtle part and deserve their own unit test file.
Dependency direction is one-way: `Export → Saves` at the context boundary only.

> *Rationale:* the analogous Phase 2 lesson, applied literally. *Reversibility:* cheap.

### D-H10 — One export surface: the server console. No Mac export action in Phase 4.

- **`exports_live.ex`** (`:53` `phx-click="export_library"`, `:102` handler) gains a
  single control beside the existing button: *"Include save revisions: All ·
  Current only · None"*, default **All**, persisted to `ExportRecord.saves_scope`.
  One control, quiet by default, matching the ethos. Non-colour-only by construction
  (it is text), keyboard-native as a radio group / `<select>`.
- **The Mac client gains no export action in Phase 4.** Export is server-side by
  D-33; a client-side writer would be a second implementation of the deterministic
  layout and a second thing to keep byte-identical. Stated as a decision so it is not
  quietly assumed either way.
- **Area G (SAVE-04 "export either side") routes through this same machinery.** The
  shared entry point is `Playstead.Export.create_export/3`. Two observations G should
  build on rather than around:
  1. Exporting a conflicted set **already** exports both sides — each branch head is
     its own file under `saves/revisions/`, and `saves.txt` names which device wrote
     which. "Export either side" may need no new code path at all, only a deep link
     to the right filename.
  2. If G genuinely needs a one-revision export, it is
     `create_export(user_id, :set, target_name:, asset_set_id:, saves_scope: {:revision, id})`
     — same worker, same layout, same manifest, one additional option value. **I am
     specifying the entry point, not G's flow.** Flagged in §7.

> *Reversibility:* cheap for the console control; costly for the shared entry point
> once G depends on it.

### D-H11 — Forward compatibility: the exact field per seed

| Seed | The seam that keeps it open | Deliberately NOT built |
|---|---|---|
| **SEED-002** (cartridge write-back) | `format: "raw_sram"` + `byte_size: 32768` + the drop-in `saves/{stem}.sav` are precisely a cart writer's inputs — a flasher needs exact bytes at an exact size under a predictable name, which is what the drop-in file is. | Any conversion, padding, endianness handling, RTC-footer awareness, or `.srm` alias. |
| **SEED-019** (save states ≠ system saves) | Three structural guards, all present on day one: (a) every slot carries `"kind": "system_save"` so no reader may assume; (b) a save state must land in a **differently named sibling folder** (`states/`, not `saves/revisions/`) with its own `kind` and a `portability` object naming the emulator build/options fingerprint; (c) **the drop-in plain-name copy is defined only for `kind: "system_save"`** — a save state can never earn a drop-in name, because a drop-in name is a portability claim and a save state cannot make one. That third guard is what mechanically prevents the folder from lying. | `states/`, the portability fingerprint fields, any save-state capture. |
| **SEED-001** (curation, names, notes on treasured revisions) | Each revision object reserves `"label": null` — the same reserve-an-empty-field idiom D-39 used for `saves` itself, which is exactly why that idiom was worth having. Filenames stay machine-derived so a future label never renames a file (labels are metadata, not navigation — the git lesson from §2). | Any naming/tagging/treasuring UI or storage; no label ever affects a path. |

### D-H12 — How this is proven (named tests, 03.5 D-03)

Extending the existing files. Every one is a real assertion, not "exited zero"; none
use fixed sleeps.

| # | File | Test name | Proves |
|---|---|---|---|
| 1 | `layout_test.exs` | "planning a library with save revisions twice produces identical output" | §4 P1 |
| 2 | `layout_test.exs` | "revision filenames sort by sequence and carry the digest prefix" | D-H3 |
| 3 | `layout_test.exs` | "revisions colliding on sequence, branch and digest prefix extend the prefix deterministically" | D-H3 collisions |
| 4 | `layout_test.exs` | "a conflicted slot produces no drop-in save file and records the reason" | **D-H3 hard rule — the anti-LWW guard** |
| 5 | `layout_test.exs` | "a linear slot's head is additionally written under the primary member's base name" | J1 / D-H3 |
| 6 | `layout_test.exs` | "a set with two slots segments revisions by slot and writes no drop-in copy" | D-H3 |
| 7 | `layout_test.exs` | "saves :none omits the saves subfolder entirely and :current omits revisions/" | D-H2 |
| 8 | `layout_test.exs` | "a hostile display title and a hostile slot label plan no path outside data/" | D-H8 |
| 9 | `saves_plan_test.exs` (new) | "branch letters follow sorted branch keys and ignore device names" | D-H3 / Syncthing footgun |
| 10 | `bagit_writer_test.exs` | "save revisions appear in manifest-sha256.txt in sha256sum -c line format" | J4 |
| 11 | `bagit_writer_test.exs` | "a missing-bytes revision is absent from the payload manifest and present in the sidecar as missing" | D-H7 |
| 12 | `sidecar_test.exs` | "a conflicted slot serialises as two branches, never a flat revision list" | D-H5 structural guarantee |
| 13 | `sidecar_test.exs` | "an unknown sidecar major version still causes the whole sidecar to be ignored with saves present" | D-35 rule survives |
| 14 | `verify_test.exs` | "verify/1 re-hashes exported revisions and names a tampered revision without deleting it" | D-H4 / Verifier reuse |
| 15 | `worker_test.exs` | "two export runs of the same revision set differ only in bag-info.txt and its tagmanifest line" | §4 P2 |
| 16 | `worker_test.exs` | "adding a revision leaves every previously written revision file byte-identical" | §4 append-only |
| 17 | `worker_test.exs` | "a re-enqueued export reproduces the same plan from the persisted saves_scope" | D-H2 persistence |
| 18 | `worker_test.exs` | "a missing-bytes revision raises exactly one attention item and the export still verifies" | D-H7 rules 3–4 |
| 19 | `round_trip_test.exs` | "the exported sidecar carries every field needed to reconstruct the revision DAG" | D-H6 forward-compat guard |
| 20 | `readiness`/preflight test | "the export free-space preflight counts revision bytes and the drop-in copy" | D-H8 |

Note tests 4, 12, 16, 18 are the ones that would actually catch a regression that
loses a user's progress. If the plan is cut for scope, cut from the other end.

---

## 6. Adversarial pass on my own recommendation

**"Your drop-in copy is a footgun."** The user copies `Pokemon Emerald (USA).sav` to
their Steam Deck, plays for a week, and now has a third divergent branch that
Playstead knows nothing about. — **Conceded, and unfixable in Phase 4.** Any export
that is useful for J1 has this property; it is the price of no lock-in. Mitigation:
`README.txt` says in one sentence that a save you play elsewhere will not come back on
its own. Recorded as R1. Refusing to write the file would not prevent the outcome — it
would just make the user rename `000012-a-1122aabb.sav` by hand and lose the digest
evidence in the process.

**"Same bytes in two places in one payload manifest is sloppy."** — It is
deliberate and legal: RFC 8493 places no uniqueness constraint on payload content, and
`sha256sum -c` verifies both lines happily. The 32 KB cost is not worth arguing about.

**"You put the human-readable file in `tags/`, one folder away from the saves. The
whole point was Finder-legibility, and you optimised for internal consistency."** —
**This is the strongest hit and I am not fully comfortable with my answer.** The
defence: Phase 2 already established that per-set metadata lives in `tags/`
(`bagit_writer.ex:137`), the payload manifest's purity is a documented promise in the
writer's moduledoc, and a user browsing `saves/` sees `000012-a-1122aabb.sav` — a
name that already conveys order and identity without narrative. `README.txt` at the
top level points to `tags/`. Ludusavi chose the opposite and I would not call it
wrong. **If the owner prefers `data/.../saves/saves.txt`, take option 3a — it is a
one-line change in the writer and it does not disturb anything else.** Recorded as R2,
the one place I would accept being overruled without argument.

**"Your branch letters are meaningless to a human."** — Correct, by choice: `a`/`b`
are stable, device names are not (§2 Syncthing/Dropbox). Meaning lives in `saves.txt`
and the sidecar, two clicks away. The alternative renames a user's past exports when
they rename their laptop, which is worse.

**"Append-only stability has three exceptions, so it is not really a property."** —
Exceptions 2 and 3 are inherited verbatim from Phase 2's shipped title-collision
suffix behaviour. I am not making the export less stable than it is today. Naming the
exceptions is the honest version; the dishonest version is a determinism test that
quietly excludes the cases where it fails.

**"Defaulting to all revisions ships a 400-file folder to a first adopter."** —
Only if area D retains 400 revisions, which is D's decision, not mine. And they are in
`revisions/`, not at eye level. The reverse default — defaulting to current-only —
means a user who exports and then wipes their server has silently lost their history,
which is unrecoverable. Asymmetric downside; default to keeping.

**What a hostile reviewer would say that I have no answer to:** the whole design rests
on area B producing a stable `(slot_id, sequence, branch_key)` triple. If B's lineage
is UUID-and-parent-pointer only, with no monotonic per-slot sequence, D-H3's filename
scheme has no `seq` and I fall back to digest-only names (option 2a) — which is
unsortable and materially worse. **This is a hard dependency, flagged loudly in §7.**

---

## 7. Coherence notes — what I assume about A–G, and where I collide

| Area | What H assumes | Collision severity |
|---|---|---|
| **A** (capture trigger) | Only that a captured revision has stable bytes and a sha256 before it can be exported. The 24 s loss window is invisible to export. | **None.** |
| **B** (lineage/conflict) | **HARD DEPENDENCY.** B must expose, per revision: a **monotonic per-slot `sequence`**, a **stable `branch_key`** (opaque string, inherited down a branch from its fork so it does not flip as the branch grows), `parent_sha256`, `captured_at`, `device{id,name}`, `play_context`. B must also define what "conflicted" means as a slot-level boolean. | **HIGH — flag loudly.** No sequence ⇒ D-H3 collapses to unsortable digest names. No stable branch_key ⇒ branch letters churn and append-only stability breaks. B should confirm both exist before D-H3 is locked. |
| **C** (restore gate) | Nothing. Export does not gate on restore compatibility — it exports bytes and records `format`/`adapter` so a human or a future importer can judge. If C defines a compatibility fingerprint, H adds it to the slot object as an additive field. | **Low.** One additive sidecar field if C wants it. |
| **D** (retention/storage) | (i) Server holds bytes for most revisions via `Playstead.Blobs`; (ii) some may be local-only on a Mac. D-H7 handles (ii). D's retention policy determines how many revisions exist — H exports what exists and takes no position on pruning. | **MEDIUM.** If D guarantees server-side bytes for every record, D-H7's missing-bytes path is dead code that must still exist as a tested invariant. If D prunes aggressively, "all revisions" is cheap; if D keeps everything, D-H2's default gets tested harder. |
| **E** (status ladder) | Nothing — export writes no status into the ladder. The one touchpoint: a missing-bytes attention item (D-H7 rule 3) flows into the existing attention surface, whose ladder position is E/P3 D-13's business, not mine. | **Low.** |
| **F** (launch preflight) | Nothing. F is client-side and zero-network; export is server-side. **One shared string:** the primary member's original basename, used by F's launch materializer for `{romBaseName}.sav` and by D-H3 for the drop-in copy. They must be the same derivation or the export's drop-in file is named differently than the file mGBA actually wrote. | **MEDIUM — worth an explicit shared definition.** |
| **G** (conflict UX) | G's "export either side" (SAVE-04) routes through `Export.create_export/3`. Exporting a conflicted set already produces both branch heads as separate files, so G may need no new export code — only a deep link. If G wants single-revision export, it is `saves_scope: {:revision, id}` on the same worker. | **HIGH — flag loudly.** G must not build a second export writer. I specify the entry point; G owns the flow. |

**Assumption I am making that could be wrong:** that a Phase 4 set has exactly one
save slot (the pinned mGBA GBA adapter declares one battery artifact). D-H3 handles
n>1 by segmentation so the vocabulary does not have to change later, but the n>1 path
will ship untested against a real adapter. Acceptable — the alternative is a
vocabulary that has to be broken when a multi-slot system arrives.

---

## 8. Residual risks

- **R1 — The drop-in copy creates untracked divergence.** A user who plays the
  exported `.sav` elsewhere creates a branch Playstead never sees. Unfixable without
  lock-in; mitigated by one README sentence. *Accepted.*
- **R2 — `saves.txt` in `tags/` may be too far from the saves.** Internal consistency
  won over Finder-proximity. One-line change to option 3a if the owner disagrees.
  *Flagged for the owner, not defended to the death.*
- **R3 — Append-only stability has three named exceptions** (drop-in tracks the head;
  branch letters appear on fork; slot segment appears on a second slot). Two are
  inherited from Phase 2's collision-suffix behaviour. *Documented and tested rather
  than hidden.*
- **R4 — Hard dependency on area B's `sequence` + stable `branch_key`.** If B does not
  produce these, D-H3 must be redesigned. *Highest-priority thing to confirm at
  synthesis.*
- **R5 — The n>1 slot path ships untested against real hardware.** Vocabulary is
  right, code path is speculative. *Accepted.*
- **R6 — Sidecar schema growth is one-way.** Once `"saves"` is populated with this
  shape at schema major 1, the field names are published and additive-only forever
  (D-35). Names chosen with SEED-019's `kind` discriminator and SEED-001's `label`
  reserve precisely because of this. *Accepted, deliberately.*
- **R7 — `bag-info.txt`'s `Bagging-Date` means "byte-identical export" is already
  false in the strict sense** and was before Phase 4. Anyone reading only the
  requirement text may believe a stronger claim than the code delivers. *Mitigated by
  stating P1/P2/P3 explicitly in §4 and asserting the exact carve-out in test 15.*

## Sources

- [RFC 8493 — The BagIt File Packaging Format](https://www.rfc-editor.org/rfc/rfc8493.html) (fetched)
- [Ludusavi — Backup structure](https://github.com/mtkennerly/ludusavi/blob/master/docs/help/backup-structure.md) (fetched)
- [Ludusavi discussion #321 — mapping.yaml and restore paths](https://github.com/mtkennerly/ludusavi/discussions/321) (search result only — unverified)
- [RetroArch #15960 — save/state naming for compressed and command-line launches](https://github.com/libretro/RetroArch/issues/15960)
- [RetroArch #13746 — subsystem Game Boy games use incorrect save file names](https://github.com/libretro/RetroArch/issues/13746)
- borg/restic, git, Google Takeout, Obsidian, Dropbox/Syncthing conflict files: from knowledge, not refetched this session.
