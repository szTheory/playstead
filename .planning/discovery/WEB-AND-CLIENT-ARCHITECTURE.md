# Web and Client Architecture

**Scope:** Phoenix server/web console, durable native-client API, optional browser play, and the first Mac client  
**Researched:** 2026-08-26  
**Confidence:** MEDIUM-HIGH for v1 boundaries; MEDIUM for browser-play viability until measured against one chosen core/system

## Decision in Brief

Build one Phoenix application with a conventional, versioned HTTPS API as the product boundary and a Phoenix LiveView web console as a first-party *consumer* of the same application/domain services. Build the first player client as a native macOS app using SwiftUI for application UI and AppKit where its mature macOS behavior is necessary. Keep a thin, typed adapter boundary for filesystem, launch, save observation, controller input, cache, credential storage, and update state.

Do **not** let LiveView events, sockets, assigns, or rendered HTML become an implicit client protocol. LiveView deliberately maintains server-side connection state and re-mounts after a dropped connection; that is a productive fit for authenticated browser administration and live import/job progress, but is incompatible with a native client that must browse, launch, and reconcile saves while disconnected. [Fact: Phoenix LiveView lifecycle documentation, S1.] Native and future handheld clients use the HTTP API plus an explicitly optional event-feed mechanism; all decisive workflows are resumable from durable server records.

Treat browser emulation as a later, high-value convenience client for a narrow verified system/core matrix, not as v1's launch path or as proof of universal browser compatibility. A browser can execute WebAssembly and poll controllers, but offline storage, threading, large byte delivery, iOS lifecycle constraints, core licensing, and persistent-save contracts make it an empirical integration project. EmulatorJS is useful prior art and is self-hostable, but its own project declares some support (for example, PSP) beta/not ready and distributes under GPL-3.0-or-later. [Fact: S14, S15.] It should not be embedded or distributed without a separate licensing and capability review.

## Recommended Boundary and Data Flow

```
                         browser-only concern
                  ┌────────────────────────────────┐
                  │ Phoenix LiveView web console    │
                  │ library/admin/import receipts   │
                  │ job progress + pairing pages    │
                  └──────────────┬─────────────────┘
                                 │ domain calls / read models
  Mac native client               │
 ┌─────────────────────┐   HTTPS JSON + blob HTTP Range    ┌───────────────────────────┐
 │ SwiftUI / AppKit UI  │──────────────┬───────────────────▶│ Phoenix boundary          │
 │ cache + sync engine  │              │                    │ /api/v1                  │
 │ adapter host         │     optional resumable event feed│ auth, policy, validation  │
 └─────────┬───────────┘              │                    └───────┬──────────┬────────┘
           │ local only               │                            │          │
           ▼                          ▼                            ▼          ▼
 emulator process /          future handhelds             Postgres      object store
 BIOS materialization /      and web client               jobs/events   immutable blobs
 controller + save files
```

### Rules that preserve the boundary

1. The domain owns library identity, manifests, import outcomes, save revisions, readiness facts, device registrations, transfers, and authorization. It has no `LiveView.Socket`, HTTP request, emulator path, or Swift type.
2. `/api/v1` owns the wire contract. It exposes commands, resource/query representations, cursor pagination, conditional reads, stable errors, idempotency, capability negotiation, and immutable blob/download endpoints. It has no LiveView-specific payload or HTML fragment.
3. LiveView and the native client use application services/read models, not each other's transport or rendering code. The browser console may call a small same-origin API where it helps, but it cannot become its sole integration route.
4. The native adapter owns platform-dependent effects: choose/materialize local files, launch and observe the emulator, obtain controller events, detect a safe save flush, and report adapter capabilities. The server owns none of those paths or process semantics.
5. Transfer and job records are durable. A socket, a client process, a LiveView process, or a browser tab can disappear without losing the operation's identity, receipt, cancellation state, verified bytes, or next retry decision.

## Phoenix and LiveView

### Recommended use

Phoenix/LiveView is the right v1 server-web stack. A LiveView begins as normal HTTP HTML and then connects to a server-side process whose state updates are rendered as diffs. It provides server-rendered accessibility-friendly HTML, form validation, streamed list updates, uploads, and async-result primitives. [Fact: S1.] This is unusually well aligned with the deployment/admin console, import receipts, exception inbox, library management, backups, audit history, device pairing approval, and live background-job progress.

