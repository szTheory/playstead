# Gray Area D — Cache & Download Semantics (Phase 3)

Researched: 2026-08-30. Grounded in PROJECT.md priority order (data safety #1), ROADMAP §Phase 3 criteria 2–3, CACH-01…04, P2 D-11/D-15/D-23/D-33, P1 D-10/D-19/D-20/D-21, WEB-AND-CLIENT-ARCHITECTURE §Mac client, and `blobs_controller.ex` as it exists today (whole-file chunked 200, ETag=sha256, no Range yet).

Scale calibration: personal server on LAN/Tailscale, one user, seven retro systems. Blob sizes: KBs–MBs (GB/GBA/NES/SNES/MD) up to ~700 MB per PSX BIN track, a few GB per multi-disc game. This is not Steam scale; every design below is judged against that.

---

## 1. Transfer mechanics

### Option table

| Option | Pros | Cons | Complexity | Recommendation |
|--------|------|------|------------|----------------|
| Whole-blob GET + single-range resume (`Range: bytes=N-` + `If-Range: <sha256>`) | Plain HTTP; blobs are immutable so If-Range never misfires; server side is `send_file` offset/length; resume = file length on disk; freezes the smallest possible protocol | One TCP stream per blob (fine on LAN); a corrupt prefix costs a restart of that blob | Server: Range/If-Range parsing in one controller. Client: downloader actor + partial files — Risk: partial-prefix trust, If-Range correctness | **Rec** — matches D-33's deferral exactly; right-sized for MB–GB blobs |
| Steam-style chunk manifest (1 MiB chunks, per-chunk hashes) | Per-chunk verify, parallel chunks, surgical corruption repair | Requires new server-side chunk-hash storage + new manifest contract (D-23 members carry only whole-file sha256+size); protocol surface triples; solves a problem PSX-sized files don't have | New DB columns, new endpoint, chunk assembler — Risk: premature protocol freeze | Rec only if v2 adds WAN/lossy links or >10 GB blobs |
| tus / multipart | Standardized resumable protocol | Explicitly LOCKED out (deferred TRAN-01 v2); designed for uploads, wrong direction | — | Excluded by lock |

### Verified-range survival across restart

Three sub-options for "resume verified ranges" (CACH-01):

1. **Persisted offset + serialized rolling SHA-256 state** — CryptoKit does not expose serializable hash state; you'd hand-roll SHA-256 or use CommonCrypto internals. Fragile, and a crash between byte-write and state-write silently desynchronizes hash state from disk contents → false verify. **Rejected: data-safety hazard.**
2. **Re-hash the partial prefix on resume** (partial file `tmp/<sha256>.partial`, fsynced periodically; on resume, hash bytes 0..len from disk, request `bytes=len-`, continue the running hash) — the disk is the single source of truth; no state file can lie. Re-hashing a 700 MB prefix at NVMe speed is ~0.3–1 s. The "verified range" is literally the bytes proven on disk at resume time. **Chosen.**
3. **Discard partial, restart** — simplest but fails CACH-01's letter ("without restarting verified ranges").

Trailing-truncation note: fsync cadence (e.g., every 8–16 MiB) bounds re-downloaded bytes after a crash; if the on-disk length exceeds the last known-good fsync, still just re-hash what's there — hashing is the authority, not bookkeeping.

### Integrity flow

- Incremental SHA-256 while streaming (same ethos as server D-11 write path).
- On completion: compare running hash to the sha256 identity. **Then** fsync, rename into the local CAS (mirror of server D-11: write-then-verify, rename-as-commit). Mismatch → delete partial, receipt the failure, re-queue with backoff; after N (=3) failures surface an honest attention item ("bytes didn't match after 3 tries — this usually means a network or disk problem, not anything you did").
- No default read-back-after-rename on the client (unlike server D-11): the client cache is reconstructable, so the custody stakes are lower; launch preflight provides a later cheap check. (Optional paranoia toggle mirrors `PLAYSTEAD_IMPORT_VERIFY`.)

### URLSession: background session vs in-process

Apple's own guidance: background-session resume machinery **ignores custom Range headers** ("It's not safe to use a Range header in an NSURLSession background session download task" — Apple dev forums), resumeData is opaque, requires server ETag/Last-Modified and silently falls back to full re-download, and the system may purge the temp file under disk pressure. Our design needs custom Range + our own incremental hashing + our own partial-file custody — all incompatible with `URLSessionDownloadTask` resumeData. Use an **in-process `URLSession` with `URLSessionDataTask`-style streaming (bytes(for:)/AsyncBytes or delegate)** writing to our own partial file. The Mac app is running while downloading (it's a desktop app, not iOS); background sessions buy nothing here. Wrap in a Swift actor (`DownloadEngine`) so concurrency invariants are single-threaded by construction. `ProcessInfo.beginActivity(.userInitiated)` (or NSProcessInfo activity) to discourage App Nap during active transfers; on sleep the TCP stream dies → treated as any other interruption → resume on wake.

### Concurrency

- Sequential members within a game (a partially-usable game doesn't exist — CACH-04 gates on all required members anyway; sequencing makes progress honest and simple).
- One game actively downloading at a time by default (queue below); per-host connection cap 2 (leave headroom for catalogue/journal polls against the same Phoenix server; BEAM handles it, but one user's Mac saturating its own LAN link with parallel streams gains nothing).
- Retry: exponential backoff with jitter (1s→2→4→…cap 60s), infinite while the item stays queued (reconnect auto-resumes), error surfaced passively after threshold.

### Server-side frozen contract (Phoenix must now honor precisely — this becomes protocol)

- `Accept-Ranges: bytes` on all blob responses.
- `ETag: "<sha256>"` (note: **quoted**, strong — current controller emits unquoted; fix while freezing).
- Single-range `Range: bytes=N-` and `bytes=N-M` → `206` with `Content-Range: bytes N-M/total` + `Content-Length`. Serve via offset/length read on the CAS file (the D-12 `stream/2 (sha256, range)` seam already anticipates this) — not `send_chunked`.
- `If-Range: "<sha256>"` → honor range if it matches (it always will; blobs immutable); mismatch → full 200. `If-None-Match` → 304 (cheap client "still exists" probe).
- Multiple ranges in one header → respond 200 full body (spec-legal, avoids multipart/byteranges forever).
- `Range` start ≥ size → `416` + `Content-Range: bytes */total`.
- `HEAD` supported (size probe for progress totals before first byte).
- No `Content-Encoding` on blobs ever (identity only — compression would break Range/offset math and hash identity).
- Authorization unchanged: source_file ownership + quarantine release check run before any byte, including 206s and HEAD.
- Contract tests: 206 arithmetic, If-Range, 416, HEAD, quoted ETag, and a resume-mid-file byte-identity test (download prefix, kill, resume, hash equals sha256).

## 2. Cache store layout on Mac

| Option | Pros | Cons | Complexity | Recommendation |
|--------|------|------|------------|----------------|
| CAS keyed by sha256 (`objects/sha256/ab/cd/<hash>`, mirrors server D-11) + per-game **materialized launch dirs via APFS `clonefile()`** | Natural dedupe (shared BIOS/tracks across sets); verify/evict logic keys off blob identity exactly like the server; emulators see real filenames (CUE references demand original basenames per D-15/D-34); clonefile = zero-cost, CoW-protected (emulator scribbling on a clone never corrupts the verified CAS copy) | Two layers to reason about; clonefile is APFS-only (fallback: copy — never hardlink, a hardlinked file edited by an emulator corrupts the CAS) | CAS dir + materializer in adapter host, clonefile via `filemanager.copyItem` (auto-clones on APFS) — Risk: stale clones after re-download; solved by re-materializing per launch | **Rec** — coheres with server custody model and D-15 member naming |
| Per-game folders only (emulator-readable, no CAS) | One layer; user-browsable | No dedupe (multi-disc/BIOS duplicated); eviction/verification per-file-per-game; emulator writes can corrupt the verified bytes in place — direct data-safety violation | — Risk: verified bytes mutable by external process | Rec against |

**Location: `~/Library/Application Support/Playstead/` — NOT `~/Library/Caches/`.** Caches is documented as system/user-purgeable; the OS or a "clean my Mac" tool deleting pinned-offline game bytes silently breaks the CACH-02 promise ("pinned-offline" means *it will be there on the plane*). "Safe-to-evict" is a *product* state the user controls, not an invitation for the OS to evict. Mitigate the backup-bloat concern instead: set `NSURLIsExcludedFromBackupKey` on the CAS (it's reconstructable from the server — honest and Time-Machine-friendly). Materialized launch dirs live beside the CAS (`launch/<asset_set_uuid>/`), rebuilt from clones on demand, deleted freely (they're clones — near-zero bytes).

## 3. Capacity policy

| Option | Pros | Cons | Complexity | Recommendation |
|--------|------|------|------------|----------------|
| Fixed quota + free-space floor, limit **blocks new downloads** with honest reclaim prompt; **manual eviction only** in Phase 3 (LRU-ordered suggestions) | Predictable; no silent deletion ever (data-safety lens: auto-evict that surprises a user pre-flight-mode is a trust failure even when technically safe); reclaim UI can be provably honest | User must occasionally click "free up space" | Settings pane + downloader gate + eviction sheet — Risk: quota accounting drift; recompute from CAS on launch | **Rec** for Phase 3 |
| LRU auto-evict at quota | Zero-touch | "Where did my game go?" the night before a trip; interacts badly with pin semantics user hasn't learned yet | — | Rec only after pin UX is proven (v-next toggle, default off) |
| Free-space floor only | Simple | Cache can silently swallow a disk over months | — | Keep as the second guard, not alone |

Defaults: quota 25 GB (holds a full 7-system retro library minus PSX depth; PSX users raise it), floor: never take the volume below 10 GB free — floor wins over quota. At the limit mid-download: pause the queue item (state stays `queued/partial`), banner names the exact reclaimable number.

Pin semantics: **per-game** (per-collection = "pin all games in it now", not a live rule — keeps Phase 3 honest); pinned = never evictable (grayed in reclaim UI with reason) **and** jumps the download queue to completion. Reclaim sheet lists only verified+unpinned items, sorted LRU, copy: "Freeing space removes only downloaded copies. Your games stay safe on your server and can be re-downloaded any time." — never touches partials-in-progress bookkeeping lies: partial bytes of *cancelled* items are reclaimable and listed as "incomplete download".

Six-state mapping (CACH-02): server-only (no local bytes) → queued (queue row, no/partial bytes, engine not on it yet or offline) → partial (bytes growing/paused) → verified-local (in CAS, verify record) → pinned-offline (verified + pin flag) → safe-to-evict (verified + unpinned — same bytes as verified-local, presented through the storage lens). States are **derived** from (queue row, partial file, CAS entry, pin flag), never stored as a free-standing enum that can drift from disk truth.

## 4. Download queue

- **Persistent, user-visible, ordered queue** (SQLite via the app's local read-model store; client-generated UUIDv7 ids per P1 D-20 ethos). Survives app restart; on launch, sweep: reconcile queue rows against partial files and CAS (adopt orphans, resume partials).
- **Sequential by default** (one game at a time, members in ordinal order) — honest ETA, no thrash; drag-to-reorder, pause/resume/cancel per item. Cancel keeps partial bytes (cheap resume if re-queued) but labels them reclaimable.
- Enqueue while offline is a normal quiet state: items sit `queued`, engine wakes on reachability change (NWPathMonitor) and auto-resumes — no error styling for "server unreachable", just "waiting for your server".
- A collection enqueues its member games as individual rows (visible, individually cancellable).
- Queue feeds states directly: row exists ⇒ queued; engine active/paused on it with bytes ⇒ partial; completion+verify ⇒ row deleted, CAS entry ⇒ verified-local.

## 5. Verification lifecycle

- **Verified-at-download is the authority event** (full incremental hash, above). Record `{sha256, size, verified_at, inode, mtime}` in the local DB.
- **Launch preflight (CACH-04 gate)**: for every `required` manifest member — CAS file exists, size matches, inode+mtime match the verify record → trust it (milliseconds, fully offline). Cheap check fails → full re-hash right there (seconds; show "double-checking game files…"); hash fails → quarantine. **No network in the gate, ever.** Optional-role members (manuals/artwork) never block launch (D-15 `required` flag is the contract).
- **No periodic background re-hash** in Phase 3 (bit-rot on a client cache is not a data-safety issue — the server is canonical; a scheduled scrub is server/Phase-5 territory). **After unclean shutdown**: only in-flight partials need re-hash-on-resume, which the resume path already does by construction.
- **Corrupt-cache handling**: move the bad file to `quarantine/<sha256>.<ts>` (never delete evidence immediately; swept after 7 days), flip derived state back to server-only, auto-enqueue re-download if the user was launching, copy: "One of this game's files didn't match its fingerprint, so we're fetching a fresh copy from your server." Never "corrupt", never user-blaming — matches the D-26 vocabulary rules.

## Adversarial pass

| Scenario | Failure mode | Design answer |
|---|---|---|
| Crash mid-write, partial has trailing garbage past last fsync | Resume from bookkept offset would verify garbage | Disk is truth: re-hash actual prefix on resume; final whole-hash check is the backstop |
| Sleep / Wi-Fi flap mid-transfer | TCP dies, half-written buffer | Same as crash path; NWPathMonitor + backoff auto-resume on wake |
| Disk fills mid-download or mid-materialize | write fails / clone fails | Pause queue (state `queued`, bytes kept), one banner with reclaim CTA; clonefile failure surfaces as preflight remedy, never a crash |
| Disk fills mid-verify | none — verify only reads | n/a |
| Server restarts mid-stream | Connection reset | Retry/backoff; blobs immutable so resume is always coherent (If-Range can't mismatch) |
| Server returns 200 instead of 206 (old server / proxy strips Range) | Client appends full body after prefix → corrupt double-length file | Client MUST check status: on 200, truncate partial to 0 and restart hash; capability handshake (`transfer` namespace, P1 D-19) advertises `range-resume` so mismatched versions are explained, not mysterious |
| Proxy adds Content-Encoding / transforms body | Hash mismatch loop | Final hash check catches it; after 3 failures the attention item names the likely proxy cause; contract test pins identity encoding |
| User edits a CAS file / emulator writes through | Verified bytes mutated | Emulator only ever sees CoW clones; preflight inode/mtime check catches external edits → re-hash → quarantine+redownload |
| OS purges cache dir | Pinned game vanishes offline | Prevented by choosing Application Support, not Caches |
| Partial file for hash X adopted for hash Y (name collision/tamper) | Wrong bytes verified | Partial named by sha256 AND final whole-hash must equal that sha256 — adoption of a wrong prefix just fails verify and restarts |
| Revoked device mid-download | 401 `device_revoked` | Queue pauses with the D-11 humane re-pair copy; verified local games remain launchable (offline gate has no network) |

## Prior art notes

- **Steam depot/chunk model** (1 MiB LZMA chunks, per-chunk adler32, chunk manifest): right for 100 GB titles over WAN + CDN dedupe; overkill at MB–GB on LAN — the value (surgical repair, massive parallelism) doesn't pay for a second manifest contract here. [SteamDB blog]
- **Apple WWDC23 "resumable file transfers" + community writeups**: confirm ETag+Range as the resume substrate and the background-session/custom-Range incompatibility that drives the in-process choice. [Apple, kean.blog, avanderlee.com]
- **Plex/Jellyfin sync**: whole-file transfer with server-canonical library and client "sync/download" states — same shape as chosen; their user-facing lesson is honest per-item state labels, which CACH-02 already mandates.
- **Xbox/PS5 install UX**: queue with explicit ordering + "ready to start" gating mirrors the CACH-04 all-required-members gate; their auto-evict complaints ("why was my game removed") support manual-eviction-first.

## Sources

- Apple WWDC23 — Build robust and resumable file transfers: https://developer.apple.com/videos/play/wwdc2023/10006/
- kean.blog — Resumable Downloads (ETag/If-Range/206 mechanics): https://kean.blog/post/resumable-downloads
- avanderlee.com — URLSession background task pitfalls: https://www.avanderlee.com/swift/urlsession-common-pitfalls-with-background-download-upload-tasks/
- Apple Developer Forums — Range header unsafe in background download tasks: https://developer.apple.com/forums/thread/47460
- SteamDB — Steam download/preload system (1 MiB chunk model): https://steamdb.info/blog/steam-download-system/
- Project grounding: PROJECT.md, ROADMAP.md §Phase 3, REQUIREMENTS.md CACH-01…04, 02-CONTEXT.md D-11/D-12/D-15/D-23/D-33, 01-CONTEXT.md D-10/D-19/D-20/D-21, WEB-AND-CLIENT-ARCHITECTURE.md, blobs_controller.ex
