---
phase: "04"
slug: "persistent-save-continuity"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-09-05"
---

# Phase 04 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

Register origin: `register_authored_at_plan_time: true`. Plans 04-01 through 04-13 each carry a
`<threat_model>` block; the 90 threats below are transcribed from those blocks verbatim. Plans
04-14 through 04-20 are gap-closure plans authored without a threat model and contribute no
register entries — see *Coverage Gaps* below.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| probe process → local filesystem | The probe creates, maps, and deletes files; a mis-scoped path would touch real user data | Temporary probe artifacts |
| probe child process → parent | `post_death_writeback` deliberately `SIGKILL`s a child; an unbounded child could outlive the run | Process lifetime |
| report artifact → downstream plans | Later plans and CP7-SAVE-C cite this report as evidence; a fabricated or truncated report would launder an inference as a measurement | Measurement claims |
| emulator → save artifact | Untrusted, opaque bytes written by a process Playstead does not control | Save bytes |
| emulator writes ↔ Playstead reads | A live mmap writer mutates the artifact while capture reads it | Save bytes |
| two launch attempts → one save artifact | Concurrent emulator processes share one 32 KB mmap-backed file | Save bytes |
| concurrent launches → one save artifact | Two launches could otherwise both execute a plan | Save bytes |
| app → user's backup system | `isExcludedFromBackup` decides whether irreplaceable bytes reach Time Machine | Save bytes |
| readiness check → launch path | A false-ready verdict lets the emulator spawn against a save path it cannot write | Readiness verdict |
| app death ↔ durable state | A crash can land between the blob write and the row insert | Save bytes + lineage |
| quota policy → save bytes | The eviction path decides what may be deleted | Save bytes |
| Mac client → device API | Device-authenticated HTTP carrying irreplaceable bytes and client-claimed metadata | Save bytes + metadata |
| device → blob volume | A device-authenticated upload consumes finite server disk | Save bytes |
| save write ↔ game-byte write | Two classes of write share one volume with different reconstructability | Disk capacity |
| device-claimed identifiers → filesystem/database | `assetSetID`, digests, and command ids become path components and primary keys | Untrusted identifiers |
| device-claimed clocks → ordering | `device_captured_at` and UUIDv7 ids embed an untrusted clock | Ordering claims |
| device-claimed clock → displayed time | Device times are evidence, server `recorded_at` is truth | Timestamps |
| device-claimed parent pointer → server lineage | A client asserts what its revision descends from | Lineage claims |
| one user's lines → another user's reads | History and resolution endpoints are user-scoped | Save lineage |
| error code registry → client microcopy | Clients key user-facing save failure copy off the machine code only | Failure codes |
| server-provided revision bytes → local `.sav` | Bytes fetched from the server are written into a path a live emulator will mmap | Save bytes |
| adapter-declared contract → restore decision | The adapter, not Playstead, declares what binds and what is provenance | Compatibility claims |
| launch flow → network | A network call in the Play flow would break the offline promise SAVE-03 names | Network egress |
| database content → filesystem paths | Revision digests, branch keys, and member basenames become file and folder names | Untrusted identifiers |
| console export request → filesystem | An export writes a tree derived from database content | Save bytes + paths |
| exported bag → external verification | Users are told to run `sha256sum -c` against the exported manifest | Digest manifest |
| export job re-enqueue → plan reconstruction | An Oban retry must not silently produce a different export | Export plan |
| stored save state → user-facing claim | A label is a promise about where irreplaceable bytes are | Durability claims |
| two runtimes → one vocabulary | SwiftUI and HEEx can drift apart silently | User-facing copy |
| device names and titles → row identity | Untrusted display strings could be used to group rows | Display strings |
| authenticated console user → save mutations | Choosing and acknowledging mutate durable lineage | Save lineage |
| user decision → durable lineage | Choosing mutates what a device will continue from | Save lineage |
| saves context ↔ attention context | Two bounded contexts share an inbox surface | Context boundary |
| local mutation ↔ outbox entry | A crash between them could lose the decision | User decisions |
| divergence detection → eager fetch | Both sides' bytes are downloaded before the user asks | Network + save bytes |
| destructive user intent → irreplaceable bytes | Five entry points can remove the only copy of progress | Save bytes |
| lane failure classification → escalation decision | A misclassification either cries wolf or stays silent when it should not | Failure signals |
| automated evidence → phase verification claim | A green suite could be read as proving more than it proves | Verification claims |
| CI gate → correctness claim | A gate whose command is missing could exit clean | Gate exit codes |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status | Evidence |
|-----------|----------|-----------|----------|-------------|------------|--------|----------|
| T-04-01-01 | Tampering | `save-p1-probe.swift` filesystem scope | medium | mitigate | Probe operates only inside a `NSTemporaryDirectory()` subdirectory it creates and removes; the optional `--mgba-artifact` path is opened read-only; acceptance criterion asserts the Playstead Application Support root is untouched | closed | audited |
| T-04-01-02 | Denial of Service | `post_death_writeback` child process | low | mitigate | Child is spawned by the probe, killed by the parent, and the parent's post-death poll is bounded at 10 s; every event wait is bounded at 2000 ms per round | closed | audited |
| T-04-01-03 | Repudiation | `04-SAVE-P1-REPORT.json` completeness | medium | mitigate | `test_save_p1_probe.py` asserts every required key and includes a negative case per key, so a truncated report fails the gate rather than passing quietly | closed | audited |
| T-04-01-04 | Information Disclosure | report `environment` block | low | accept | The report records OS version, hardware model, filesystem type, and page size — host facts with no ROM names, paths, digests of user content, or credentials, consistent with QUAL-03's default-redaction posture | closed | audited |
| T-04-01-SC | Tampering | npm/pip/cargo installs | high | mitigate | No package-manager install occurs in this plan: the probe is a single-file Swift script and the validator is stdlib `unittest`; RESEARCH.md's Package Legitimacy Audit records that this phase installs no external packages | closed | audited |
| T-04-02-01 | Denial of Service | `AppPaths` backup exclusion scope | high | mitigate | Exclusion is applied only to `objects`, `partials`, `launch`, `emulators`, `bios`; `clearStaleRootBackupExclusion` repairs existing installs at launch; tests assert the root, `saves/`, and `playstead.sqlite3` are not excluded | closed | audited |
| T-04-02-02 | Tampering | concurrent emulator writes to one `.sav` | high | mitigate | `AdapterLaunchMutex` keyed by `assetSetID`, held across prepare → spawn → exit, released on termination regardless of `AdapterExit` case; `tryAcquire` returns false rather than spawning a second process | closed | audited |
| T-04-02-03 | Denial of Service | stranded launch mutex key | medium | mitigate | `defer`-based release on every path between acquisition and spawn; release is idempotent; a behaviour test covers the throw-before-spawn path | closed | audited |
| T-04-02-04 | Tampering | readiness probe residue in the save directory | medium | mitigate | The atomic-placement probe uses a uniquely-named temporary path and removes all residue on every outcome; an acceptance behaviour asserts the directory's contents are unchanged after evaluation | closed | audited |
| T-04-02-05 | Spoofing | remedy identifier drift | low | accept | `RemedyAction.repairSaveDirectory` keeps its identifier by decision (D-42); only the visible label changes, and a source assertion pins both | closed | audited |
| T-04-02-SC | Tampering | npm/pip/cargo installs | high | mitigate | No package-manager install occurs in this plan; RESEARCH.md's Package Legitimacy Audit records that this phase installs no external packages on either tier | closed | audited |
| T-04-03-01 | Denial of Service | `open_write/2` `reserve: :critical` | high | mitigate | The reserve bypasses only the `required_bytes/2` margin; a 64 MiB physical hard floor still refuses the write, and a behaviour test proves refusal below the floor | closed | audited |
| T-04-03-02 | Denial of Service | unbounded save uploads exhausting the volume | high | mitigate | 8 MiB per-artifact cap enforced during streaming (`save_revision_too_large`, 413), 120 revisions/hour/device via the shipped `RateLimiter`, and `save:`-namespaced `UploadSlots` concurrency accounting | closed | audited |
| T-04-03-03 | Denial of Service | save uploads starving game downloads of the general margin | medium | accept | Accepted by decision: save bytes are reconstructable from nowhere (D-25) while game bytes are reconstructable from the user's own media; the 64 MiB floor bounds the exposure | closed | audited |
| T-04-03-04 | Information Disclosure | problem+json bodies | low | mitigate | Codes are the contract and titles are generic English; no ROM names, paths, digests, or save bytes appear in any of the six registered titles, consistent with QUAL-03 | closed | audited |
| T-04-03-05 | Repudiation | unregistered failure codes falling through to 500 | medium | mitigate | Tests assert registry membership for all six codes, so a missing registration fails the gate instead of silently degrading to `internal_error` | closed | audited |
| T-04-03-SC | Tampering | npm/pip/cargo installs | high | mitigate | No package-manager install occurs in this plan; RESEARCH.md's Package Legitimacy Audit records that this phase installs no external packages | closed | audited |
| T-04-04-01 | Tampering | path components derived from `assetSetID`/digest | high | mitigate | Reuse the shipped `PathSafety.validatedFilename` (Mac) and `Sanitize.component`/`safe_join` (server); no parallel path-building routine is added for saves | closed | self-reported |
| T-04-04-02 | Spoofing | client-claimed ordering via UUIDv7 or `device_captured_at` | high | mitigate | Server-assigned `recorded_at` is the only orderable time; device times are stored as evidence only, and no query orders on the id column | closed | self-reported |
| T-04-04-03 | Elevation of Privilege | cross-user save access | high | mitigate | Every `save_lines`/`save_revisions` row carries `user_id`, every context function takes the scope, and the unique index is user-scoped — the Phoenix 1.8 scoping convention already enforced project-wide (P1 D-01) | closed | self-reported |
| T-04-04-04 | Denial of Service | oversized or unbounded streamed upload | high | mitigate | 8 MiB cap enforced during streaming as `save_revision_too_large` (413), `Content-Length` required, `save:`-namespaced upload slots, and the 120/hour commit limit from plan 04-03 | closed | self-reported |
| T-04-04-05 | Repudiation | duplicate effect from a retried mutation | medium | mitigate | `Idempotency.execute/4` around the metadata commit returns the original receipt; a replay test asserts exactly one revision row | closed | self-reported |
| T-04-04-06 | Tampering | bytes altered in transit or at rest | high | mitigate | `Repr-Digest` declared by the client, verified during streaming by the CAS, and the stored blob is content-addressed by its own sha256; a mismatch returns `save_revision_digest_mismatch` | closed | self-reported |
| T-04-04-07 | Denial of Service | orphan pending blobs from abandoned uploads | medium | mitigate | Pending upload blobs are TTL'd and swept; an orphan is collectable by construction because bytes are written before references (D-06) | closed | self-reported |
| T-04-04-08 | Information Disclosure | save bytes or ROM names in logs/errors | medium | mitigate | Problem responses carry registered codes and generic titles only; no save bytes, digests of user content, or paths are logged by default, per QUAL-03 | closed | self-reported |
| T-04-04-SC | Tampering | npm/pip/cargo installs | high | mitigate | No package-manager install occurs in this plan; RESEARCH.md's Package Legitimacy Audit records that this phase installs no external packages on either tier | closed | self-reported |
| T-04-05-01 | Repudiation | silent data loss via non-fast-forward rejection | high | mitigate | Accept-and-branch: a rejected commit would leave the losing side's only durable copy on a client, inverting the project's first priority; the only 409 is `save_parent_unknown`, which is retried, not surfaced | closed | self-reported |
| T-04-05-02 | Tampering | mutation of a committed revision | high | mitigate | `save_revision_immutable` (409) on any modification attempt; resolution appends a new revision and never rewrites a head | closed | self-reported |
| T-04-05-03 | Elevation of Privilege | cross-user save line access | high | mitigate | Every query is `user_id`-scoped; an out-of-scope line returns 404 rather than 403, so existence is not confirmed | closed | self-reported |
| T-04-05-04 | Denial of Service | unbounded branch fan-out on one line | medium | mitigate | `save_branch_limit_exceeded` at 32 heads, raised loudly rather than silently dropping a commit | closed | self-reported |
| T-04-05-05 | Denial of Service | unbounded per-user revision growth | medium | accept | Accepted by decision (D-28, keep everything forever): 100,000-revision and 20 GiB backstops surface as attention and never prune; pathological cost is roughly 1.6 GB/year | closed | self-reported |
| T-04-05-06 | Spoofing | client clock used to order or win | high | mitigate | Ordering is by server `recorded_at` only; `device_clock_offset_ms` separates clock error from queue delay and drives a displayed caveat, never a decision | closed | self-reported |
| T-04-05-07 | Repudiation | concurrent resolution racing to a lost decision | medium | mitigate | Resolution is an append with no compare-and-swap; a test commits both arrival orders and asserts identical retained sets | closed | self-reported |
| T-04-05-SC | Tampering | npm/pip/cargo installs | high | mitigate | No package-manager install occurs in this plan; RESEARCH.md's Package Legitimacy Audit records that this phase installs no external packages | closed | self-reported |
| T-04-06-01 | Tampering | torn read of a live mmap artifact | high | mitigate | Raw SRAM is not self-describing, so temporal quiescence is the only available detector: three consecutive identical 1 Hz reads before any capture, and the bytes are never parsed | closed | self-reported |
| T-04-06-02 | Denial of Service | save loss on disk-full | high | mitigate | D-31's durable blocked row, one alert, persistent attention, retry every cycle, and a direct-upload escape hatch; nothing is deleted and the game keeps running | closed | self-reported |
| T-04-06-03 | Repudiation | lost promotion when the app dies after emulator exit | high | mitigate | `SaveSessionRecovery` replays the identical settle pass at launch, idempotent by digest, single-winner promotion | closed | self-reported |
| T-04-06-04 | Denial of Service | eviction reclaiming irreplaceable save bytes | high | mitigate | Save revisions are unconditionally excluded from eviction candidate selection, asserted by test at maximum quota pressure | closed | self-reported |
| T-04-06-05 | Tampering | out-of-band edits to the artifact absorbed silently | medium | mitigate | A session-start baseline revision marked `origin: external` records the out-of-band change as its own node rather than folding it into the session's promotion | closed | self-reported |
| T-04-06-06 | Information Disclosure | blocked-capture alert content | low | mitigate | The blocked row records the line, session, digest, and reason internally; the user-facing alert carries no path, ROM name, or digest, per QUAL-03 | closed | self-reported |
| T-04-06-SC | Tampering | npm/pip/cargo installs | high | mitigate | No package-manager install occurs in this plan; RESEARCH.md's Package Legitimacy Audit records that this phase installs no external packages | closed | self-reported |
| T-04-07-01 | Tampering | mismatched artifact written to a live medium | critical | mitigate | D-20's hard block on `medium_id`/`artifact_bytes` mismatch with no override affordance: writing a mismatched artifact is the documented path to the game itself declaring the save corrupt and offering to erase it | closed | self-reported |
| T-04-07-02 | Tampering | torn in-place `.sav` write | high | mitigate | Stage → `fsync` → `rename` → `fsync` directory; the target is never opened for writing in place, and a source assertion pins both `fsync` calls | closed | self-reported |
| T-04-07-03 | Repudiation | silent loss of uncaptured on-disk progress | high | mitigate | Restore captures the current on-disk artifact as a revision first, and a failed capture aborts the restore | closed | self-reported |
| T-04-07-04 | Tampering | corrupted or substituted revision bytes | high | mitigate | Always full re-hash at restore, never the size/inode/mtime shortcut; a mismatch quarantines rather than deletes, with no override while offline | closed | self-reported |
| T-04-07-05 | Tampering | concurrent plan execution against one artifact | high | mitigate | The executor runs inside the per-`assetSetID` `AdapterLaunchMutex` from plan 04-02 | closed | self-reported |
| T-04-07-06 | Information Disclosure | network activity during offline play | medium | mitigate | Zero recorded HTTP requests across the whole Play flow, asserted by a recording transport that includes fire-and-forget tasks | closed | self-reported |
| T-04-07-07 | Elevation of Privilege | path traversal via `assetSetID` in the save path | high | mitigate | The save path is resolved through the shipped `saveDirectoryURL(forAssetSetID:)` and `PathSafety.validatedFilename`; no new path-building routine is added | closed | self-reported |
| T-04-07-08 | Repudiation | auto-picking a branch at launch | high | mitigate | A diverged slot always yields `.keep`; the planner writes nothing and the non-local head is never written | closed | self-reported |
| T-04-07-SC | Tampering | npm/pip/cargo installs | high | mitigate | No package-manager install occurs in this plan; RESEARCH.md's Package Legitimacy Audit records that this phase installs no external packages | closed | self-reported |
| T-04-08-01 | Tampering | path traversal or collision via member/branch names in export paths | high | mitigate | All names route through the shipped `Sanitize.component/1` and `reserved_saves_name?/1`; no new path-building or sanitizing code is written | closed | self-reported |
| T-04-08-02 | Repudiation | a diverged history exported as one file | high | mitigate | `branches` is always present in the sidecar even when linear, and a diverged slot gets no drop-in copy — the export tool never picks a side | closed | self-reported |
| T-04-08-03 | Tampering | an incomplete bag that fails the user's own verification | high | mitigate | Missing revision bytes are named in the sidecar and deliberately kept out of `fetch.txt`, so `sha256sum -c` still succeeds; a test asserts it | closed | self-reported |
| T-04-08-04 | Repudiation | a re-run export silently differing from the first | medium | mitigate | `saves_scope` is persisted on `ExportRecord` and read by the worker; determinism is asserted as plan purity plus write reproducibility plus append-only stability, with the three exceptions enumerated | closed | self-reported |
| T-04-08-05 | Information Disclosure | export filenames leaking device identity | medium | mitigate | Branch letters derive from a stable fork-inherited `branch_key`, never a device name, so a rename cannot rewrite a past export and no device name reaches the filesystem | closed | self-reported |
| T-04-08-06 | Denial of Service | export of a very large revision history | low | accept | Accepted: revision artifacts are bounded at 8 MiB by plan 04-03 and the per-user backstops from plan 04-05 surface pressure before an export becomes pathological | closed | self-reported |
| T-04-08-SC | Tampering | npm/pip/cargo installs | high | mitigate | No package-manager install occurs in this plan; RESEARCH.md's Package Legitimacy Audit records that this phase installs no external packages | closed | self-reported |
| T-04-09-01 | Spoofing | a label claiming durability the bytes do not have | high | mitigate | "Backed up" is banned from every save surface and the destination is always "your server"; the rollup reads the newest revision's durability from the committed local store, never an in-flight state | closed | audited |
| T-04-09-02 | Repudiation | copy drift between the Mac and the console | medium | mitigate | One shared vocabulary artifact read as a test resource on both sides, with exhaustiveness asserted in both directions so an unlisted string fails | closed | audited |
| T-04-09-03 | Tampering | row grouping driven by attacker-influencable display names | medium | mitigate | Rows are keyed by stored revision identity and digest, never by device-name or title string comparison | closed | audited |
| T-04-09-04 | Information Disclosure | digests, paths, or internal nouns leaking into player copy | medium | mitigate | The banned-word scan over vocabulary values covers sha256, digest, hash, journal, blob, CAS, and the rest; those remain available only behind the per-row "Details" disclosure for support | closed | audited |
| T-04-09-05 | Denial of Service | hashing during render on a large history | low | mitigate | Durability is read from SQLite and never hashed at render; the timeline is session-grouped rather than flat | closed | audited |
| T-04-09-06 | Elevation of Privilege | the Save row blocking launch | medium | mitigate | The Save row cannot produce `.blocked` and does not contribute to the blocker count, asserted by test for every input including two divergent heads | closed | audited |
| T-04-09-SC | Tampering | npm/pip/cargo installs | high | mitigate | No package-manager install occurs in this plan; RESEARCH.md's Package Legitimacy Audit records that this phase installs no external packages | closed | audited |
| T-04-10-01 | Elevation of Privilege | cross-user access to save lines or attention items | high | mitigate | Every query is `user_id`-scoped under the `:require_authenticated_user` live session, matching the shipped console convention; out-of-scope reads return not-found | closed | self-reported |
| T-04-10-02 | Tampering | a console action silently discarding a version | high | mitigate | Choosing and keeping-both call the append-only context functions from plan 04-05; nothing is deleted, and the non-chosen side stays on screen with a live switch-back control | closed | self-reported |
| T-04-10-03 | Repudiation | context-boundary erosion via a widened reason enum | medium | mitigate | `Playstead.Attention.Reason` is left frozen and its member list is pinned by a test; the saves source owns its own table and vocabulary | closed | self-reported |
| T-04-10-04 | Spoofing | a console-rendered current-version claim the Macs do not honour | medium | mitigate | The console never renders a global playhead and uses the console-only result strings, which say what will happen at the next sync rather than what is being played | closed | self-reported |
| T-04-10-05 | Information Disclosure | digests and internal nouns in console copy | low | mitigate | The digest is behind the "Details" disclosure only; the copy-contract test from plan 04-09 scans console strings for banned words | closed | self-reported |
| T-04-10-06 | Denial of Service | unbounded export enqueued from the console | low | accept | Accepted: exports already run through the shipped Oban worker with its existing concurrency limits, and the saves scope narrows rather than widens the work | closed | self-reported |
| T-04-10-SC | Tampering | npm/pip/cargo installs | high | mitigate | No package-manager install occurs in this plan; RESEARCH.md's Package Legitimacy Audit records that this phase installs no external packages | closed | self-reported |
| T-04-11-01 | Repudiation | a decision lost between the local write and the send | high | mitigate | The local mutation and the durable outbox row are written in one transaction, mirroring the shipped `Outbox.enqueue` discipline; a crash test covers the window | closed | self-reported |
| T-04-11-02 | Tampering | a resolution silently discarding the other version | critical | mitigate | Resolution appends and never deletes or moves a head; both original heads are asserted present after every resolution, and the non-chosen side stays on screen with a live switch-back control | closed | self-reported |
| T-04-11-03 | Repudiation | duplicate resolutions from retries or double taps | medium | mitigate | The outbox entry is idempotent; a test asserts a second resolution of the same fork enqueues nothing new | closed | self-reported |
| T-04-11-04 | Spoofing | a ranked or pre-selected side standing in for the user's judgement | high | mitigate | No recommendation, highlight, pre-selection, or colour distinction exists; their absence is asserted by source scan and by rendering test | closed | self-reported |
| T-04-11-05 | Information Disclosure | eager fetch of both sides on a metered connection | low | accept | Accepted: the artifacts are 32 KB, and fetching them at detection is what makes the whole flow work offline | closed | self-reported |
| T-04-11-06 | Denial of Service | divergence interrupting play | medium | mitigate | Divergence is never a modal, notification, or launch prompt; the rank-1 rung surfaces it without interrupting, and playing a diverged slot is never blocked | closed | self-reported |
| T-04-11-07 | Information Disclosure | internal nouns in divergence copy | medium | mitigate | The copy-contract test from plan 04-09 scans divergence strings for the banned words, including "conflict", which survives only as an internal state name | closed | self-reported |
| T-04-11-SC | Tampering | npm/pip/cargo installs | high | mitigate | No package-manager install occurs in this plan; RESEARCH.md's Package Legitimacy Audit records that this phase installs no external packages | closed | self-reported |
| T-04-12-01 | Denial of Service | user destroys the only copy of their progress | critical | mitigate | An interruptive modal at each of the five destructive-intent points whenever the only-on-this-Mac count is greater than zero, with the export escape hatch as the default button and the destructive path never default | closed | self-reported |
| T-04-12-02 | Repudiation | an unfixable upload failure staying silent | high | mitigate | The escalated tier fires on revoked auth, capability skew, server refusal, and compatibility rejection — the four cases the system cannot resolve on its own | closed | self-reported |
| T-04-12-03 | Denial of Service | alarm fatigue from escalating normal offline operation | medium | mitigate | Escalation is never triggered by duration or count; the four non-escalating cases are asserted by name and a source scan proves no duration threshold exists | closed | self-reported |
| T-04-12-04 | Tampering | the modal's count evaluated against optimistic in-flight state | medium | mitigate | The count is computed from committed local state; a backstop truth records the requirement and a test drives the in-flight case | closed | self-reported |
| T-04-12-05 | Information Disclosure | reason strings leaking internal detail | low | mitigate | The reason substituted into the panel body comes from the lane's user-facing classification, and the vocabulary's banned-word scan from plan 04-09 covers both surfaces | closed | self-reported |
| T-04-12-SC | Tampering | npm/pip/cargo installs | high | mitigate | No package-manager install occurs in this plan; RESEARCH.md's Package Legitimacy Audit records that this phase installs no external packages | closed | self-reported |
| T-04-13-01 | Repudiation | an automated pass claiming the continuation proof | high | mitigate | The automated proxy and CP7-SAVE-C are two distinct recorded verification items; the UAT document states explicitly that a green suite is not a passed continuation proof, and the checkpoint is a blocking human gate | closed | audited |
| T-04-13-02 | Repudiation | a required test silently absent or skipped | high | mitigate | Both new tests are registered in the CI required-tests manifest, which the shipped evidence validator enforces as named, discovered, and non-skipped; a negative check proves removal fails the gate | closed | audited |
| T-04-13-03 | Repudiation | a gate passing because its command is missing | high | mitigate | Gate commands exit non-zero when unresolvable; the acceptance criteria include a negative check rather than only a positive run | closed | audited |
| T-04-13-04 | Information Disclosure | UAT evidence containing ROM names or paths | medium | mitigate | The recorded observations name the title and adapter version, which the developer chooses to record; no paths, digests of user content, or save bytes are captured, consistent with the shipped UAT evidence boundaries | closed | audited |
| T-04-13-SC | Tampering | npm/pip/cargo installs | high | mitigate | No package-manager install occurs in this plan; RESEARCH.md's Package Legitimacy Audit records that this phase installs no external packages | closed | audited |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above `workflow.security_block_on` (high) count toward `threats_open`*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*
*Evidence: `audited` — verified against shipped source by `gsd-security-auditor` on 2026-09-05 (see Verification Evidence below). `self-reported` — closure recorded per-threat in that plan's own `## Threat Flags` SUMMARY section by the executing agent, not independently re-verified in this run.*