Use LiveView for these flows:

| Flow | Why it fits | Required durability rule |
|---|---|---|
| Server setup, account/device approval, backup health | Authenticated, low-frequency, explainable forms | Reload must reconstruct every state from DB/read models. |
| Library browse, filters, collections, metadata correction | Fast server-rendered queries, URL-addressable filters, streamed rows | Query state belongs in URL; results must work after reconnect. |
| Import review and staged-collection orchestration | Inline validation, receipts, progress, exception resolution | Import session/job is persisted before any work begins. |
| Progress/readiness dashboards | Live fan-out makes current status pleasant | Live push is acceleration only; HTTP refresh yields the same truth. |
| Browser pairing approval | One-time interactive confirmation | Approve/reject is a normal authenticated command with audit record. |

### LiveView constraints that matter here

On the first visit, LiveView renders an HTTP response then mounts again when the client connects. If the connection drops or the process crashes, it reconnects and runs `mount/3` and `handle_params/3` again. [Fact: S1.] Consequently:

- Never use assigns, a LiveView PID, `handle_info`, or a pushed event as the only source of import, pairing, save, transfer, or device state.
- Never couple a long-running hash/import/download to the lifetime of the LiveView process. The documentation notes that LiveView async work may stop when the LiveView exits; a supervised, persisted job must own work that must outlive navigation. [Fact: S1.]
- Expect duplicate mount behavior. Make mount read-only/idempotent; create commands only from explicit idempotency-keyed actions.
- Present a deliberate offline/degraded state. A web console can preserve static HTML and reconnect, but it is not an offline player: it cannot safely promise current server truth, local emulator launch, or durable unsynced-save handling after loss of connectivity.
- Treat all LiveView params/event payloads as untrusted; LiveView itself documents authorization and validation requirements for these client-controlled values. [Fact: S1.]

### Web information architecture: progressive disclosure

The console should feel like a curated library, not an operations dashboard or a raw file manager.

**Default navigation:** Home, Library, Imports, Devices, Health. Home is a small readiness digest: recent play (when clients report it), continue-ready count, queued/attention count, backup health, and the one next meaningful action. Library starts with curated views (Favorites, Recently Played, Queue, Collections); the canonical all-items archive is reachable, never forced.

**System visibility:** hide an unconfigured/empty system from primary browse and system filters by default. Reveal it in an expandable “Other systems” group only when it has a pending import, a recognized item, an error, or an explicit user preference. Each visible system carries useful counts: total items, playable now, needs attention, server-only, downloaded-on-this-device (in client UI), and missing dependency where known. Do not render a wall of empty consoles.

**Contextual settings:** settings are grouped by actual ownership: Server & storage, Import policy, Devices & pairing, Metadata providers, Backup & restore, Diagnostics. System/core/BIOS settings appear only after an adapter declares the relevant capability or an item needs them. Expert flags stay in an Advanced disclosure with a short consequence statement.

**Search:** one global command/search field indexes titles, alternate names, system, collection, source filename/provenance (with permissions), and import exceptions. Results are typed and scope-labelled. Search selects a useful view; it must not collapse every subsystem into a generic table.

**Accessibility:** all browse/management paths retain semantic HTML, keyboard order, clear focus, and non-color-only readiness. Controller-first navigation is a client responsibility; the web console is keyboard/pointer/assistive-tech complete and may add controller shortcuts later, not rely on them.

## Durable API for Native and Handheld Clients

### V1 contract

Use HTTPS JSON for control-plane resources and commands, plus standard HTTP for bytes:

```
GET  /api/v1/capabilities
POST /api/v1/device-pairing/requests
POST /api/v1/imports                 Idempotency-Key required
GET  /api/v1/imports/{id}
GET  /api/v1/library?view=favorites&cursor=...
GET  /api/v1/items/{id}/manifest
GET  /api/v1/blobs/{sha256}          Range, ETag, immutable cache semantics
POST /api/v1/saves/{save_key}/revisions   base_revision required
GET  /api/v1/changes?cursor=...      durable cursor; long-poll initially
```

