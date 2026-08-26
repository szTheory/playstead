# Experience Ethos

**Working expression:** effortless, never mysterious  
**Status:** product constitution to preserve through scoping and implementation

## The Intended Feeling

The product should feel like a beautifully designed game console that happens to respect ordinary files and self-hosting. The happy path is quiet, fast, and integrated. When reality is messy, the product becomes more transparent—not more technical, destructive, or judgmental.

Polish is not decoration. Here, polish means confidence that a game, save, BIOS, controller, or server upgrade will behave predictably and remain recoverable.

## Product Precedence

When tradeoffs are real, choose in this order:

1. Data safety and recoverability
2. Reliable local play and save continuity
3. Clarity, accessibility, and low-administration operation
4. Performance and resource efficiency
5. Integrated delight
6. Feature breadth

This is not an argument against ambitious features. It is a rule that achievements, recommendations, streaming, social layers, and other enrichments earn their place only after they can be isolated from the dependable play path.

## Principles

### 1. Automate the work; expose the truth

Scanning, hashing, matching, deduplication, organization, caching, and save backup should normally happen without intervention. Every automated action must still produce an understandable receipt: what was found, what changed, where the bytes live, how confident the match is, and how to undo or correct it.

### 2. Custody must be tangible

Use ordinary concepts—library, source file, managed copy, downloaded to this Mac, backed up, export—not storage jargon. Never make a user guess whether dropping a file copied it or merely remembered its path. Exact bytes remain exportable in a deterministic folder layout with a readable manifest.

### 3. Quiet by default, detailed on demand

Healthy operation should not create an alert stream. Summarize success softly. Escalate only when the user must decide or data is at risk. Preserve full diagnostics and provenance behind progressive disclosure for power users and support.

### 4. Reversibility earns trust

Imports leave sources untouched. Deletes explain scope. Saves have history. Conflicts preserve both sides. Migrations take backups and validate afterward. Exports are tested. Every risky flow has preview, cancellation where honest, and recovery.

### 5. Exceptions are part of the happy path

Unknown, patched, dirty, duplicated, multi-file, or BIOS-dependent games are normal. Route them to a calm “Needs attention” inbox with plain-language reasons and safe next actions. Do not label unfamiliar bytes as bad, illegal, or disposable.

### 6. Readiness before failure

Before Play, show a compact readiness model covering local availability, required assets, emulator adapter, BIOS, controller, and save-sync state. Prevent predictable failures and translate unavoidable emulator errors into actionable language.

### 7. Local responsiveness, cloud continuity

