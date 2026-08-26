<!-- GSD:project-start source:PROJECT.md -->

## Project

**Emu Server**

Emu Server is the working name for an open-source, self-hostable personal game-library and continuity system. It gives people a polished way to import user-supplied ROMs, understand exactly what happened to their files, browse and play through integrated clients, keep persistent saves safe across devices, and export everything without lock-in.

The first proof is one excellent Mac-to-server experience. The long-term vision is a platform-neutral protocol and family of clients for Mac, Windows, Linux, Steam Deck, PSP/Vita-class homebrew devices, arcade and living-room systems, and the web where technically appropriate.

**Core Value:** A locally available game and its progress remain effortless to play, safe, understandable, synchronized, and fully under the user's control.

### Constraints

- **Content posture**: User-supplied, private content only — do not distribute, locate, or facilitate acquisition of copyrighted ROMs or proprietary BIOS files.
- **Data ownership**: Preserve exact original bytes and provide documented, verified export — convenience cannot create lock-in.
- **Repository safety**: Distinguish canonical storage from independent backup copies and display their health — centralization must reduce rather than concentrate the risk of disk loss.
- **Reliability**: Never silently discard save conflicts or mutate imported source data — progress and provenance are trust-critical.
- **Offline**: A verified locally cached game must remain launchable without optional network services — network enrichment stays off the critical path.
- **Compatibility**: State support in terms of explicit client/emulator/core/system/version matrices — do not market aspirational universal compatibility.
- **Security**: Treat uploaded files, archives, metadata, filenames, emulator output, and parsers as untrusted — use validation, quotas, bounded workers, and isolation.
- **Operations**: Optimize for an opinionated low-administration deployment while preserving documented advanced adapters — the happy path is intentionally narrow.
- **Architecture**: Build domain contracts before splitting repositories; integrate mature emulators and services behind adapters; avoid cyclic dependencies and infrastructure leakage into the core domain.
- **Technology**: Elixir/Phoenix server is the strong default; Mac client technology and emulator adapter are decided by experiential spikes.
- **Delivery boundary**: Phoenix LiveView is the built-in web experience, not the durable client protocol; native clients must converge through API state after disconnects and missed notifications.
- **Naming**: `emu-server` is temporary until the product/protocol boundary survives the Mac spike.
- **Commercialization**: Hosting is not a configuration toggle — it requires separate legal, policy, security, tenant, cost, and SRE readiness.

<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->

## Technology Stack

## Decision Status

| Status | Meaning | Decisions |
|---|---|---|
| **Committed platform** | Safe to design against now | Elixir/Phoenix, PostgreSQL, local-filesystem object store, `/api/v1`, Phoenix LiveView console, native SwiftUI Mac client boundary, container release path. |
| **Recommended default** | Add when its named problem exists | Ecto/Postgrex, Oban, OpenApiSpex, Telemetry/OpenTelemetry, ExUnit/StreamData, Docker Compose. |
| **Spike decision** | Must be proved empirically before adoption | First emulator/system adapter; Mac sandbox/distribution model; `tus` versus S3 multipart; direct object-store transfers; archive inspection sandbox; remote S3 provider. |
| **Deferred** | Do not add to the first proof | Browser emulation, multi-tenant hosting, a separate SDK/schema repo, web sockets/SSE as semantic transport, MinIO deployment, Redis, Kubernetes. |

## Recommended Stack

### Core Technologies

