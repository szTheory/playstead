# Gray Area B — Curation Ownership & Sync (Favorites, Collections, Continue, Recent, Play Queue)

Phase 3: Mac Offline Play Vertical Slice. Requirements LIBR-03 (curate without altering canonical game bytes), LIBR-05 (console parity). Researched 2026-08-30.

## Grounding facts (read from repo/planning, not assumed)

- `Playstead.Sync.EntityKind` freezes six kinds: `device pairing catalogue job transfer save`. The moduledoc's stated purpose of the freeze is (a) a later phase attaches a *producer* for an already-registered kind without protocol change, and (b) the `Entry` changeset rejects unregistered kinds so nothing sneaks in silently. There is **no `curation` kind**.
- Critical timing fact: **no native client exists yet**. Phase 3 ships the *first* journal consumer. A seventh kind added now, registered in `EntityKind` and advertised via capabilities (P1 D-18 additive-only minor evolution), breaks zero deployed clients. The same addition after Phase 3 ships would require capability gating on the client side.
- P2 D-23: the `catalogue` payload is frozen ("additions only, never renames") and deliberately excludes user-preference data. D-30 establishes the split: journal for read models clients reconstruct; REST (with `Idempotency-Key`) for commands and rarely-replayed detail.
- P1 D-20: idempotency = header receipts + client-generated UUIDv7 natural keys with `on_conflict` upsert convergence. D-21: journal + snapshot + cursor + 410 resync is "the recovery spine every client's sync engine implements."
- EXPERIENCE-ETHOS: "Primary views: Continue, Favorites, Collections, Queue, Recent, and chosen Systems"; "Curation is user-directed before it is algorithmic"; sync honesty ("never say Synced when a write is merely queued").
- WEB-AND-CLIENT-ARCHITECTURE: "Offline client changes → local command/outbox journal; replay idempotently" — the Mac outbox pattern is already the sanctioned design.
- Phase 4 owns saves. Continue in Phase 3 cannot reference save revisions.

## Decision point 1 — Ownership model per curation noun

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| A. Everything server-canonical, per-user | One model; console parity free; "new computer, same library" story holds for curation | Requires play-event reporting for Recent/Continue | **Chosen** for favorites, collections, queue, Recent, Continue |
| B. Queue per-device | Matches Spotify/Apple Music device-queue prior art | Wrong prior art: a music queue is an ephemeral playback buffer; Playstead's play queue is a *backlog/watchlist* ("what I intend to play"), hours-long sessions, planned on the couch (console) and used at the Mac. Per-device breaks the LIBR-05 success criterion ("console offers the same canonical library views") and the migration story | Rejected |
| C. Recent/Continue client-local only | Zero server knowledge of play habits | Breaks clean-reinstall restore (PROJECT success metric), breaks console parity, and Phase 4 will need play/save session reporting anyway; on a *self-hosted* server the privacy argument is weak — the user owns the server | Rejected |
| D. Hybrid: curation synced, Recent/Continue local | Avoids play events in Phase 3 | Recent/Continue are named in the Phase 3 success criterion for the console too; hybrid gives two freshness models for adjacent shelves | Rejected |

**Recent/Continue derivation:** both derive from **play events**. The Mac posts `POST /api/v1/play-sessions` (UUIDv7 id, asset_set id, started_at, ended_at, adapter id) from its outbox after play; posting is never on the launch path (optional services never gate play). Recent = distinct games by last `ended_at`. Continue = Recent minus games the user explicitly marks finished/dismisses from Continue (a curation verb, not a save inference). Copy discipline: Continue means "you played this recently; your emulator's local save is where you left it" — no restore promise until Phase 4.

**Privacy stance:** the server learns coarse play sessions (game, start, end) and nothing finer (no input telemetry, no periodic heartbeats). This is the user's own server; sessions are per-user rows (P2 D-13 scoping), deletable ("Clear play history" is cheap to include; at minimum a dismissal per Continue row). Recording granularity finer than session start/end is explicitly out.

## Decision point 2 — Protocol shape and conflict semantics

### Read path

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| A. New `curation` entity kind + snapshot branch | Rides the D-21 recovery spine (cursor, 410, snapshot, compaction, convergence tests all exist); offline Mac read models come free; console and Mac converge identically | Touches the "frozen" EntityKind list | **Chosen** — see freeze analysis below |
| B. Stuff curation into `catalogue` payload | No new kind | Violates frozen D-23 payload; every favorite toggle re-emits a large catalogue entity; mixes canonical facts with preferences; per-user preference in a payload D-23 defined as canonical library truth | Rejected hard |
| C. REST-only reads (ETag polling) | No journal change | Builds a *second* sync mechanism beside the spine D-21 says every client implements; offline read models need hand-rolled diffing; resync-after-410 wouldn't cover curation | Rejected |