---

## Verification Evidence

The 29 threats from plans 04-01, 04-02, 04-03, 04-09 and 04-13 were opened by this audit —
those five SUMMARYs carry no `## Threat Flags` section, so no disposition had ever been recorded
for them. `gsd-security-auditor` verified each against shipped source at ASVS L1.

| Threat ID | Evidence |
|-----------|----------|
| T-04-01-01 | `playstead-mac/scripts/probes/save-p1-probe.swift:653-667` (`NSTemporaryDirectory()` + UUID subdir, `cleanupProbeDir()` at `:737`); `:490` `open(artifactPath, O_RDONLY)`; no Application Support write path in the file |
| T-04-01-02 | `save-p1-probe.swift:24-25` (`eventWaitMillisecondsPerRound = 2000`, `postDeathPollSeconds = 10.0`), `:409` `kill(pid, SIGKILL)` + `waitUntilExit()`, `:414-427` bounded poll |
| T-04-01-03 | `playstead-mac/scripts/ci/tests/test_save_p1_probe.py:62-107` `validate_report`, `:132` `delete_key`, one `test_rejects_missing_*` per required key (30 tests) |
| T-04-01-04 | `04-SAVE-P1-REPORT.json` `environment` holds exactly `artifact_bytes, filesystem_type, hardware_model, os_version, page_size` — no ROM names, paths, user-content digests, or credentials. Accepted: risk R-04-01. |
| T-04-01-SC | `git show --stat 53c47c4 caa7599` — `.swift`, `.sh`, `.py`, `.json`, `.md` only; no dependency manifest or lockfile |
| T-04-02-01 | `AppPaths.swift:64-70` excludes only `objects, partials, launch, emulators, bios`; `:81-90` `clearStaleRootBackupExclusion` (idempotent, runs first at `:44`); `AppPathsBackupExclusionTests.swift:41-55,60-88` assert root, `saves/` and `playstead.sqlite3` are not excluded |
| T-04-02-02 | `AdapterHost.swift:101-126` `AdapterLaunchMutex`; `:395-406` acquire + `defer`; `:420-421` release before `AdapterExit.classify` so it fires for every exit case; `LaunchMutexTests.swift:88,153` |
| T-04-02-03 | `AdapterHost.swift:403-406` `releaseOnReturn` + `defer`, `:431` cleared only after `proc.run()` succeeds; `release` idempotent; `LaunchMutexTests.swift:42,59` |
| T-04-02-04 | `ReadinessEngine.swift:309-318` UUID-named probe + `defer { removeItem(probeURL); removeItem(targetURL) }`; `SaveDirectoryAtomicPlacementTests.swift:98` `testEvaluationLeavesNoResidue` |
| T-04-02-05 | `Remedy.swift:15` `case repairSaveDirectory` identifier intact, pinned by `SaveDirectoryAtomicPlacementTests.swift:91` and `ReadinessEngineTests.swift:197`; only the label moved to `SaveVocabulary.blockerSaveDirectoryRemedy` (`ReadinessEngine.swift:291`). Accepted: risk R-04-02. |
| T-04-02-SC | `git show --stat 3e39dd7 7df9360 e91ad42` — Swift sources/tests only |
| T-04-03-01 | `readiness.ex:395` `@critical_free_floor_bytes 67_108_864`, `:414-418` `fits_critical_free_space?/2`; `local_disk.ex:51,82` routes `reserve: :critical` to the floor check only; `readiness_critical_reserve_test.exs:64,87` (succeeds above floor, refused below), `:48` pins `required_bytes/2` unchanged |
| T-04-03-02 | `blobs.ex:198-236` (8 MiB cap, 120/hr, `"save:"` slot + rate keys); enforced at `saves_controller.ex:48-50`, `:122-133` `RateLimiter.hit`, `router.ex:79`. The cap applies to `declared_length`, which `plugs/repr_digest.ex:45,67` makes mandatory (411 when absent) — the chunked/no-length bypass is closed at the plug |
| T-04-03-03 | The 64 MiB floor that bounds the exposure exists and is enforced (`readiness.ex:395,414-418`; `readiness_critical_reserve_test.exs:87`). Accepted: risk R-04-03. |
| T-04-03-04 | `error_codes.ex:40-45` — six titles are generic English nouns; no path, digest, or byte content |
| T-04-03-05 | `test/playstead_web/error_codes_test.exs:15-46` — per-code status assertion plus registry-membership over all six codes |
| T-04-03-SC | `git show --stat 3d62b95 bbd1e82 3c36f1a` — `.ex`/`.exs` only; `mix.exs`/`mix.lock` untouched |
| T-04-09-01 | `SaveCopyContractTests.swift:16-22` bans `"backed up"` (whole-word), `:127-131` scans every vocabulary value, `:146` proves the scan catches a real violation; `shared/save-vocabulary.json` has 17 `"your server"` and 0 `backed up`; `SaveRollup.swift:9,31-45` reads only `newestDurability`, a committed-store fact |
| T-04-09-02 | `SaveCopyContractTests.swift:49,81,88,95,110` (JSON↔Swift exact dictionary equality, drift both directions); `playstead-server/test/playstead/save_copy_contract_test.exs:25,51,58,75` |
| T-04-09-03 | `SaveHistorySheet.swift:9,37` (`id: String` on row and session), `:89,139` `ForEach(..., id: \.element.id)`; no device-name/title comparison in the file (`deviceName` at `:134` is display-only) |
| T-04-09-04 | `SaveCopyContractTests.swift:16-22` banned list (`sha256, digest, hash, cursor, journal, parent, base, head, ancestor, revision, blob, CAS, idempotency key, LWW`) asserted over all 99 values at `:127-131`; mirrored at `save_copy_contract_test.exs:94` |
| T-04-09-05 | Verified absence: no `SHA256`/`sha256`/`Insecure`/`hashValue` in `SaveHistorySheet.swift`, `SaveRollup.swift`, `SaveStateModel.swift`, `StatusSlotView.swift`; `SaveHistorySheet.swift:89` renders session-grouped, not flat |
| T-04-09-06 | `ReadinessEngine.swift:340-367` — every `.saveState` return is `.ready` or `.warning`, never `.blocked`; `:384` `case .blocked: return 0`; `SaveStateModelTests.swift:179,193` |
| T-04-09-SC | `git show --stat db28574 580ed66 b0b412c 9f561e9` — `.swift`, `.ex`, `.json`, `.png`, `.xctestplan` only (`shared/save-vocabulary.json` is a copy table, not a package manifest) |
| T-04-13-01 | `04-UAT.md:52-58` CP7-SAVE-C recorded separately, `result: blocked`, `blocked_by: human-action`, gate `blocking-human`, with an explicit "a green result on test 1 is not evidence" clause; `:41-49` evidence-boundary paragraph; `:63-72` Explicit Separation Statement; `04-VALIDATION.md:79-81,99` two distinct rows |
| T-04-13-02 | `run-mac-verification.sh:1280,1294` both tests in the required-tests manifest; enforcement at `:484-496` (`discovered`, `execution_count == 1`, `skipped is False`, `outcome == "passed"`, empty allowlist rejected) and `:789-796`; registrations at `LiveServer.xctestplan:52`, `UI.xctestplan:31`; negatives at `scripts/ci/tests/four-layer-verifier-test.sh:235,269,273` |
| T-04-13-03 | `four-layer-verifier-test.sh:274,275,265` (malformed / no-allowlist / duplicate execution all fail); `run-mac-verification.sh:590` `die` when a layer has no `--required-test`; `:283-284` skipped-canary rejection. 04-13 added no new gate mechanism — `git show --stat cd0acfe` is a 6-line registration into the existing fail-closed gate |
| T-04-13-04 | `04-UAT.md` contains no ROM filename, no `/Users/` path, no `.rom`/`.gba` name, and no digest value; `:53` records only "a real commercial GBA title" + the pinned mGBA adapter; backed by `scripts/ci/sanitize-evidence.sh` and `four-layer-verifier-test.sh:261` |
| T-04-13-SC | `git show --stat cd0acfe 3640491` — `.swift`, `.xctestplan`, `.sh`, `.md` only |

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| R-04-01 | T-04-01-04 | The probe report's `environment` block records OS version, hardware model, filesystem type and page size — host facts only, with no ROM names, paths, user-content digests, or credentials. Consistent with QUAL-03's default-redaction posture. Contents confirmed against the shipped `04-SAVE-P1-REPORT.json`. | 04-01-PLAN.md disposition | 2026-09-05 |
| R-04-02 | T-04-02-05 | Remedy identifiers are structural and pinned by test; only the user-facing label moved into `SaveVocabulary`. A drifted label cannot spoof a remedy because the identifier, not the label, drives behaviour. | 04-02-PLAN.md disposition | 2026-09-05 |
| R-04-03 | T-04-03-03 | Save uploads may consume the general margin ahead of game downloads. Bounded by the enforced 64 MiB `:critical` free-space floor; a game download is reconstructable from the server, a save is not, so the priority inversion is the intended trade. | 04-03-PLAN.md disposition | 2026-09-05 |
| R-04-04 | T-04-05-05 | Unbounded per-user revision growth is accepted (D-28); no retention policy ships this phase. Per-user backstops in 04-05 bound the practical rate. | 04-05-PLAN.md disposition | 2026-09-05 |
| R-04-05 | T-04-08-06 | Export of a very large revision history is accepted; bounded by 04-03's 8 MiB per-artifact cap and 04-05's per-user backstops. | 04-08-PLAN.md disposition | 2026-09-05 |
| R-04-06 | T-04-10-06 | An unbounded export enqueued from the console is accepted; export volume is bounded by the existing Oban worker's concurrency limits. | 04-10-PLAN.md disposition | 2026-09-05 |
| R-04-07 | T-04-11-05 | Eager fetch of both sides of a divergence on a metered connection is accepted; per 04-11's SUMMARY the path is not yet triggered in shipped code. Re-evaluate when divergence fetch goes live. | 04-11-PLAN.md disposition | 2026-09-05 |

