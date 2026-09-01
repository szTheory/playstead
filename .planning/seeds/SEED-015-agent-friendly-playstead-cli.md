---
id: SEED-015
status: dormant
planted: 2026-09-01
planted_during: v1.0 / Phase 03.5 (Mac Verification Automation)
trigger_when: when /api/v1 stabilizes, a second automation consumer appears, or agent/operator workflows need a supported non-GUI interface
scope: medium-to-large — product CLI, stable automation contract, safety model, docs, and distribution
---

# SEED-015: Design an agent-friendly Playstead CLI as a first-class automation client

## Why This Matters

A supported `playstead` CLI would let people, scripts, operators, and future AI
agents inspect and operate Playstead through the same durable API contracts as
native clients. It could make self-hosting, diagnostics, imports, exports,
catalogue queries, storage checks, pairing administration, save history, and
recovery workflows composable without forcing browser automation or direct
database/filesystem access.

The CLI should be a deliberately designed client, not a thin dump of every HTTP
route and not an excuse to expose infrastructure internals. Its value comes from
stable domain verbs, predictable machine-readable results, safe retry semantics,
excellent errors and remediation, and a narrow set of high-value workflows. The
human terminal experience and the agent/automation experience should share the
same commands while using different presentation modes over one result model.

This is also an opportunity to make Playstead agent-accessible without embedding
an LLM, making network inference a dependency, or coupling the product to one
vendor. A future MCP server or agent skill could wrap the CLI or the same client
library after real use demonstrates which tasks deserve higher-level tools.

## Design and Research Questions

### Jobs and domain language

- Inventory the intended users and jobs: owner/operator diagnostics, scripted
  backup/export, catalogue and curation management, device/pairing administration,
  import status, cache/readiness inspection, save recovery, CI fixtures, and
  agent-driven assistance. Do not build commands without a named workflow.
- Keep nouns and verbs aligned with the API and Playstead's ubiquitous language.
  Avoid three names for the same command, receipt, asset, collection, revision,
  device, or readiness state.
- Decide what must remain native-client-local—emulator paths, Keychain details,
  controller mappings, launch/process control—rather than pretending every
  operation belongs to the server CLI.

### Human UX, DX, and agent UX

- Provide concise interactive defaults for humans plus explicit `--json` or
  versioned JSON/JSONL output for automation. Keep stdout parseable and reserve
  stderr for diagnostics; define stable exit codes and error identifiers.
- Support capability/schema/version discovery so an agent can learn what this
  server supports without guessing. Document pagination, cursors, time formats,
  byte units, enum evolution, optional fields, and compatibility ranges.
- Prefer complete task-oriented commands and composable filters over dozens of
  chatty primitives. Consider bounded output, field selection, streaming JSONL,
  and continuation tokens so large libraries do not overwhelm a terminal or an
  agent context window.
- Supply examples, shell completion, man/help pages, a machine-readable command
  catalogue, copyable remediation, and deterministic fixtures. Evaluate whether
  a small read-only discovery command should work before authentication.

### Safety and trust

- Reuse scoped device credentials and `/api/v1`; never read the database or blob
  store directly. Store secrets in an OS credential facility where available,
  never print tokens by default, and make server identity/TLS pinning inspectable.
- Mutations need idempotency keys, durable command receipts, explicit targets,
  bounded waits, and safe retry/resume. Destructive or irreversible actions need
  preview/dry-run where meaningful, a precise effect summary, and deliberate
  confirmation; non-interactive mode must fail closed unless intent is explicit.
- Separate authentication, authorization, integrity, and success. “Request sent”
  is not “job completed”; “downloaded” is not “digest verified”; “queued” is not
  “backed up.” Preserve those distinctions in structured output.
- Add quotas, redaction, audit correlation IDs, cancellation semantics, timeout
  behavior, and defenses against prompt/argument injection through untrusted
  filenames or metadata. Never emit shell-ready commands containing untrusted
  values without robust escaping and clear provenance.
- The CLI must preserve the private user-supplied-content posture: no ROM/BIOS
  search, acquisition, or source-location commands.

### Architecture and prior art

- Compare mature CLIs such as `gh`, `docker`, `kubectl`, `aws`, `fly`, package
  managers, backup tools, and content-addressed systems. Study both successful
  patterns and postmortems around unstable JSON, configuration precedence,
  confirmation bypasses, secret leakage, plugin supply chains, shell quoting,
  output pagination, and command sprawl.
- Evaluate implementation language/distribution only after the supported host
  environments and reuse boundary are clear. Options may include an Elixir
  escript/release, Swift companion tooling, or a small portable client; avoid a
  shared SDK until two real consumers establish the abstraction.
- Decide whether plugins are needed only after core commands prove insufficient.
  A plugin system adds version negotiation, trust/signing, sandboxing, discovery,
  and support burdens that conflict with a KISS first version.

## When to Surface

**Trigger:** when `/api/v1` stabilizes, a second automation consumer appears, or
agent/operator workflows need a supported non-GUI interface.

Surface before agents begin depending on ad-hoc shell scripts, direct SQL, or
unstable internal endpoints. Start with a read-heavy vertical slice—server status,
capabilities, library query, one durable mutation, and one export/verification
workflow—then expand from observed use.

## Scope Estimate

**Medium-to-large.** A useful initial CLI can be one focused phase after the API
and auth contracts are proven. A broad command surface, cross-platform packaging,
plugins, an MCP layer, or autonomous agent workflows are separate later decisions.

## Breadcrumbs

- `.planning/PROJECT.md` — `/api/v1`, durable convergence, capability negotiation,
  content posture, data ownership, and domain-language constraints
- `.planning/ROADMAP.md` — protocol, command-receipt, pairing, catalogue, export,
  storage, readiness, and save workflows the CLI could eventually compose
- `.planning/research/STACK.md` — versioned HTTPS JSON control plane, idempotency
  receipts, cursor journal, OpenAPI, and explicit compatibility policy
- `.planning/research/ARCHITECTURE.md` — delivery clients call application
  services and must not bypass domain/storage boundaries
- `.planning/discovery/LANDSCAPE.md` — existing Steam ROM Manager CLI breadcrumb
- `.planning/seeds/SEED-009-ubiquitous-domain-language-audits.md` — terminology
  consistency across internal, public API, UI, and CLI surfaces

## Notes

Captured during Phase 03.5 from the owner's explicit preference for a future
Playstead CLI that makes the system easier and safer for AI agents to operate.
When surfaced, fan out research across user jobs, agent ergonomics, security,
prior art, packaging, and API boundaries before selecting an implementation.