| Technology | Baseline at research date | Purpose | Why recommended |
|---|---:|---|---|
| **Elixir + OTP** | Resolver-selected supported release | Server runtime and supervision | Fits the owner ecosystem and is well suited to concurrent, fault-contained workflow coordination. Supervision is a recovery mechanism, not durable-job state. |
| **Phoenix** | `1.8.12` verified in Hex | HTTP application, API delivery, releases | One application can ship a secure conventional HTTP API and the admin console without inventing a separate backend. Keep all client semantics in application services, not controllers. |
| **Phoenix LiveView** | `1.2.10` verified in Hex | First-party setup, administration, import, library, pairing and job-status console | Gives a polished server-rendered console, but it is expressly not the native-client protocol or owner of long-running work. Reload/reconnect must reconstruct state from durable services. |
| **PostgreSQL** | `18.6` verified current minor | Transactional metadata, authorization, change journal, idempotency receipts, save heads/revisions and job state | The canonical source of durable coordination. PostgreSQL maintains a current-minor policy and supports strong relational constraints required for custody, provenance and conflict handling. |
| **Ecto SQL + Postgrex** | Phoenix-generator compatible versions | Database mapping, migrations and PostgreSQL driver | Use the Phoenix-supported defaults; model immutable blobs, manifests, imports, commands, job records and save revisions relationally. Do not hide domain invariants in database callbacks or storage adapters. |
| **Local filesystem object-store adapter** | Project-owned interface, no package | Canonical immutable blob bytes on a mounted persistent volume | The lowest-risk first deployment: exact-byte custody and backup/restore can be proven before cloud transfer complexity. The interface must support a later S3-compatible implementation without changing the client protocol. |
| **Docker Compose + OTP release** | Compose Spec/current base images validated at build | One documented self-hosted deployment path | Package one production release, Postgres, persistent named/bind volumes, health endpoints and explicit backup/restore/upgrade instructions. Pin image digests in release artifacts, never `latest`. |

### Supporting Libraries

| Library | Baseline at research date | Purpose | When to use |
|---|---:|---|---|
| **Oban** | `2.24.0` verified in Hex; Apache-2.0 | Durable PostgreSQL-backed background work | Adopt for imports, hashing coordination, recognition, reconciliation, retention and backup verification. Persist work intent/outcome, use bounded queues and idempotent workers; do not place raw CPU- or parser-heavy work unbounded in a BEAM process. |
| **OpenApiSpex** | `3.22.3` verified in Hex; MPL-2.0 | OpenAPI 3 contract, request validation and generated API documentation | Use for `/api/v1` schemas, checked examples and contract fixtures. Keep a hand-written small Swift transport client; do not generate the Mac domain model from Phoenix. Review MPL-2.0 notice/source obligations before distribution. |
| **Telemetry** | Phoenix/Erlang ecosystem default | Metrics/events boundary | Instrument domain commands, jobs, storage operations, API latency and resource limits with privacy-safe fields. Never log ROM filenames, content hashes, save bytes or authorization tokens by default. |
| **OpenTelemetry Erlang + exporter** | Resolve only after chosen collector/exporter | Distributed traces/metrics export | Add after baseline telemetry proves useful. Trace request → command → job → storage using correlation IDs, sampled and scrubbed; an OTLP collector is preferred over application-specific SaaS lock-in. |
| **Swoosh** | Resolver-selected compatible version | Optional transactional email | Only if pairing/recovery notifications actually need email. No hosted-email provider is a v1 dependency. |
| **ExUnit + StreamData + Mox** | Resolver-selected compatible versions | Unit/property/contract tests and boundary fakes | Use property tests for manifests, idempotency, cursor convergence, path containment and export/import byte preservation; use fakes at storage, matcher and adapter seams. |
| **Dialyzer/PLT and Credo** | Toolchain-selected | Static analysis and style guardrails | Run in CI after the application boundary exists; do not block the first vertical slice on speculative type coverage. |

### Protocol and Delivery Defaults

| Concern | Default | Rationale |
|---|---|---|
| Native-client API | Versioned HTTPS JSON control plane at `/api/v1`; standard HTTP byte endpoints | Supports offline/retryable clients and ordinary `Range` downloads without a persistent socket. |
| Contract | OpenAPI schemas, checked examples, contract fixtures and compatibility matrix | Additive fields are optional; removals/new requirements get a new major representation or published migration/sunset path. |
| Mutations | `Idempotency-Key`, persisted command receipt and durable job ID | Enables safe replay after an app, browser, socket or network failure. |
| Client convergence | Cursor-based `/changes` journal with snapshot/reset semantics; polling/long-poll first | A missed notification cannot cause divergent state. SSE/WebSocket may later be a hint only. |
| Blob transfer | Server-proxied streaming first; immutable blob ID + SHA-256 + byte size + `Range`/conditional requests | Keeps credentials server-side and makes end-to-end verification explicit. Spike resumable upload before large/remote collection imports. |
| Object storage | Storage behaviour behind an application-owned port; local disk first, S3-compatible adapter later | Avoids R2-, MinIO- or AWS-specific client semantics. A remote provider is an operational adapter, not the protocol. |

