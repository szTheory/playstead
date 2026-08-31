# Accessibility

What the Mac client actually delivers against the QUAL-01 accessibility
floor (03-UI-SPEC.md), and its current, honestly stated limits.

## What is delivered

- **Keyboard reachability.** Every interactive element across the
  library, shelves, list view, search, filter chips, storage, downloads,
  collections, adapter settings, the BIOS drop target, the readiness
  report, and controller settings is reachable by keyboard alone, in an
  order matching the visual layout. Tab order is proven equal to
  declared visual order per surface in
  `PlaysteadTests/AccessibilityTests/AccessibilityAuditTests.swift`.
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
- **The audit is an automated tree-walk plus a human check, not a
  third-party conformance assessment.** `AccessibilityAuditTests` walks
  a declarative manifest of each top-level surface's real accessible
  names, traits, and declared order (this test target is headless-only;
  see `FilterChipRow.isSelected`'s doc comment for this codebase's
  established precedent of testing logic over a live rendered tree). No
  formal external accessibility certification is claimed for this
  release.
- **Controller hardware itself remains unproven.** The plan 03-01 spike
  recorded controller connect/disconnect recovery as
  FAIL/unproven — no physical or paired game controller was available in
  the execution environment (03-SPIKE-REPORT.md, probe 5). Every piece
  of `ControllerHost`'s logic is exercised against an injectable
  `ControllerInputSource` with full test coverage; whether real hardware
  behaves exactly as the fake source simulates is a claim this project
  has not yet verified on physical hardware.