Previously downloaded games and library views should remain useful without the network. Background synchronization must never block local browsing or obscure whether a save has reached the server. This follows local-first ideals: multi-device convenience without surrendering user ownership or offline agency. [Ink & Switch](https://www.inkandswitch.com/essay/local-first/)

For large disc-based games, “available” must be exact: server-only, queued, partially downloaded, verified locally, pinned offline, or safe to evict. Once verified locally, launching must not call a storefront, metadata provider, achievement service, or server on the critical path.

### 8. Controller-first, never controller-only

Every player-facing flow must work well with a controller, including pairing recovery and visible focus. Keyboard, pointer, and assistive technology remain equivalent paths so a failed controller never traps the user. Apple likewise recommends supporting familiar platform interactions alongside physical game controllers. [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/game-controls)

### 9. Motion must explain or delight with restraint

Use animation for spatial continuity, cause-and-effect, focus, progress, and small moments of earned delight. Avoid ambient bounce, gratuitous staging, and motion that delays input. Always honor reduced-motion preferences. Emil Kowalski's useful test is to ask what purpose an animation serves before adding it. [You Don't Need Animations](https://emilkowal.ski/ui/you-dont-need-animations), [Great Animations](https://emilkowal.ski/ui/great-animations)

### 10. Honest confidence beats false certainty

Metadata matches have sources and confidence. BIOS readiness is scoped to a system/core. Controller compatibility is scoped to platform and driver. Save portability is scoped to adapter and version. Microcopy must say what is known, what is inferred, and what the user can do next.

### 11. Novice clarity, expert leverage

Provide one opinionated happy path. Reveal advanced storage, adapter, metadata, export, and diagnostics controls progressively. Experts can inspect and override; novices never need to learn the internal architecture to play a game.

### 12. No lock-in, dark patterns, or acquisition theater

The project organizes user-supplied content. It does not distribute or help acquire copyrighted ROMs or proprietary BIOS files. It never makes exit intentionally painful, claims hashes prove ownership, or turns a private library into a public catalogue by accident.

### 13. Enrichment is subordinate to play

Achievements can be delightful and may later arrive through an optional provider adapter. They cannot redefine canonical identity, require manual cross-provider reconciliation, or create a failure mode for browsing, launching, offline use, saves, or export. The same isolation rule applies to artwork, recommendations, social features, and remote services.

### 14. Upgrades must not move the floor

Known-playable configurations need compatibility records and rollback. Update metadata, cores, adapters, and server components atomically where possible; preflight migrations; retain the previous working state; and surface incompatibility before changing it. “Everything updated” is not success if the user can no longer play.

### 15. A library is not an inventory dump

The complete repository can be large without dominating the experience. Lead with favorites, collections, continue playing, recent additions, queue, and the systems this user cares about. Make global search and exhaustive filters excellent, but do not force every title and platform into every view. Curation is user-directed before it is algorithmic.

### 16. Repository, cache, and backup are different promises

The server is the canonical personal repository. A client cache is selective and safely reconstructable. A backup is an independent verified copy capable of restoring the repository after loss. Use these words and states consistently; never show a reassuring green “safe” state merely because one disk currently contains the bytes.

### 17. New-computer setup is a product ritual

Pairing a new machine should establish identity, show the catalogue, find available controllers and adapters, offer a small set of recommended downloads, and restore progress without requiring an external drive or complete mirror. A large collection becomes progressively available while the interface remains responsive and useful.

## Interaction Contracts

### Import

- Primary action: **Copy into my library**
- Supporting explanation: “Your original file stays where it is. A verified copy will be stored by your server and available to your devices.”
- Result receipt: exact duplicate / new managed copy / recognized variant / needs attention / failed safely
- Advanced reference-in-place behavior is deferred until its failure and portability semantics can be made equally clear.
- A single file feels immediate. A massive folder becomes a staged background job with estimated work, pause/resume, safe retries, and an import receipt; both paths use the same custody rules.

### Sync

- States: only on this device / queued / uploading / backed up / downloading / offline / conflict / action required
- Show the last successful revision, device, and time without requiring filename archaeology.
- Never say “Synced” when a write is merely queued or when competing heads exist.
- Keep catalogue metadata, game-byte availability, persistent saves, and backups as separate visible states rather than collapsing them into one ambiguous sync icon.

### Collections and Local Availability

- Primary views: Continue, Favorites, Collections, Queue, Recent, and chosen Systems
- Per-game availability: On server / downloading / ready on this device / pinned offline
- Collection actions: download here, pin offline, remove local copy, export, and verify
- Storage view: explain reclaimable cache separately from irreplaceable repository data

### Ready to Play

- Game files: complete or missing named components
- Local cache: available, downloading, or server-only
- Emulator: supported adapter and version
- BIOS: not needed, valid, optional replacement, or user file required
- Controller: detected/tested with keyboard fallback
- Save: current, pending backup, older remote revision, or conflict

### Errors and Recovery

Follow durable usability heuristics: keep system status visible, preserve user control, prevent errors where possible, and explain recovery in the user's language. [Nielsen Norman Group heuristics](https://www.nngroup.com/articles/ten-usability-heuristics/)

An error message should answer:

1. What could not be completed?
2. Is the user's data safe?
3. What likely caused it?
4. What is the recommended next action?
5. Where can an expert inspect details?

## Design Influences

- **Console and industrial design:** strong defaults, limited visible machinery, tactile feedback, coherent physical/digital states.
- **Local-first software:** offline usefulness, long-term preservation, privacy, cross-device continuity, and ultimate user control.
- **Backup and synchronization systems:** immutable history, device identity, explicit conflict artifacts, restore drills, and truthful state.
- **DJ/music library management:** rapid filtering, recent/favorite/queued collections, duplicate and variant handling, recognizable progress, and contextual discovery.
- **Package managers and dependency auditors:** readiness checks, exact versions/hashes, dependency explanations, and repair without acquisition ambiguity.
- **Game feel:** immediate feedback and small, purposeful moments of delight—but never at the expense of speed or clarity.
- **Accessibility and platform conventions:** multiple equivalent input methods, semantic focus, reduced motion, readable contrast, large targets, and native expectations.

## Review Questions for Every Feature

1. Does the happy path require a decision the system can safely make?
2. Can the user tell what happened to their files or saves?
3. Is the action reversible and recoverable?
4. Does it still work acceptably offline or during interruption?
5. Can it be completed with controller, keyboard, pointer, and assistive technology where relevant?
6. Does motion communicate something useful?
7. Are confidence, compatibility, and legal boundaries stated honestly?
8. Does this preserve a clean exit from the ecosystem?
