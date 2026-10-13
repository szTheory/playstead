# Accessibility

This document separates properties Playstead can verify mechanically from
experiences that still require a person. It describes the current Mac client,
not a claim of complete accessibility conformance.

## Machine-observable evidence

The recurring Mac UI suite verifies the following against the launched app on
the explicitly inventoried surfaces:

- Keyboard reachability and activation of the tested controls, including
  contained-sheet dismissal and opener-focus restoration.
- Accessibility roles, names, values, parent-child hierarchy, and finite
  element frames for the declared semantic targets.
- Non-color status communication: status symbols have descriptive labels,
  and list rows pair status symbols with text.
- The public macOS accessibility audit categories declared by
  `SurfaceAccessibilityTests`, including contrast, element detection, hit
  region, sufficient element description, action, and parent-child checks.
- Production focus styling is exposed on keyboard-focusable controls; the
  live-tree tests separately check focus movement and activation. They do not
  treat the decorative focus ring as an accessibility-tree element.

`SurfaceAccessibilityTests` is live UI evidence for those named properties.
It does not cover every screen size, every macOS release, or every possible
system appearance. Semantic AppKit colors follow the user's appearance and
accent selection; automated results apply to the environment where that suite
runs.

`ControllerNavigationTests` proves deterministic controller-navigation state
transitions and parity with arrow-key commands. It is unit evidence about the
reducer, not a live focus, device-discovery, or physical-controller result.
The keyboard/live-tree audit and the controller transition suite are separate
evidence categories; neither stands in for the other. The owner-run paired
DualSense walkthrough is the evidence for visible focus and activation from a
physical controller.

## Human review and limits

Automation does not establish VoiceOver pronunciation, rotor usefulness,
sentence quality, human comprehension, or navigation intuition. Those require
human review with VoiceOver and are not claimed by this phase. The public
accessibility audit is not a third-party conformance certification.

Controller text entry is limited to the system and availability filter chips;
free-text search still requires a keyboard. Downloads, Settings, and other
out-of-scope destinations do not inherit a controller-support claim from the
Library transition tests.

Hosted failure diagnostics are source-bounded. They may report a canonical
failed test, a normalized assertion kind, and a repository-relative Swift
file and line only when structured test output resolves to one unique checked-
in source name. Runtime values, full paths, messages, attachments,
environments, and raw result bundles do not cross the artifact boundary.