The first response after authenticated pairing is a capability document: protocol major/minor, server build, supported client ranges, feature flags, allowed content/upload modes, rate/size limits, event-feed support, and deprecation notices. The native client reports its client build, OS/platform, adapter fingerprints, supported persistent-save classes, and transfer capabilities. Major incompatibility is a clear no-play/no-mutate error with upgrade action; additive optional fields/features are ignorable. This gives native clients a stable contract without holding them hostage to server release cadence.

Use resource schemas published as OpenAPI (with checked examples and generated test fixtures), but avoid generating the Mac client's entire domain model from server code. Hand-write a small transport client around stable schemas and map it into client-owned models. Version the public boundary at `/api/v1`, carry a schema/representation version where it prevents ambiguity, and publish compatibility and sunset windows. GitHub's API guidance treats additive changes differently from removed, renamed, or newly-required fields; the same discipline is appropriate here. [Fact: S13.]

### Command, event, and offline model

| Need | v1 mechanism | Do not use |
|---|---|---|
| Mutate safely across retry/reconnect | `Idempotency-Key`, command ID, persisted outcome/receipt | A WebSocket/LiveView event as the only acknowledgement |
| Import/download/job progress | `GET /jobs/{id}` plus long-poll or `GET /changes?cursor=` | Ephemeral progress only in a LiveView assign |
| Refresh client library | Cursor-based change journal with reset/snapshot semantics | Treating a full library listing as a sync protocol |
| Mutable save synchronization | Immutable revisions + `base_revision`; explicit conflict heads | Last-write-wins timestamps |
| Content transfer | `Range`, `ETag`, SHA-256, immutable manifest/blob IDs | HTML download routes or multipart ETag as content identity |
| Offline client changes | Local command/outbox journal; replay idempotently after auth refresh | Queuing raw UI gestures or relying on a persistent socket |

Start the change feed with authenticated polling/long-poll and a durable cursor. Add Server-Sent Events or WebSocket only after measuring a real need; each event is merely a hint that causes an idempotent cursor fetch. A client that misses every notification must converge by calling the same HTTP endpoint. Keep blobs/proprietary content private: a capability or manifest authorization is required for every blob request, no predictable shared URLs, and credentials never reach the object store unless a later explicit direct-transfer design gives narrowly scoped short-lived authorizations.

## First Mac Client

### Recommendation: SwiftUI app with an AppKit escape hatch and a narrow adapter host

Choose a native SwiftUI macOS application for the first proof, using AppKit where SwiftUI does not yet offer the required control or accessibility fidelity. This is a product decision: this client must prove macOS filesystem behavior, secure credential handling, launching an external emulator, local cache durability, controller behavior, system preferences, accessibility, code signing/notarization, and recovery after sleep/offline transitions. Apple exposes the Game Controller framework for controller integration and requires/notably documents notarization for distribution outside the App Store. [Fact: S10, S11.] The native option has the least translation layer between the work to be proven and the platform APIs that govern it.

Suggested shape:

```
App UI (SwiftUI + focused AppKit components)
  ├─ Presentation: browse, search, readiness, transfer and conflict views
  ├─ Application: sync coordinator, local DB/read models, command outbox
  ├─ Protocol client: API schemas, auth, retries, Range downloader
  ├─ Cache manager: manifest + sha256 blob store, pin/LRU/verification
  ├─ Secure services: Keychain credentials, pairing token rotation
  └─ Adapter host
       └─ emulator adapter: discover → materialize → preflight → launch
                             → observe safe save flush → collect revision
```

Keep the app sandbox decision inside the adapter spike. A sandboxed direct-distribution/App-Store-style model, scoped access/bookmarks, and unrestricted external emulator/process coordination have materially different constraints. Do not decide by aesthetics; prove the target distribution and emulator-launch configuration with a legal homebrew test asset. Store secrets in Keychain, not a preferences file. Store cache and adapter materialization in the app-controlled Application Support/cache location; source files selected for import remain user-owned and untouched.

### Decision matrix