### Native Mac Client Boundary

| Technology | Baseline | Responsibility | Boundary rule |
|---|---|---|---|
| **SwiftUI with focused AppKit** | Current Xcode/macOS SDK validated in the Mac spike | Mac UI, accessibility, local read models, controller UX, cache presentation | Choose native APIs to test the actual filesystem, Keychain, controller, signing and process-launch constraints. Use AppKit only where SwiftUI lacks required behaviour. |
| **URLSession + Keychain + Game Controller** | Apple SDK, validated in spike | HTTPS client/Range transfer, credentials, controller input | Secrets stay in Keychain. Controller/device mapping and cache paths are client-local, never server domain data. |
| **Adapter host** | Project-owned protocol, one adapter first | Discover → materialize → preflight → launch → observe safe save flush → collect persistent save revision | Emulator paths, BIOS materialization, core options and process lifecycle stay out of Phoenix and out of the common API schema. Prove one legal homebrew test configuration before committing an emulator dependency. |

## Installation Shape

# Performed only after the phase validates the current generator/toolchain.

# Add only the capabilities that are being built.

## Alternatives Considered

| Recommended | Alternative | When to use the alternative |
|---|---|---|
| Phoenix API + LiveView console | SPA plus separate API service | Only when two independently deployed web clients demonstrate a real lifecycle/team boundary; v1 would pay duplicate auth, deployment and state complexity. |
| PostgreSQL | SQLite | A disposable single-user local prototype may use SQLite, but the actual server needs durable concurrent jobs, change journals, operational backup drills and a supported self-hosted path. |
| Local disk first + S3-compatible port later | Direct MinIO/R2/S3 deployment from day one | After a transfer/backup/restore spike proves a specific provider, lifecycle policy, credential model, cost and license/terms posture. Do not infer MinIO licensing from old community guidance. |
| Server-proxied streaming then spike | `tus` or S3 multipart immediately | Use either only after interruption, cleanup, checksum and authorization tests demonstrate the need. Never invent a partial-upload protocol. |
| Oban | Ad-hoc `Task.async`/GenServer queues | Only for short, non-durable presentation work. User-visible import, reconciliation and verification work must survive navigation/restarts with persisted identity and outcome. |
| SwiftUI/AppKit native client | Tauri/Electron | Reconsider once cross-platform UI sharing is a measured priority. They add a webview/process bridge exactly where v1 needs to prove native process, filesystem, controller and signing semantics. |

## What Not to Use

| Avoid | Why | Use instead |
|---|---|---|
| LiveView sockets/events as native-client API | Reconnects and UI process lifetime cannot be protocol semantics; native offline clients must converge without a socket. | `/api/v1`, idempotent commands and durable cursor fetch. |
| LiveView tasks for durable imports/transfers | Navigation, crash or reconnect can end UI-owned work. | Oban-backed durable workflow records with bounded execution. |
| Redis, Kafka or a separate queue in v1 | Adds another durable system before Postgres-backed workflow limits are measured. | PostgreSQL + Oban; revisit only with demonstrated throughput/isolation needs. |
| Kubernetes | Increases operational burden and hides the one-container-path promise. | Docker Compose + documented persistent volumes, health, backups and release rollback. |
| An S3 SDK in the first vertical slice | Premature remote credentials and multipart semantics distract from custody/import/export proof. | Local object-store port; spike S3 compatibility later. |
| Browser emulator bundle or GPL emulator frontend dependency | Browser isolation, performance, core licensing and save semantics are separate integration work; a licence can impose distribution obligations. | Defer browser play; use a native adapter spike with a reviewed emulator/core licence. |
| Save-state universality | States are frequently core/build/options/platform-specific. | Explicit adapter-proven persistent-save revisions; scope any experimental state artifact by full compatibility fingerprint. |
| ROM/BIOS catalogue, downloader or acquisition workflow | Outside the user-supplied private-content posture and a material legal/product risk. | A private file importer and BIOS readiness auditor only. |
| User filenames/paths or multipart ETags as object identity | They are mutable or multipart-specific evidence, not content identity. | Full-stream SHA-256 of exact original bytes plus immutable manifests. |

## Version Compatibility and Validation Strategy

