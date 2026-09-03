---
id: SEED-025
status: dormant
planted: 2026-09-03
planted_during: v1.0 / Phase 04 (Persistent Save Continuity) planning — owner's first real setup run
trigger_when: when revisiting authentication, planning household/multi-user support, or before the email-free recovery design ossifies further
scope: medium-to-large for SSO; the credential-UX affordances are small and independently shippable
related: SEED-004 (household player profiles), SEED-024 (first-run TLS trust experience)
---

# SEED-025: Evaluate SSO (sigra) and close the credential-UX gaps it would also fix

## Why This Matters

Playstead's auth today is deliberately narrow and deliberately email-free:
password login, sudo-mode re-authentication for destructive actions, one-time
recovery codes, and a setup-token bootstrap. That was the right v1 scope — it
has no external dependency, no mail server, and no third-party identity provider
in the critical path of a self-hosted private server.

Two things now push on it:

1. **SSO.** The owner maintains `sigra`, his own open-source authentication
   library for Phoenix, published on hex.pm. Adopting it would replace
   hand-rolled auth surface with a maintained one, and would plausibly bring
   SSO/OIDC along with it. For a self-hoster who already runs an identity
   provider — or a household where several people need distinct logins — that
   is a real ergonomic win, and it converges with SEED-004's household player
   profiles.
2. **The credential-UX gaps are visible right now.** During his first real
   setup run the owner immediately noticed that the recovery-codes screen has
   **no copy-to-clipboard or download affordance** — the codes are rendered in a
   grid, shown exactly once, and never displayed again. His own framing
   connected the two: *"if we migrate to sigra that would be fixed for us
   anyway hopefully."* Maybe — but the gap is small, concrete, and shippable
   independently of any auth migration, and it should not wait on one.

The tension worth thinking about explicitly: **SSO and self-hosted custody pull
in opposite directions.** The entire product premise is that your library lives
on your server, under your control, recoverable without anyone else's
cooperation. An external identity provider inserts a dependency into the login
path — if the IdP is down, or the subscription lapses, or the tenant is deleted,
can you still reach your own library? Any SSO design must keep a local
break-glass credential that works with no network and no third party. That is
the same instinct behind the email-free recovery design, and it should not be
weakened.

## Questions to Explore

- **What does `sigra` actually provide** — session management, password
  hashing, MFA, OIDC/SAML client, IdP capability? Which parts of the existing
  hand-rolled surface (`Accounts`, sudo-mode, throttling, recovery codes, audit
  log) does it replace versus merely sit beside? Is a partial adoption sane, or
  is it all-or-nothing?
- **Migration cost against a shipped Phase 1.** Owner accounts, sessions,
  recovery codes, the sudo pipeline, the audit log, and the pairing ceremony all
  currently key off `Accounts`. What is the blast radius, and does it disturb
  the device-pairing credential path (which is header-only and deliberately
  separate from browser sessions)?
- **Break-glass invariant.** Whatever ships, a local credential must reach the
  console with no internet and no IdP. Can that be stated as a testable
  prohibition — the same shape Phase 4 uses in `must_haves.prohibitions`?
- **Does SSO imply multi-user?** Today there is one owner. SEED-004 wants
  household profiles. SSO without a real multi-user model may be premature; with
  one, it is the natural front door. Sequence them together.

### Concrete, shippable now (independent of any SSO decision)

- **Copy-to-clipboard on the recovery-codes screen** (`setup_live.ex`,
  `render_step_3/1`) — codes are shown exactly once; the absence of a one-click
  copy is what makes people screenshot them or mistype them into a password
  manager.
- **Download-as-file** for the same codes, so they can be dropped into a
  password manager or printed.
- **Say that regeneration exists.** `POST /settings/recovery-codes/regenerate`
  already exists behind sudo, but nothing on the setup screen tells the user
  that fumbling the codes now is recoverable. One sentence removes a genuine
  moment of panic.

## When to Surface

Surface the **credential-UX affordances** whenever there is appetite for a small
UI change — they are self-contained, and the setup screen is a first-impression
surface (see SEED-024 for the other half of that first impression).

Surface **SSO** when revisiting authentication properly, most naturally
alongside SEED-004's household profiles. It is explicitly not v1.0 work: the
current auth is adequate for a single owner, and replacing shipped, tested auth
mid-milestone trades real safety for ergonomics nobody has asked for yet.

## Notes

Raised by the owner during his first real setup run on a clean stack, after
completing the wizard and reaching `/devices`: *"should we at some point support
SSO for this? ... maybe using sigra? hex.pm sigra published by szTheory — that's
my open-source auth thing for Phoenix. Also shouldn't the recovery codes thing
have a little copy-to-clipboard easy UI affordance."*

Current state for whoever picks this up: recovery codes render in
`lib/playstead_web/live/setup_live.ex` `render_step_3/1` as a two-column grid of
`<.code_display>` components inside `#recovery-codes`, with a Continue button
and no copy, download, or print affordance. Regeneration lives at
`PlaysteadWeb.RecoveryCodesController.regenerate/2`, routed at
`router.ex:447` behind `:require_sudo`.