| Choice | Filesystem/process + emulator adapter | Controller/keychain/accessibility | Offline cache & performance | Updater/distribution | V1 verdict |
|---|---|---|---|---|---|
| **SwiftUI + AppKit** | Direct macOS APIs; minimum bridge for external process and security-scoped file access | Native Game Controller, Keychain, Accessibility APIs | Native I/O/concurrency; no browser runtime | Apple signing/notarization tooling; distribution policy still a spike | **Choose.** Best way to validate the actual Mac constraints. |
| Tauri 2 shell | Capability-scoped shell/process and filesystem plugins exist [Fact: S12] but need Rust command/security boundaries | Web UI must bridge native controller/accessibility behavior | Smaller than Electron; still webview + two-language boundary | Supports macOS bundles/signing/updater paths | Defer. Strong later if a cross-platform UI becomes real; adds uncertainty to v1. |
| Electron | Full Node/process ecosystem; main/renderer isolation is explicit [Fact: S16] | Native integrations are possible, but additional bridge and Chromium focus handling | Heavy Chromium runtime and memory footprint for a local emulator front-end | Code-signing/notarization supported; Electron warns Keychain-related APIs need proper signing [Fact: S17] | Do not choose for Mac-first proof. Useful only if a proven TypeScript desktop codebase outweighs runtime cost later. |
| Narrow Swift adapter shell over a web UI | Can expose platform operations | Still retains dual UI/runtime boundary; controller focus and offline storage become web concerns | Browser cache semantics leak into critical path | Same packaging work as native | Avoid. It optimizes premature UI sharing rather than the risks v1 must answer. |

### Mac client interaction model

The app opens quickly from local read models and does not wait for server metadata. Library cards show server-only, queued, partial, verified local, pinned, safe-to-evict, missing dependency, and save-sync states. Launch is enabled only when the locally cached manifest is verified and the adapter's local preflight passes. Network recovery happens in background; a verified game never waits on a metadata provider or server to start.

Controller support belongs at two layers: an OS controller source emits a canonical logical mapping; each adapter can map it to its emulator/core configuration. Retain the raw device/profile and a user-editable semantic mapping separately. Do not assume a macOS mapping transfers to other OS drivers or to browser Gamepad API identifiers.

## Optional Browser Emulation: Later Phase, Narrow Contract

### What browser play can be

Browser play can be a compelling out-of-box *companion*: click Play for a supported small/medium system, download a verified local browser cache, run an approved WebAssembly core, attach a controller, and synchronize only an explicitly supported persistent-save artifact. It is especially valuable for quick access from a trusted desktop browser, demo/self-hosted onboarding, and systems that do not need external BIOS or complex disk layouts.

It must be a separate client/adapter implementation against the same API, not a Phoenix LiveView feature and not a fallback that silently replaces the Mac adapter. Browser mode starts with one core/system, explicit supported browsers, a byte-size/asset-set limit, no proprietary firmware distribution, and a clearly marked capability matrix. Never promise that every server item, core, disc system, controller, save, or iOS browser will work.

### Practical constraints

| Concern | Fact / implication | Required design response |
|---|---|---|
| WASM/core execution | WebAssembly enables compiled core execution, but performance/features are core and browser dependent. | Pin core build and options fingerprint; test each supported system/browser. Keep a non-threaded fallback only if it remains acceptable. |
| Threads and isolation | `SharedArrayBuffer` availability is security-gated; cross-origin isolation generally requires COOP and COEP. [Fact: S6, S7.] | Serve play pages and every subresource from an isolation-compatible origin/header policy; audit CDN, iframe, OAuth/popup, analytics and artwork behavior. Capability-detect and fail plainly, not by black screen. |
| Large ROM delivery | Browser cache eviction/quota and interrupted networks are not equivalent to a managed native cache. | Use manifest-first download, HTTP Range, SHA-256 verification, explicit progress/cancel, and a size ceiling in first phase. Do not cache a whole library. |
| Offline cache | Service workers can intercept/cache requests and browser storage APIs expose persistence/quota behavior, but eviction/persistence remains browser/user controlled. [Fact: S4, S5.] | Offer “available in this browser” only after verified bytes; request persistent storage where available; treat it as best effort and provide re-download/recovery UX. |
| Saves | IndexedDB/OPFS-style browser storage is local browser state; browser data loss or clearing is normal. | Write adapter-declared persistent saves to a versioned local record, sync immutable revisions when online, expose unsynced state, and never call it durable backup before server acknowledgement. |
| Controller input | Gamepad API is available as a web platform interface, but device IDs/mappings/focus and browser behavior differ. [Fact: S3.] | Poll only while the play surface is focused/visible; display connection/focus/remap state; maintain keyboard and assistive alternatives. |
| iOS/Safari | Mobile browsers impose lifecycle/memory/background/audio/storage constraints and cannot be assumed to support the same threading/isolation performance as desktop. | Declare iOS/Safari unsupported in first browser-play phase unless the chosen core passes a real-device matrix. Gracefully browse/manage library instead of presenting a broken Play action. |
| Licensing | EmulatorJS is GPL-3.0-or-later; bundled WASM cores have their own licensing. [Fact: S15.] | Create a bill of materials and distribution/legal review before shipping any core. Do not copy CDN artifacts or embed a GPL project into a differently licensed distribution by default. |