| Surface | Rule before merge/release |
|---|---|
| Elixir/OTP/Phoenix/LiveView/Ecto/Postgrex | Generate or resolve once from current official release constraints; commit `mix.lock`; remove unused dependencies, review Hex/OSV advisories, test and release-build on the pinned compiler image. Do not manually combine unverified major versions. |
| PostgreSQL | Pin major `18` and the current supported minor (`18.6` at research); periodically update to the current minor after migration/restore and integration tests. Major upgrade is a planned `pg_upgrade` or dump/restore exercise, never an incidental container-tag change. |
| Oban/OpenApiSpex | Add only alongside their use case; pin compatible resolver output and test migrations, queues and generated OpenAPI fixtures. Recheck their disclosed licenses and notices on each upgrade. |
| Container images | Pin immutable digest in released Compose files; rebuild for security updates; publish SBOM/provenance where feasible. Runtime containers run non-root, with read-only code filesystem and only declared writable volumes. |
| Mac client | Pin Xcode/Swift toolchain in CI and test the claimed macOS support range. Gate release on code signing/notarization, Keychain, offline-cache and adapter contract tests. |
| API | Contract-test OpenAPI examples against Phoenix; native client tests the same fixtures. Maintain explicit server/client compatibility ranges and a deprecation policy. |

## Security, Operations and Release Baseline

- Run the Phoenix release as a non-root container; keep blobs outside the web root on an explicit persistent mount; generate storage keys rather than accepting paths.
- Terminate TLS at the documented deployment boundary; secure browser sessions with CSRF protections; make device pairing, tokens, rate/byte/concurrency limits and audit receipts first-class.
- Treat uploads, filenames, archive headers, metadata and emulator output as untrusted. Begin opaque storage with strict limits; enable archive inspection only in a resource-limited worker after a malicious-corpus spike.
- Publish `/healthz` for liveness and a readiness/health model that separately reports database, object store, job queues, migrations and backup freshness. Do not emit alerts for normal offline client state.
- Make backup a separate, verified copy. Release guidance must include restore drills and migration preflight/rollback; one server volume is not a backup.
- CI should run formatting, compile-with-warnings-as-errors, unit/property/contract tests, dependency advisory/licence review, image scan/SBOM and a production-release smoke test. Add fuzz/adversarial corpus tests before enabling parsers/extractors.

## Source Ledger

| Source | Claim used | Confidence |
|---|---|---|
| [Phoenix on Hex](https://hex.pm/packages/phoenix) | Phoenix `1.8.12` release and MIT licence | HIGH |
| [Phoenix LiveView on Hex](https://hex.pm/packages/phoenix_live_view) | LiveView `1.2.10` release | HIGH |
| [Oban on Hex](https://hex.pm/packages/oban) | Oban `2.24.0`, PostgreSQL-backed jobs and Apache-2.0 licence | HIGH |
| [OpenApiSpex on Hex](https://hex.pm/packages/open_api_spex) | OpenApiSpex `3.22.3`, OpenAPI/Phoenix role and MPL-2.0 licence | HIGH |
| [PostgreSQL versioning policy](https://www.postgresql.org/support/versioning/) | Supported `18.6`, current-minor and major-upgrade policy | HIGH |
| [Phoenix LiveView documentation](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html) | HTTP/reconnect lifecycle and async-work constraints | HIGH |
| [Phoenix file uploads documentation](https://hexdocs.pm/phoenix/file_uploads.html) | Conventional HTTP versus LiveView upload boundary | HIGH |
| [Apple Game Controller](https://developer.apple.com/documentation/gamecontroller) | Native controller integration boundary | HIGH |
| [Apple notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) | Direct-distribution notarization requirement | HIGH |
| [Technical risks discovery](.planning/discovery/TECHNICAL-RISKS.md) | Content identity, transfers, object-storage port, save and archive-security requirements | MEDIUM (synthesis; sources ledger therein) |
| [Web and client architecture discovery](.planning/discovery/WEB-AND-CLIENT-ARCHITECTURE.md) | API-first/LiveView/native-client boundaries and delivery order | MEDIUM (synthesis; sources ledger therein) |

## Research Gaps and Required Spikes

<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:

- `$gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `$gsd-debug` for investigation and bug fixing
- `$gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `$gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