**Freeze analysis (adversarial):** the freeze's letter says six kinds; its *mechanism* (registry + changeset validation + capability advertisement) exists precisely so kind vocabulary is deliberate. Amending the registry additively in Phase 3, before any client ships, preserves every property the freeze protects: no unregistered kind can be written, clients built from Phase 3 onward know `curation` from day one, and D-18's additive-minor rule (unknown keys ignored, capability-advertised) covers any hypothetical earlier consumer (there are none). This must be logged as a deliberate context decision, not done silently. The alternative reading ("never add a kind, ever") would force option B or C, both strictly worse for the contract the freeze serves.

**Entity granularity within `curation`:** one kind, three payload shapes discriminated by an inner `type` field, entity_id = the row's UUIDv7:
- `favorite` `{type, asset_set_id, created_at}` — tombstone on unfavorite
- `collection` `{type, name, created_at, updated_at}` — tombstone on delete
- `collection_member` `{type, collection_id, asset_set_id, position, added_at}` — tombstone on remove
- `queue_item` `{type, asset_set_id, position, added_at}` — tombstone on remove/complete
- `continue_dismissal` `{type, asset_set_id}` — small, honest, replayable

Play sessions themselves are **REST-read, journal-summarized**: the journal carries a compact `recent` payload per game (`{type: "recent", asset_set_id, last_played_at, play_count}`) so shelves reconstruct from the journal alone; full session history (if ever surfaced) is cursor-paginated REST, mirroring the D-30 receipts precedent.

Snapshot gains a `curation` branch inside the same consistent transaction (P1 discretion note already allows per-domain snapshot branches; Phase 2 added `catalogue`/`job` the same way — direct precedent).

### Write path (mutations)

REST commands with `Idempotency-Key` + client UUIDv7 row ids, per D-20/D-30 — no new invention:
- `PUT /api/v1/curation/favorites/:asset_set_id` / `DELETE` (natural key = (user, asset_set); toggle is idempotent by nature)
- `POST /api/v1/curation/collections` (client UUIDv7), `PATCH`, `DELETE`
- `PUT /api/v1/curation/collections/:id/members/:asset_set_id` (body: position), `DELETE`
- `PUT /api/v1/curation/queue/:asset_set_id` (body: position), `DELETE`
- `POST /api/v1/play-sessions` (client UUIDv7 id; `on_conflict` no-op)

Mac offline queueing: the existing sanctioned outbox — commands recorded locally with their UUIDv7 ids, replayed in order after reconnect; replay past receipt expiry converges via natural-key upsert (D-20b). UI shows optimistic local state with the ETHOS-mandated honesty ("queued", not "synced") only where it matters (a subtle pending indicator, not per-row badges).

### Conflict semantics

| Concern | Option considered | Verdict |
|---|---|---|
| Favorite toggled on two offline devices | Ordered CRDT counters vs LWW | **LWW by server arrival order.** A boolean toggle race has no "lost action" — whichever intent lands last wins, both intents were applied. Proportionate. |
| Collection membership add vs remove (concurrent) | OR-set (add-wins) vs LWW per membership | **LWW per membership row** (server arrival). Worst case: a game the user removed on device A reappears because device B re-added it offline — visible, one tap to fix, never silent data loss. OR-set adds tag bookkeeping for a case a single household user hits ~never. |
| Queue / collection reordering | (a) ordered-list CRDT (RGA/Logoot), (b) full-list overwrite LWW, (c) **fractional-index position per item + server rebalance** | **(c).** Client sends intent ("X gets position between Y and Z" as a fractional key, Figma/Linear-style); concurrent reorders interleave rather than clobber; a full-list overwrite (b) is the one option that *can* silently drop an offline addition from the other device — disqualified by the "never silently loses a user action" bar. CRDT (a) is Google-Docs-grade machinery for a list of a few dozen games. Server rebalances keys when precision exhausts and re-journals affected items. |
| Duplicate replay (outbox after receipt expiry) | — | UUIDv7 natural keys + `on_conflict` upsert (D-20b) — already the contract. |

Invariant stated for tests: **no client ever transmits a whole list as truth; every mutation is a single-row intent.** That single rule is what makes every conflict above merge-visible instead of merge-lossy.

## Decision point 3 — Data model

| Question | Decision | Rationale |
|---|---|---|
| Collections ordered or unordered? | **Ordered** (same fractional-position column as queue), default view sort still user-switchable (manual / title / recently added) | One mechanism serves both; Plex/Jellyfin ship unordered collections and users immediately request ordering (playlists exist to fill the gap); adding order later would be a payload change to a shipped contract |
| Smart/dynamic collections in Phase 3? | **No.** Recently Added, per-system, Continue, Recent are *built-in derived views* (computed from catalogue + curation read models), not stored collections. Manual collections only | "Curation is user-directed before it is algorithmic" (ETHOS). A rules engine is a shipped contract; derived views are just queries. Immich's albums-then-smart-search sequencing is the sane prior art |
| Nesting / collections of collections | No | Steam categories, Plex collections, Immich albums are all flat; nesting is complexity with no Phase 3 requirement |
| Caps | Sanity caps, generous: name ≤ 100 code points (D-22 sanitization rules reused: NFC, control/bidi stripped), ≤ 500 collections/user, ≤ 5,000 members/collection, ≤ 500 queue items; RFC 9457 `code` on violation | Bounds journal payloads and snapshot pages; a personal library never legitimately hits these |
| One queue or many | **One play queue per user** | The requirement says "a play queue"; multiple queues ≈ collections, which already exist |
| Naming vocabulary | Favorites, Collections, Continue, Queue ("Up Next" as display label candidate), Recent | Matches ETHOS primary views verbatim |