### Prior art, used correctly

EmulatorJS demonstrates a self-hostable JavaScript/WebAssembly emulator frontend and publishes a supported-systems list. Its repository says a PSP beta is not ready for daily use and its license is GPL-3.0-or-later. [Fact: S14, S15.] That makes it valuable as a compatibility/provisioning reference and as a candidate to evaluate in a quarantined spike—not a blanket browser-emulation dependency. Libretro/RetroArch-derived browser packaging needs the same per-core version, save-path, performance, and licensing validation as any native adapter.

### Browser-play spike acceptance criteria

1. One permitted homebrew test title, one simple non-BIOS-dependent system/core, desktop Safari + current Chrome + Firefox where support is claimed.
2. Cold download, interrupted/resumed download, cache hit, cache eviction, and re-download all end with manifest and SHA-256 verification.
3. Controller attach/detach, focus loss, keyboard fallback, reduced-motion/accessibility behavior, and play-surface resize are tested.
4. Persistent-save safe write, offline queue, second-browser/device restoration, deliberate conflict, and browser-storage eviction are observed—not assumed.
5. The threaded and non-threaded behavior is measured with isolation headers on/off; unsupported configurations give a readiness explanation.
6. A license/BOM review covers launcher, core, WASM artifacts, configuration, artwork, and every redistributed file. No ROM or BIOS acquisition/distribution flow is added.

## Anti-Patterns

1. **LiveView as the client protocol.** It prevents offline native clients and makes reconnect behavior accidentally semantic. Use API/domain services as the contract.
2. **Long work owned by a UI process.** LiveView async tasks are useful for presentation; durable imported/transfer jobs need independent supervision, persistence, bounds, and recovery.
3. **A general browser Play button.** A per-item browser readiness matrix is mandatory; hide unsupported play behind a clear reason, not an optimistic button.
4. **Putting emulator paths/core settings/server logic in the shared domain.** Platform adapter facts remain local/client-scoped.
5. **Save-state universality.** Sync only adapter-proven persistent saves; treat save states as local experimental artifacts keyed by exact emulator/core/build/options/content compatibility.
6. **Entire-library browser or client mirroring.** Catalogue sync is cheap; bytes are selected, capacity-aware, hash-verified cache entries.
7. **Using browser storage as the backup promise.** It is an optimization with local loss/eviction risk; canonical save revisions live on the server after acknowledgement.
8. **Embedding an emulator project because it demos well.** First check every core's maturity, thread/isolation needs, legal status, license compatibility, save semantics, and browser matrix.

## Recommended Delivery Order and Repository Consequences

1. **Server domain + `/api/v1` skeleton:** capability handshake, auth/pairing, stable error/idempotency format, library/manifest queries, blob authorization/Range, jobs/read models. Write contract tests that neither LiveView nor Mac code can bypass.
2. **LiveView console:** setup/admin/library/import receipts/job progress/pairing approval, always reconstructible from durable services. This provides self-hosted operability early without defining the protocol.
3. **Mac vertical slice:** native app, pairing, light catalogue, selected download/cache, one adapter, local readiness/launch, persistent save revision/recovery. This is the product proof.
4. **Second adapter/client:** use it to pressure-test API/capability boundaries before extracting an SDK/schema package.
5. **Optional browser-play spike and phase:** only after the Mac path and one adapter are stable; keep its Wasm/core assets and web adapter independently versioned and licensed.

Keep the server and LiveView in one repository/application initially, with one-way dependency flow: `domain ← application services ← delivery (API, web)`. Create the Mac client repository once native signing/lifecycle/adapter work begins. Keep a compact API schema/fixtures directory in the server repo until two clients demonstrate a separate package is worthwhile. Browser-play assets should live in a distinct client module/package with a generated third-party notices/BOM file; never co-mingle core binaries with Phoenix static assets by default.

