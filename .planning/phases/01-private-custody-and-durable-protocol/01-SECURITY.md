---
phase: 01
slug: private-custody-and-durable-protocol
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
block_on: high
created: 2026-08-28
---

# Phase 01 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.
> Register authored at plan time (8 PLAN `<threat_model>` blocks); verified retroactively by `gsd-security-auditor` at ASVS L1 grep-depth against `playstead-server/`.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Internet/LAN → Caddy | Only container publishing host ports; terminates TLS | Raw TLS, all client traffic |
| Caddy → Phoenix app | Reverse-proxied on the internal compose network | HTTP + `x-forwarded-for` (the only trusted source of requesting IP) |
| Anonymous browser → `/setup`, `/log-in`, recovery routes | Untrusted claim/credential submission | Setup token, password, recovery code |
| Host operator → container stdout/env / release commands | Root of trust for secrets, setup token, reset URL | Secrets, single-use tokens |
| Unpaired client → pairing request / redemption endpoints | Fully untrusted; must present the self-generated `device_code` | Claimed device fields, `device_code` |
| Paired device → authenticated `/api/v1` (`hello`, mutating routes, `/changes`, `/snapshot`) | Credential-bearing; `Idempotency-Key`, `command_id`, cursor are client-supplied | Device credential, opaque cursor, capability declaration |
| Owner console (LiveView) → domain contexts | Authenticated, `%Scope{}`-bound, sudo-gated commands | Approve/deny/revoke/rotate, session revocation |
| Client-claimed fields → console rendering | Attacker-controlled strings reach the owner's screen | Device name, platform, self-report |
| Caddy CA volume → console fingerprint display | Trust anchor a Mac will pin | CA root fingerprint |
| Journal partition → per-owner reads | Isolation boundary between owners' change feeds | Change entries, tombstones |
| Container → named volumes (`playstead_db`, `playstead_blobs`) | Durable library storage | All persisted data |
| Repository build context → builder image → runner image | Only the compiled release crosses into the runtime image | Docs runbooks, source tree |
| Unauthenticated browser → `GET /docs/recovery` | Public recovery runbook | Host-shell-gated procedures only |

---

## Threat Register

