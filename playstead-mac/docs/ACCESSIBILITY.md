# Accessibility

What the Mac client actually delivers against the QUAL-01 accessibility
floor (03-UI-SPEC.md), and its current, honestly stated limits.

## What is delivered

- **Machine-checked keyboard reachability on the currently inventoried
  surfaces.** `SurfaceAccessibilityTests` independently declares the
  library's cards/list/readiness controls and is configured to traverse them
  in both directions, through wrap, and activate the focused control with
  Space against a launched app. It also covers the contextual adapter,
  readiness, BIOS, and controller-settings routes, including sheet
  containment, Escape/Done dismissal, and opener-focus restoration. Plans 06
  and 07 add curation and storage inventories before Plan 09 performs the
  complete all-surface aggregation. A hosted run is required evidence before
  a release can claim these live checks passed.
- **A visible focus indicator that is never suppressed for keyboard
  users.** `DesignTokens.focusRing` is the one focus-ring color token,
  reused nowhere else (never for a system or a status color).
- **A labeled name for every control and every status.** A card's and a
  list row's accessible name combines the title, the system's display
  name, and the status ladder's full-sentence accessible name — the same
  three facts a sighted user reads, in the same order on both layouts.
- **Every status distinguishable without color alone.** Each
  `LibraryStatus` case exposes its own SF Symbol glyph identifier
  (`LibraryStatus.glyphIdentifier`), and the list view additionally
  shows a text label alongside the glyph — color is decoration, never
  the only signal.
- **A keyboard-and-pointer alternative to every drag interaction.** The
  BIOS drop target accepts a drag, but also exposes a "Choose File…"
  button opening a standard file chooser — a drop target that only
  accepts a drag would exclude anyone who cannot perform one.
- **Reduced motion never removes progress information.** `MotionPreference`
  observes the system's reduce-motion setting and exposes exactly one
  thing: a duration (`morphAndTransitionDuration`) that collapses to
  zero — an instant change — for a completion morph, a directional focus
  transition, or a status crossfade. The determinate download progress
  fraction (`ProgressFillState`) is computed with **no** dependency on
  motion preference at all, so it renders identically whether or not
  reduced motion is on; removing it under reduced motion would trade one
  accessibility need for the loss of the only signal a long download is
  advancing.
- **Full controller lifecycle with no stranding.** `ControllerHost`
  publishes connect/disconnect/assignment state; disconnecting shows a
  quiet, non-modal recovery banner that never disables any other control
  and never blocks keyboard or pointer input to any surface
  (`InputPathAvailability` reports keyboard and pointer as always
  available, independent of controller state).

## Current limits — stated honestly

- **Controller text entry is filter chips only, in this release.**
  `FilterChipRow` is the controller-reachable path to narrowing the
  library by system/availability. Arbitrary free-text search
  (`SearchField`) requires the keyboard — an on-screen keyboard for
  controller text entry is explicitly out of scope for this phase (see
  03-10-PLAN.md's `prohibitions`).
- **The public accessibility audit is machine evidence, not experiential
  VoiceOver review or certification.** `SurfaceAccessibilityTests` is
  configured to launch a deterministic app profile and check stable roles,
  labels, values, finite frames, exact focus behavior, and every supported
  public audit category. Any audit
  exclusion must name one stable identifier, one exact typed fingerprint, and
  a rationale; unmatched issues fail closed. This does not establish speech
  quality, rotor usefulness, navigation intuition, or usability with a human
  VoiceOver workflow, and no third-party conformance certification is claimed.
- **Hosted failure diagnostics remain source-bounded.** Sanitized per-layer
  evidence may name a canonical failed test, a normalized XCTest assertion
  kind, and a repository-relative Swift file and line only when the xcresult
  location resolves to one unique checked-in source name. Runtime assertion
  values, full paths, messages, attachments, environments, and raw xcresults
  never cross the artifact boundary; unmatched diagnostics are omitted.
- **Controller hardware itself remains unproven.** The plan 03-01 spike
  recorded controller connect/disconnect recovery as
  FAIL/unproven — no physical or paired game controller was available in
  the execution environment (03-SPIKE-REPORT.md, probe 5). Every piece
  of `ControllerHost`'s logic is exercised against an injectable
  `ControllerInputSource` with full test coverage; whether real hardware
  behaves exactly as the fake source simulates is a claim this project
  has not yet verified on physical hardware.