## Source Ledger

All sources accessed 2026-08-26. **HIGH** means direct official/primary documentation for the stated capability; recommendations and ecosystem inferences are marked **MEDIUM** even when their underlying facts are HIGH.

| ID | Source | Publisher | URL | Supported claim | Confidence |
|---|---|---|---|---|---|
| S1 | Phoenix.LiveView v1.2.10 | Phoenix | https://phoenix-live-view.hexdocs.pm/Phoenix.LiveView.html | HTTP-to-stateful lifecycle, reconnect/remount, streams, uploads, async task constraints, untrusted client data | HIGH |
| S2 | Phoenix file uploads | Phoenix | https://hexdocs.pm/phoenix/file_uploads.html | Conventional multipart upload versus LiveView-specific upload path | HIGH |
| S3 | Gamepad API | MDN / Mozilla | https://developer.mozilla.org/en-US/docs/Web/API/Gamepad_API | Browser gamepad interface and compatibility surface | MEDIUM |
| S4 | Using Service Workers | MDN / Mozilla | https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API/Using_Service_Workers | Service-worker cache/offline mechanism | MEDIUM |
| S5 | Storage API | MDN / Mozilla | https://developer.mozilla.org/en-US/docs/Web/API/Storage_API | Storage persistence/quota interface | MEDIUM |
| S6 | SharedArrayBuffer | MDN / Mozilla | https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/SharedArrayBuffer | Shared memory security gating | MEDIUM |
| S7 | Cross-origin isolation | MDN / Mozilla | https://developer.mozilla.org/en-US/docs/Web/API/Window/crossOriginIsolated | Isolation state/requirements used by security-gated features | MEDIUM |
| S8 | IndexedDB API | MDN / Mozilla | https://developer.mozilla.org/en-US/docs/Web/API/IndexedDB_API | Browser structured persistent storage | MEDIUM |
| S9 | COOP header | MDN / Mozilla | https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cross-Origin-Opener-Policy | COOP role in cross-origin isolation | MEDIUM |
| S10 | Game Controller | Apple | https://developer.apple.com/documentation/gamecontroller | Native Apple controller framework | HIGH |
| S11 | Notarizing macOS software before distribution | Apple | https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution | macOS distribution notarization | HIGH |
| S12 | Tauri v2 shell plugin | Tauri | https://v2.tauri.app/plugin/shell/ | Capability-scoped process/shell integration and distribution docs | HIGH |
| S13 | API versions | GitHub Docs | https://docs.github.com/en/rest/about-the-rest-api/api-versions | Additive versus breaking change/versioning discipline | HIGH |
| S14 | EmulatorJS repository README | EmulatorJS | https://github.com/EmulatorJS/EmulatorJS | Self-hosted web emulation prior art, published system matrix and beta caveat | MEDIUM |
| S15 | EmulatorJS LICENSE | EmulatorJS | https://github.com/EmulatorJS/EmulatorJS/blob/main/LICENSE | GPL-3.0-or-later license | HIGH |
| S16 | Electron process model | Electron | https://www.electronjs.org/docs/latest/tutorial/process-model | Main/renderer process model | HIGH |
| S17 | Electron code signing | Electron | https://www.electronjs.org/docs/latest/tutorial/code-signing | macOS signing/notarization and Keychain-related behavior | HIGH |

## Open Questions Requiring Empirical Work

- Which first emulator and system offers a controlled persistent-save path and acceptable native sandbox/notarization shape? Prefer a no-proprietary-BIOS homebrew test case for the spike.
- Does the intended Mac distribution use App Store constraints, direct notarized distribution, or both? Do not choose sandbox/adapter permissions without a measured launch spike.
- What user/household authorization model is needed beyond a single owner? This changes device pairing and browser-console roles but not the `/api/v1` boundary.
- Is direct object-store transfer needed after the first demo? Keep server-proxied, bounded streaming until transfer interruption/cleanup data requires multipart or signed URLs.
- Browser play: which exact core, license, desktop browser set, title size, and save format meets the acceptance criteria? No browser-play feature should be planned before those answers exist.