All evidence paths are relative to `playstead-server/`.

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-01-01 | Information Disclosure | `/api` error paths | high | mitigate | `plugs/api_problem_handler.ex:28-73` wraps router `call/2` (`router.ex:10`); RFC 9457 envelope + random correlation ID `problem.ex:28-51`; registry `error_codes.ex` | closed |
| T-01-02 | Information Disclosure | `/healthz` | medium | mitigate | `controllers/health_controller.ex:15-25` — `%{status: "ok"\|"unavailable"}` only | closed |
| T-01-03 | Spoofing / Tampering | Transport | high | mitigate | `Caddyfile:27-29` automatic HTTPS; `readiness.ex:146-183` never labels plain-HTTP/external-proxy secure; `docs/DEPLOY.md` | closed |
| T-01-04 | Elevation of Privilege | Postgres | high | mitigate | `docker-compose.yml:2-17` db has no `ports:`; app publishes nothing; `release.ex:161-195` `assert_no_placeholder_secrets!/0` called from `application.ex:21` | closed |
| T-01-05 | Tampering | Container images | high | mitigate | `docker-compose.yml:3,49` `postgres:17.2`, `caddy:2.10`; `Dockerfile:20-25` pinned ARGs; no `latest` | closed |
| T-01-06 | Denial of Service | Migration on boot | medium | mitigate | `release.ex:34-66` raises on failure; `:206-230` `assert_minimum_upgradable_version!/0`; both in `application.ex:21-23` | closed |
| T-01-07 | Repudiation | Deployment state | low | accept | AR-01 | closed |
| T-01-SC-a | Tampering | hex.pm installs (plan 01-01) | high | mitigate | `01-RESEARCH.md:138` Package Legitimacy Audit; `phx_gen_auth` absent from `mix.exs`/`mix.lock` | closed |
| T-01-08 | Elevation of Privilege | `/setup` claim window | critical | mitigate | `setup.ex:63-77,135-145` 256-bit token, SHA-256 hash-only; `plugs/require_setup_open.ex:13-15` literal 404; `router.ex:57-59,96-100` | closed |
| T-01-09 | Elevation of Privilege | Concurrent setup claims | high | mitigate | `setup.ex:93-118` single `Ecto.Multi`, `count == 1` guard → `:token_already_used` | closed |
| T-01-10 | Spoofing | Password authentication | high | mitigate | `accounts/user.ex:127,142-146` bcrypt + `no_user_verify`; generic copy `controllers/user_session_controller.ex:13-15,40-50` | closed |
| T-01-11 | Information Disclosure | Recovery codes | high | mitigate | `accounts.ex:128-135,146-170` per-code bcrypt, consume-once, no plaintext read path; shown once `live/setup_live.ex:235-252` | closed |
| T-01-12 | Information Disclosure | Setup token in logs | medium | accept | AR-02 | closed |
| T-01-13 | Tampering | Readiness HTTPS reporting | medium | mitigate | `tls_trust.ex:45-58` four states; `readiness.ex:153-183` plain-HTTP explicitly "not secure" | closed |
| T-01-14 | Spoofing | Session cookie theft | high | mitigate | `endpoint.ex:13-18,76` `http_only`, `same_site: "Lax"`, `secure` set by Plug on HTTPS (`user_auth.ex:23-27`); DB tokens `accounts.ex:273-330`; revoke UI `live/sessions_live.ex:53-77` | closed |
| T-01-15 | Elevation of Privilege | Dangerous console actions | high | mitigate | `plugs/sudo_mode.ex:41-49,66-78`; `router.ex:253-264`; device revoke `live/devices_live.ex:181-195` | closed |
| T-01-16 | Spoofing | Credential brute force | high | mitigate | `plugs/throttle.ex:31-71` per-IP + per-account; `router.ex:72-86`; sudo posts to throttled `/log-in` (`live/sudo_live.ex:42-44`) | closed |
| T-01-17 | Elevation of Privilege | Reset-URL interception | high | mitigate | `release.ex:115-134` hashed single-use token, `delete_all_sessions` in same transaction, stdout only | closed |
| T-01-18 | Repudiation | Credential-affecting events | medium | mitigate | `audit_log.ex` exposes only `record/3`, `list/2`, `list_by_subject/1`; callers `accounts.ex:167,187,327`, `release.ex:128`, `user_session_controller.ex:33` | closed |
| T-01-19 | Information Disclosure | Session client labels | low | mitigate | `accounts/user_token.ex:29-30,55-65` nil label when unrecognized; generic render `live/sessions_live.ex:53-77` | closed |
| T-01-20 | Denial of Service | Throttle lockout of owner | medium | accept | AR-03 | closed |
| T-01-21 | Elevation of Privilege | Display-code guessing | critical | mitigate | `pairing.ex:294-303` hashed `device_code` via `secure_compare`; `display_code` never in a lookup/authz predicate | closed |
| T-01-22 | Elevation of Privilege | Auto-approval of lone pending request | critical | mitigate | `pairing.ex:198,204` `approve/2` and `transition/4` require `%Scope{user: user}` | closed |
| T-01-23 | Elevation of Privilege | Concurrent redemption | high | mitigate | `pairing.ex:270-276,306-322` guarded update, `count == 1`; 409 at `controllers/api/v1/pairing_controller.ex:79-83` | closed |
| T-01-24 | Tampering | Approving an expired request | high | mitigate | `pairing.ex:166` re-derives; `:211` re-checks `effective_status == "pending"` at approval | closed |
| T-01-25 | Information Disclosure | Credential leakage into logs/URLs | high | mitigate | `pairing.ex:654-661` hashed; `plugs/device_auth.ex:34-35` header-only; `config/config.exs:114` `filter_parameters`; prefix only `live/devices_live/device_row.ex:6-7,141` | closed |
| T-01-26 | Spoofing | Forged requesting IP on the evidence card | medium | mitigate | `plugs/client_ip.ex:36-42` trusts first `x-forwarded-for` when `:trust_proxy_headers` (default `true`, `config/runtime.exs:84`); safety depends on compose topology; `release.ex:246` only warns. See WR-02 in 01-REVIEW.md | open — below high threshold (non-blocking) |
| T-01-27 | Denial of Service | Pending-queue flooding | medium | mitigate | Per-IP limit `router.ex:28-30,110-114`; cap + audited eviction `pairing.ex:94-97,152` | closed |
| T-01-28 | Repudiation | Pairing lifecycle | medium | mitigate | Audit entries `pairing.ex:98,152,218,315,530`; `pairing/rotation_audit_worker.ex:20` | closed |
| T-01-29 | Elevation of Privilege | Cross-scope device access | high | mitigate | `pairing.ex:518-520,543-547,555-558` `owned_device/2` scoping; foreign-scope test `test/playstead/pairing_test.exs:188` (explicit negative test covers `list_devices/1` only) | closed |
| T-01-30 | Spoofing | Approval evidence card | critical | mitigate | `live/devices_live/approval_card.ex:65-90` "(claimed)" labels, muted, `truncate`, `max-w-[16ch]` | closed |
| T-01-31 | Tampering | Client-side expiry countdown | high | mitigate | Server re-check `pairing.ex:211`; expired flash `live/devices_live.ex:212-222` | closed |
| T-01-32 | Elevation of Privilege | Device revocation via hijacked session | high | mitigate | `live/devices_live.ex:178-195` requires `Accounts.sudo_mode?/1`; console has no rotate action (rotate is device-API only) | closed |
| T-01-33 | Information Disclosure | Credential exposure in console | high | mitigate | `live/devices_live/device_row.ex:6-7,141` renders `active_credential_fingerprint/1` only | closed |
| T-01-34 | Tampering | Adversarial claimed device name | medium | mitigate | HEEx escaping + truncation (`approval_card.ex:67-90`); `pairing/device.ex:48,59` `validate_length` | closed |
| T-01-35 | Spoofing | CA fingerprint substitution | high | mitigate | `tls_trust.ex:16,80-106` server-side SHA-256 from read-only `caddy_data` (`docker-compose.yml:45`); `require_authenticated` `/devices` (`router.ex:243-250`) | closed |
| T-01-36 | Repudiation | Console-issued pairing commands | medium | mitigate | `live/devices_live.ex:184,205-207` call `Pairing.approve/deny/revoke_device` only | closed |
| T-01-37 | Tampering | Idempotency-key replay | high | mitigate | `idempotency.ex:60-80,91-118` fingerprint + one `Ecto.Multi`; 422 `plugs/idempotency.ex:58-62`; unique index in `20260827200000_create_idempotency_receipts.exs:23` | closed |
| T-01-38 | Information Disclosure | Cross-device receipt replay | high | mitigate | `idempotency.ex:61` keyed on `device_id` + key; composite unique index; `plugs/idempotency.ex:45` | closed |
| T-01-39 | Denial of Service | Receipt-store growth | medium | mitigate | `idempotency.ex:23,131-146` 90-day horizon; `idempotency/prune_expired_worker.ex`; `config/config.exs:53` `@daily` | closed |
| T-01-40 | Tampering | Capability declaration as privilege claim | medium | mitigate | No `Negotiation.`/`verdict` reads in `plugs/`, `user_auth.ex`, `pairing.ex`; informational render `controllers/api/v1/hello_controller.ex:28-36` | closed |
| T-01-41 | Denial of Service | Capability lockout deadlock | medium | mitigate | `router.ex:102-106` `/api/v1/capabilities` on plain `:api` pipeline; hello never halts on `incompatible` | closed |
| T-01-42 | Tampering | Forged / colliding `command_id` | medium | mitigate | `command_id.ex:14-32` v7 version+variant; enforced `pairing.ex:456`; unique index `20260827210000_add_command_id_to_device_credentials.exs:15` | closed |
| T-01-43 | Information Disclosure | Stored response bodies in receipts | medium | mitigate | Receipts carry `device_id`; credentials only leave at redemption, never on an idempotent route | closed |
| T-01-44 | Tampering | Cursor forgery | high | mitigate | `sync/cursor.ex:26-50` HMAC-SHA256 + `secure_compare`, payload is `seq` only; partition via `sync.ex:39-47` | closed |
| T-01-45 | Information Disclosure | Cross-owner journal leakage | high | mitigate | `sync/change_journal.ex:105-113` `where user_id`; `user_id` from `device.user_id` (`changes_controller.ex:18`); `test/playstead/sync/change_journal_test.exs:85` | closed |
| T-01-46 | Tampering | Cursor-gap lost update | high | mitigate | `change_journal.ex:12-30,66,88-95` advisory xact lock; `sync.ex:51-57` `seq > cursor`; `sync/snapshot.ex:82-101` REPEATABLE READ; `snapshot_concurrency_test.exs` | closed |
| T-01-47 | Information Disclosure | Tombstone payload leakage | medium | mitigate | `change_journal.ex:61-62` `tombstone/3` writes `%{}`; `pairing.ex:535` | closed |
| T-01-48 | Denial of Service | Unbounded journal growth | medium | mitigate | `sync/compaction.ex:29,38-41,66` horizon + `oldest_surviving_seq/0`; `sync.ex:63-68` 410; `config/config.exs:56` | closed |
| T-01-49 | Denial of Service | Expensive snapshot reads | medium | accept | AR-04 | closed |
| T-01-50 | Repudiation | Silent client/server divergence | high | mitigate | `test/playstead_web/controllers/api/v1/convergence_test.exs` | closed |
| T-01-51 | Denial of Service | Docker builder `RUN mix compile` | high | mitigate | `Dockerfile:61` `COPY docs docs` before `:64` compile; `test/playstead/docker_build_context_test.exs:17,97-103` | closed |
| T-01-52 | Information Disclosure | `COPY docs docs` into builder | medium | mitigate | `docs/` holds three runbooks only; `Dockerfile:100` runner copies release only; `.dockerignore:23,30,35,36` | closed |
| T-01-53 | Tampering | `/docs/recovery` served content | medium | mitigate | `controllers/recovery_docs_controller.ex:14-16` `@external_resource`; byte-comparison `recovery_docs_controller_test.exs` | closed |
| T-01-54 | Information Disclosure | Unauthenticated `GET /docs/recovery` | low | accept | AR-05 | closed |
| T-01-SC-b | Tampering | Package installs (plan 01-08) | n/a | accept | AR-06 — no new dependency in `mix.exs`/`mix.lock` | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-01 | T-01-07 | Phase 1 has no operator audit surface beyond container logs; per-component health and diagnostics land in Phase 5 (OPER-03, QUAL-03) | 01-01-PLAN.md threat model | 2026-08-28 |
| AR-02 | T-01-12 | Setup token is deliberately printed to stdout (Jupyter-pattern bootstrap); host access is the documented root of trust (D-03, D-05); mitigated by single-use semantics and hash-only storage | 01-02-PLAN.md threat model | 2026-08-28 |
| AR-03 | T-01-20 | Fixed throttle limits with a short window chosen over adaptive lockout (D-06); host-side reset command is an out-of-band path no network attacker can throttle | 01-03-PLAN.md threat model | 2026-08-28 |
| AR-04 | T-01-49 | Phase 1 snapshots cover only device and pairing rows on a single-owner server; revisit when the catalogue producer lands in Phase 2 | 01-07-PLAN.md threat model | 2026-08-28 |
| AR-05 | T-01-54 | The recovery runbook documents only host-shell-gated procedures; gating it behind login would make it unreachable when needed | 01-08-PLAN.md threat model | 2026-08-28 |
| AR-06 | T-01-SC-b | Plan 01-08 installs no packages; nothing for the package-legitimacy gate to audit | 01-08-PLAN.md threat model | 2026-08-28 |