*Accepted risks do not resurface in future audit runs.*

---

## Coverage Gaps

Recorded so a later audit does not mistake absence of a finding for absence of risk.

| Gap | Detail |
|-----|--------|
| Plans 04-14 … 04-20 carry no threat model | Seven gap-closure plans were authored without a `<threat_model>` block and contribute no register entries. Their SUMMARYs assert no new network endpoint, auth path, or schema change was introduced, but that claim was not independently verified in this run. |
| 61 of 90 threats closed on self-report | Plans 04-04 … 04-08 and 04-10 … 04-12 record per-threat closure in their own `## Threat Flags` sections. This audit carried those forward without re-verifying them in source, per the ASVS L1 scope chosen for this run. Raise `workflow.security_asvs_level` to 2 to force deep re-verification of the whole register. |
| `SaveRollup` has no production call site | `grep -rn "SaveRollup\.\|SaveRollup(" playstead-mac/Playstead` returns nothing — the D-36 rollup is exercised only by tests. T-04-09-01's mitigation is present and correct, and the label cannot over-claim because it is not rendered; this is a reachability gap in the same family as WINDOWS #37, not a threat gap. |
| `SaveHistorySession` is constructed only in tests | Built only in `SaveHistoryContractSnapshotTests.swift`. T-04-09-03's keying discipline is correct in the view, but the real grouping producer is not in the tree yet — re-verify the keying when it lands. |
| Probe cleanup is not `defer`-guaranteed | `cleanupProbeDir()` is invoked once at `save-p1-probe.swift:737`; a `die()` before that point leaves the temp subdirectory behind. Scope-wise T-04-01-01 is closed — nothing outside `NSTemporaryDirectory()` is ever touched — but the cleanup is not exception-safe. |
| T-04-01-01's "Application Support untouched" check is one-time | It is a plan acceptance criterion, not a recurring gate; no shipped test re-asserts it. The source-level scoping is what closes the threat. |
| WINDOWS #52 — `bytesLocal: false` on a crash-recovered capture | Disclosed by plan 04-20: `SaveSessionRecovery.replay` (D-07 crash recovery, reachable in production via `recoverAbandonedSaveSessionsAtLaunch`) records a promoted revision but holds no `CASManager`. Not a register threat — 04-20 has no threat model — but it touches T-04-06-03's subject matter (lost promotion after app death) and should be re-checked against that threat when the fix lands. |

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-09-05 | 90 | 90 | 0 | gsd-security-auditor (29 verified in source) + plan SUMMARY threat flags (61 carried forward) |

## Security Audit 2026-09-05

| Metric | Count |
|--------|-------|
| Threats found | 90 |
| Closed | 90 |
| Open | 0 |

29 threats were opened by this audit because plans 04-01, 04-02, 04-03, 04-09 and 04-13 recorded
no disposition anywhere. The auditor closed 26 in source; the remaining 3 were `accept`-disposition
items whose technical substance was verified but which had no accepted-risks log to live in. This
file is that log, and closes them as R-04-01, R-04-02 and R-04-03.

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-09-05