## Decision point 4 — Console parity scope & first-run

- **Console ships (LIBR-05):** the same shelves — Favorites, Collections (create/rename/add/remove/reorder), Continue, Recent, Queue — as LiveView views calling the *same context functions* the API controllers call (Phase 2 house rule). This is cheap because reads come from the same tables the journal producers watch; LiveView is never the protocol.
- **Mac-only:** launch/preflight integration of Continue and Queue (play from shelf), local availability badges interleaved with curation state.
- **First-run/empty states (LIBR-04):** a new library shows All Games + Systems-with-content only. Continue/Recent/Queue shelves are **hidden until they have content** (not shown empty); Favorites and Collections show one quiet inline hint each on first visit ("Favorite a game to start your own shelf" / "Collections group games your way — Weekend RPGs, With the Kids"), dismissible, never a modal or forced setup. First play event materializes Recent+Continue silently — the shelf appearing *is* the feedback.

## Lens findings

- **Product/UX:** the queue is a backlog, not a playback buffer — that single reframe resolves the per-device question. Continue without saves is still honest if copy points at the emulator's local state.
- **Distributed systems:** every scheme that transmits list-state instead of row-intent fails the no-silent-loss bar; every row-intent scheme with UUIDv7 keys converges under the existing D-20/D-21 machinery. Nothing new to build below the payload level.
- **Elixir/Ecto idiom:** curation rows are ordinary user-scoped schemas; journal append + effect in one transaction (existing `ChangeJournal.append/4` pattern); fractional position = string column, btree-sorted; rebalance = one `Repo.transaction` re-keying + re-journaling.
- **Swift persistence:** Mac read models in the client's local store (SQLite/GRDB or SwiftData per the client-architecture spike) mirror journal payloads 1:1; outbox is a local table of pending commands with UUIDv7 ids — no bespoke merge code on the client.
- **Multi-device:** two-device convergence is testable now (Mac + console session) against the D-21 contract test style: apply interleaved offline mutations, replay both outboxes, assert identical read models.
- **Privacy:** self-hosted per-user rows; session-grain only; deletable; nothing leaves the user's server.

## Adversarial pass

1. "Frozen means frozen — you're breaking D-21." Answered above: the freeze's protected properties all survive an additive registration before any client ships; the risky move is *waiting* until after Phase 3, when a new kind needs capability gating in shipped clients. Log it as an explicit decision.
2. "Fractional indexing is still over-engineering." The only simpler scheme (integer ordinal + full-list rewrite) is exactly the one that silently drops concurrent offline additions. Fractional keys are ~30 lines and one string column.
3. "Play events are surveillance creep." Session-grain, self-hosted, deletable, and required by the Phase 3 success criterion (Recent/Continue on both surfaces) and Phase 4 anyway. The alternative (client-local Recent) fails clean-reinstall restore — the project's stated success metric.
4. "Continue is a lie before Phase 4." Only if copy promises restore. It must not; it promises recency. Phase 4 upgrades the same shelf in place.
5. "LWW membership can resurrect a removed game." True, visible, one-tap fix, and the documented tradeoff vs OR-set bookkeeping. Acceptable at personal-library scale; revisit only if household sharing changes concurrency reality.
6. "Journal churn from reorder drags." Coalesce: client batches a drag gesture into one final position command; server journals only settled rows. Never journal per-pixel moves.

## Prior art consulted

- Jellyfin: favorites/playlists sync gaps and third-party clients hand-rolling offline sync are a cautionary tale for REST-only curation reads ([issue 12501](https://github.com/jellyfin/jellyfin/issues/12501), [feature request 589](https://features.jellyfin.org/posts/589/sync-playlists-for-offline-listening), [Symfonium favorites-sync thread](https://support.symfonium.app/t/jellyfin-favorites-not-being-automatically-synced/3945)).
- Plex watchlist: server-canonical per-user watchlist synced to all clients — the queue-as-watchlist model adopted here.
- Steam categories/favorites: per-user cloud-synced flat categories; historical local-config era caused loss/desync — reinforces server-canonical.
- Spotify/Apple Music queues: per-device playback buffers with explicit handoff — rejected as the wrong analogy for a game backlog.
- Immich: albums are server-canonical ordered-ish sets; smart features arrived later as derived queries, not stored rules — sequencing adopted for smart views.
- Figma/Linear fractional indexing: standard proportionate ordered-list merge without CRDTs.