*Accepted risks do not resurface in future audit runs.*

---

## Open Items (non-blocking)

| Threat | Severity | Gap | Recommended follow-up |
|--------|----------|-----|-----------------------|
| T-01-26 | medium | `ClientIp` trusts a client-controllable `x-forwarded-for` by default; the safety property (only Caddy publishes ports) is topological and unverified at runtime. Forged IPs would also evade the per-IP throttles keyed on `:client_ip` (`plugs/throttle.ex:63-66`). Already tracked as WR-02. | Either (a) resolve `x-forwarded-for` only when `conn.remote_ip` is inside the trusted proxy CIDR (e.g. `remote_ip` library with the compose subnet), or (b) turn the boot-time warning into a refusal when `PLAYSTEAD_PROXY` is unset in prod, or (c) document and accept here. |

Observations carried forward (no disposition change): T-01-29's explicit foreign-scope negative test covers `list_devices/1` only — `rename_device/3` and `revoke_device/2` share the verified `owned_device/2` filter but lack their own negative test. T-01-32's rotation clause is vacuous because the console exposes no rotate action; any future console-side rotate must route through the same `Accounts.sudo_mode?/1` gate used by `handle_event("revoke", …)` at `live/devices_live.ex:181`.

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-08-28 | 56 | 55 | 1 (0 blocking) | gsd-security-auditor via /gsd-secure-phase |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed (1 medium-severity open item below the `high` block threshold)
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-08-28
