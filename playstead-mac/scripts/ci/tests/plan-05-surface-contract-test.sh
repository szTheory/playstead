#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

python3 - "$MAC_ROOT" <<'PY'
import pathlib, re, sys

root = pathlib.Path(sys.argv[1])
identifiers = (root / "Playstead/Design/AccessibilityIdentifiers.swift").read_text()
tokens = (root / "Playstead/Design/DesignTokens.swift").read_text()
focus_ring = (root / "Playstead/Design/FocusRing.swift").read_text()
shell = (root / "Playstead/Library/LibraryShellView.swift").read_text()
game_row = (root / "Playstead/Library/GameRowView.swift").read_text()
game_card = (root / "Playstead/Library/GameCardView.swift").read_text()
status_slot = (root / "Playstead/Library/StatusSlotView.swift").read_text()
sidebar = (root / "Playstead/Library/SidebarView.swift").read_text()
adapter = (root / "Playstead/Adapter/AdapterSetupView.swift").read_text()
bios = (root / "Playstead/Adapter/BiosDropTarget.swift").read_text()
readiness = (root / "Playstead/Readiness/ReadinessSheetView.swift").read_text()
readiness_report = (root / "Playstead/Readiness/ReadinessReportView.swift").read_text()
controller = (root / "Playstead/Controller/ControllerSettingsView.swift").read_text()
harness = (root / "PlaysteadUITests/Support/UITestHarness.swift").read_text()
tests = (root / "PlaysteadUITests/SurfaceAccessibilityTests.swift").read_text()
bootstrap = (root / "Playstead/UITesting/UITestBootstrap.swift").read_text()
profiles = (root / "Playstead/UITesting/DeterministicProfile.swift").read_text()
app_root = (root / "Playstead/App/PlaysteadApp.swift").read_text()
docs = (root / "docs/ACCESSIBILITY.md").read_text()
plan = (root.parent / ".planning/phases/03.5-mac-verification-automation/03.5-05-PLAN.md").read_text()

routes = {
    "playstead.surface.library": shell,
    "playstead.surface.sidebar": sidebar,
    "playstead.surface.search": shell,
    "playstead.surface.filter": shell,
    "playstead.surface.game-card": shell,
    "playstead.surface.game-list": shell,
    "playstead.surface.readiness": readiness,
    "playstead.surface.adapter": shell,
    "playstead.surface.bios": bios,
    "playstead.surface.controller-settings": controller,
}
controls = (
    "playstead.control.show-cards",
    "playstead.control.show-list",
    "playstead.control.open-readiness",
    "playstead.control.open-adapter",
    "playstead.control.open-bios",
    "playstead.control.open-controller-settings",
)

granular_coverage = {
    "testLibraryRouteInventorySettlesOnProductionProfile": (
        "playstead.surface.library", "playstead.surface.sidebar",
        "playstead.surface.search", "playstead.surface.filter",
        "playstead.surface.game-card", "library.search.field",
    ),
    "testLibraryFocusSequenceWrapsAndActivatesList": (
        "exactFocusOrder", "traverseExactFocusSequence", "playstead.surface.game-list",
    ),
    "testDownloadsSheetOpensAndDismisses": (
        "playstead.control.open-downloads", "playstead.control.done", "XCTAssertFalse",
    ),
    "testLibrarySemanticTargetsHaveRolesLabelsAndFrames": (
        "validateSemanticTargets(libraryTargets)", "sanitizedTrace",
    ),
    "testContextualOpenersHaveRolesLabelsAndFrames": (
        "validateSemanticTargets(contextualOpenerTargets)",
    ),
    "testAdapterSheetContainsKeyboardFocus": (
        "launchAdapterSheet()", "assertSheetFocusContained",
    ),
    "testAdapterSheetDismissesWithEscape": (
        "launchAdapterSheet()", ".escape", "XCTAssertFalse",
    ),
    "testAdapterSheetRestoresOpenerFocusAfterEscape": (
        "launchAdapterSheet()", ".escape", "hasKeyboardFocus",
    ),
    "testAdapterControlsHaveRolesLabelsAndFrames": (
        "validateSemanticTargets(adapterTargets)",
    ),
    "testReadinessRoutesReachBIOSAndControllerSettings": ("launchReadinessRoutes()",),
    "testReadinessSheetContainsKeyboardFocus": (
        "launchReadinessRoutes()", "assertSheetFocusContained",
    ),
    "testReadinessDoneActionReceivesKeyboardFocus": (
        "launchReadinessRoutes()", "focusContainedAction", "playstead.control.done",
    ),
    "testReadinessDoneActionDismissesSheet": (
        "launchReadinessRoutes()", "focusContainedAction", "typeKey(.space", "XCTAssertFalse",
    ),
    "testReadinessControlsHaveRolesLabelsAndFrames": (
        "validateSemanticTargets(readinessTargets)",
    ),
}

audit_surfaces = {
    "Library": "auditLibrary",
    "ContextualOpeners": "auditContextualOpeners",
    "Adapter": "auditAdapter",
    "Readiness": "auditReadiness",
}
audit_categories = {
    "Contrast": "contrast",
    "ElementDetection": "elementDetection",
    "HitRegion": "hitRegion",
    "SufficientDescription": "sufficientElementDescription",
    "Action": "action",
    "ParentChild": "parentChild",
}
for surface, helper in audit_surfaces.items():
    for category_name, category_value in audit_categories.items():
        granular_coverage[f"test{surface}{category_name}AccessibilityAudit"] = (
            f"{helper}(.{category_value})",
        )

def check_granular_coverage(test_source):
    matches = list(re.finditer(r"^    func (test[A-Za-z0-9_]+)\(", test_source, re.MULTILINE))
    names = [match.group(1) for match in matches]
    if set(names) != set(granular_coverage) or len(names) != len(granular_coverage):
        raise AssertionError(f"granular UI test identity drift: {names}")
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else test_source.find("    private func", match.end())
        section = test_source[match.start():end]
        missing = [marker for marker in granular_coverage[match.group(1)] if marker not in section]
        if missing:
            raise AssertionError(f"{match.group(1)} lost acceptance coverage: {missing}")
    for name in granular_coverage:
        if name not in plan and "PlaysteadUITests/SurfaceAccessibilityTests</automated>" not in plan:
            raise AssertionError(f"Plan 05 verification does not select granular test: {name}")
    broad_tests = (
        "testLibrarySidebarUsesIndependentFocusAndLiveAudit",
        "testContextualRoutesContainAndRestoreFocus",
        "testLibraryControlsPassLiveAccessibilityAudit",
        "testContextualOpenersPassLiveAccessibilityAudit",
        "testAdapterSheetContainsFocusDismissesAndRestoresOpener",
        "testAdapterControlsPassLiveAccessibilityAudit",
        "testReadinessSheetContainsFocusAndDoneDismisses",
        "testReadinessControlsPassLiveAccessibilityAudit",
    )
    if any(name in test_source for name in broad_tests):
        raise AssertionError("broad UI tests hide the failing audit category or sheet stage")
    for marker in (
        "playstead.surface.readiness", "playstead.surface.bios",
        "playstead.surface.controller-settings",
    ):
        helper = test_source[test_source.find("    private func launchReadinessRoutes") :]
        if marker not in helper:
            raise AssertionError(f"readiness route helper lost coverage: {marker}")

check_granular_coverage(tests)
for name, markers in granular_coverage.items():
    method = re.search(rf"^    func {name}\(", tests, re.MULTILINE)
    following = re.search(r"^    (?:func test|private func)", tests[method.end():], re.MULTILINE)
    end = method.end() + following.start() if following else len(tests)
    section = tests[method.start():end]
    mutated_section = section.replace(markers[0], "removed.granular.coverage")
    mutated = tests[:method.start()] + mutated_section + tests[end:]
    try:
        check_granular_coverage(mutated)
    except AssertionError:
        pass
    else:
        raise SystemExit(f"granular coverage meta-test did not fail for {name}")

def check_route_inventory(sources):
    missing = [route for route, source in sources.items() if route not in tests or route not in identifiers or "AccessibilityIdentifiers.Surface" not in source]
    if missing:
        raise AssertionError(f"missing independently inventoried production routes: {missing}")

check_route_inventory(routes)
for control in controls:
    if control not in tests or control not in identifiers:
        raise SystemExit(f"missing independently authored control contract: {control}")

# Meta-test the checker itself: one removed route must be detected.
mutated = dict(routes)
mutated["playstead.surface.bios"] = mutated["playstead.surface.bios"].replace("AccessibilityIdentifiers.Surface.bios", "removed.route")
try:
    check_route_inventory(mutated)
except AssertionError:
    pass
else:
    raise SystemExit("route-removal meta-test did not fail")

category_block = harness[harness.find("enum AuditCategory"):harness.find("let app: XCUIApplication")]
declared_categories = set(re.findall(r"^        case ([A-Za-z0-9_]+)$", category_block, re.MULTILINE))
if declared_categories != set(audit_categories.values()):
    raise SystemExit(f"macOS public accessibility audit category drift: {declared_categories}")
for category in audit_categories.values():
    if f"case .{category}: .{category}" not in category_block:
        raise SystemExit(f"audit category is not mapped one-to-one: {category}")
if "performAccessibilityAudit(for: category.xcuiType)" not in harness:
    raise SystemExit("public accessibility audit must run one canonical category")
for marker in (
    'rawIdentifier.hasPrefix("playstead.")',
    'rawIdentifier.hasPrefix("library.")',
    "hasOnlyAllowedCharacters",
    ': "unidentified"',
    "PLAYSTEAD_A11Y_ISSUES[\\(category.rawValue)]",
    "XCTAssertTrue(",
    "issueIdentifiers.isEmpty",
):
    if marker not in harness:
        raise SystemExit(f"bounded fail-closed audit identity is missing: {marker}")
if "performAccessibilityAudit(for: .all)" in harness:
    raise SystemExit("all-category audit hides the canonical failing category")
if "func validateSemanticTargets(_ targets: [AuditTarget])" not in harness:
    raise SystemExit("semantic role/label/frame validation is not independently observable")
if "exclusions:" in tests:
    raise SystemExit("Plan 05 contracts must repair production audit issues, not suppress them")
if "AUDIT-DISCOVERY" in harness or "Thread.sleep" in harness or "sleep(" in harness:
    raise SystemExit("live harness contains a discovery bypass or fixed sleep")
if "identifiers.map" not in harness or "identifiers.isEmpty" not in harness:
    raise SystemExit("exact test-owned focus sequence contract is missing")

def check_focus_expectations(harness_source, test_source):
    required_harness = (
        "for _ in 0..<24 where !foundActivationTarget",
        "activation search crossed declared controls out of cyclic order",
        "func focusContainedAction(_ identifier: String, rootIdentifier: String)",
        "requested action is outside the presented sheet",
    )
    missing = [marker for marker in required_harness if marker not in harness_source]
    if missing or "0..<expected.count where !foundActivationTarget" in harness_source:
        raise AssertionError(f"focus traversal uses a content-dependent bound or lacks containment: {missing}")
    dismissal_start = test_source.find("    func testReadinessDoneActionDismissesSheet()")
    dismissal_end = test_source.find("    func testReadinessControlsHaveRolesLabelsAndFrames()", dismissal_start)
    dismissal = test_source[dismissal_start:dismissal_end]
    focus_call = dismissal.find("harness.focusContainedAction(")
    done_activation = dismissal.find('harness.element("playstead.control.done", type: .button).typeKey')
    if focus_call < 0 or done_activation < 0 or focus_call > done_activation:
        raise AssertionError("Done receives Space before the test explicitly moves sheet focus to Done")

check_focus_expectations(harness, tests)
for marker, source_name in (
    ("for _ in 0..<24 where !foundActivationTarget", "harness"),
    ("func focusContainedAction(_ identifier: String, rootIdentifier: String)", "harness"),
):
    mutated_harness = harness.replace(marker, "removed.focus.contract", 1) if source_name == "harness" else harness
    mutated_tests = tests.replace(marker, "removed.focus.contract", 1) if source_name == "tests" else tests
    try:
        check_focus_expectations(mutated_harness, mutated_tests)
    except AssertionError:
        pass
    else:
        raise SystemExit(f"focus expectation meta-test did not fail after removing {marker}")

def check_ui_profile_launch(harness_source):
    assignments = dict(re.findall(r'app\.launchEnvironment\["([A-Z0-9_]+)"\] = (.+)', harness_source))
    expected = {
        "PLAYSTEAD_UI_TESTING": '"1"',
        "PLAYSTEAD_UI_TEST_PROFILE": "profile.rawValue",
    }
    if assignments != expected:
        raise AssertionError(f"UI harness launch environment must be exactly mode + finite profile: {assignments}")
    if "enum Profile: String, CaseIterable" not in harness_source:
        raise AssertionError("UI harness profile selector is not finite")

check_ui_profile_launch(harness)
for key in ("PLAYSTEAD_UI_TESTING", "PLAYSTEAD_UI_TEST_PROFILE"):
    try:
        check_ui_profile_launch(harness.replace(f'app.launchEnvironment["{key}"]', 'removed.environment.key', 1))
    except AssertionError:
        pass
    else:
        raise SystemExit(f"UI launch environment meta-test did not fail after removing {key}")

app_profiles = set(re.findall(r'case [A-Za-z0-9_]+ = "([a-z0-9-]+)"', profiles.split("static func parse", 1)[0]))
harness_profiles = set(re.findall(r'case [A-Za-z0-9_]+ = "([a-z0-9-]+)"', harness.split("struct AuditTarget", 1)[0]))
if harness_profiles != app_profiles or not harness_profiles:
    raise SystemExit("XCUITest finite profile mirror drifted from the app profile allowlist")
if 'static let modeKey = "PLAYSTEAD_UI_TESTING"' not in bootstrap or 'environment[modeKey] == "1"' not in bootstrap:
    raise SystemExit("UI bootstrap mode gate is not fail closed")
if "guard isRequested(environment: processEnvironment)" not in bootstrap or "DeterministicProfile.parse" not in bootstrap:
    raise SystemExit("UI bootstrap bypasses mode/profile validation")
if "APIClient.unpairedForUITesting()" not in app_root or "credential" in " ".join(re.findall(r'app\.launchEnvironment\["([^"]+)"\]', harness)).lower():
    raise SystemExit("UI profile composition may use a credential override")

profile_root = app_root[app_root.find("private struct UITestProfileRootView"):app_root.find("private struct ProductionRootView")]
if "LibraryShellView()" not in profile_root or ".environment(session.environment)" not in profile_root:
    raise SystemExit("deterministic UI profile does not render the production library shell")
if any(name in profile_root for name in ("AdapterSetupView()", "ReadinessSheetView(", "BiosDropTargetView(", "ControllerSettingsView(")):
    raise SystemExit("deterministic UI profile duplicates a Plan 05 production surface")
for marker in (
    "let fixture = try profile.makeFixture()",
    "uiTestingPaths: fixture.paths",
    "localStore: fixture.localStore",
    "appEnvironment.blockExternalIOForUITesting()",
):
    if marker not in bootstrap:
        raise SystemExit(f"deterministic UI profile composition drifted: {marker}")

def check_audit_repairs(shell_source, row_source, token_source, focus_source):
    required_shell = (
        "private var libraryCommandBar",
        '.accessibilityLabel("Library actions")',
        ".focused($focusedShellControl, equals: surface)",
        ".onChange(of: presentedSurface)",
        "focusedShellControl = previous",
        ".accessibilityLabel(Self.title(for: surface))",
        ".background(DesignTokens.background.ignoresSafeArea())",
        ".preferredColorScheme(.dark)",
        ".accessibilityHidden(true)",
    )
    missing = [marker for marker in required_shell if marker not in shell_source]
    if missing or ".toolbar {" in shell_source:
        raise AssertionError(f"unlabeled toolbar/sheet or focus-restoration regression: {missing}")
    if "static let background = Color(hex: 0x0F172A)" not in token_source:
        raise AssertionError("the dark palette has no explicit production canvas")
    if ".foregroundStyle(.secondary)" in row_source:
        raise AssertionError("small game-row metadata regressed to the low-contrast secondary role")
    if ".accessibilityHidden(true)" not in focus_source:
        raise AssertionError("decorative focus-ring shape leaked into the accessibility tree")
    for marker in (".accessibilityElement(children: .combine)", ".accessibilityLabel(rowSummaryAccessibilityLabel)"):
        if marker not in row_source:
            raise AssertionError("game-row summary is not one described accessibility element")

check_audit_repairs(shell, game_row, tokens, focus_ring)

def check_hosted_audit_repairs(shell_source, readiness_source, card_source, slot_source, report_source):
    required_shell = (
        "@FocusState private var focusedSheetDismissal: Bool",
        ".focused($focusedSheetDismissal)",
        ".onAppear { focusedSheetDismissal = true }",
        ".background(DesignTokens.background.ignoresSafeArea())",
        ".preferredColorScheme(.dark)",
    )
    required_readiness = (
        "@FocusState private var doneHasFocus: Bool",
        ".focused($doneHasFocus)",
        ".onAppear { doneHasFocus = true }",
        ".background(DesignTokens.background.ignoresSafeArea())",
        ".preferredColorScheme(.dark)",
    )
    missing = [marker for marker in required_shell if marker not in shell_source]
    missing += [marker for marker in required_readiness if marker not in readiness_source]
    if missing or shell_source.count(".background(DesignTokens.background.ignoresSafeArea())") < 2:
        raise AssertionError(f"sheet focus or explicit dark canvas regressed: {missing}")
    if ".accessibilityElement(children: .ignore)" not in card_source or ".accessibilityElement(children: .combine)" in card_source:
        raise AssertionError("described game card exposes a conflicting nested accessibility subtree")
    if '?? ""' in slot_source or "Color.clear" not in slot_source or ".accessibilityHidden(true)" not in slot_source:
        raise AssertionError("empty status slot can become an undescribed accessibility element")
    if ".accessibilityElement(children: .contain)" not in report_source or '.accessibilityLabel("\\(label). \\(check.finding)")' not in report_source:
        raise AssertionError("readiness row collapses its actionable remedy into the descriptive parent")

check_hosted_audit_repairs(shell, readiness, game_card, status_slot, readiness_report)

for marker, source_name in (
    ("@FocusState private var focusedSheetDismissal: Bool", "shell"),
    (".onAppear { focusedSheetDismissal = true }", "shell"),
    ("@FocusState private var doneHasFocus: Bool", "readiness"),
    (".onAppear { doneHasFocus = true }", "readiness"),
    (".accessibilityElement(children: .ignore)", "card"),
    ("Color.clear", "slot"),
    ('.accessibilityLabel("\\(label). \\(check.finding)")', "report"),
):
    sources = {
        "shell": shell,
        "readiness": readiness,
        "card": game_card,
        "slot": status_slot,
        "report": readiness_report,
    }
    sources[source_name] = sources[source_name].replace(marker, "removed.hosted.audit.repair", 1)
    try:
        check_hosted_audit_repairs(
            sources["shell"], sources["readiness"], sources["card"],
            sources["slot"], sources["report"],
        )
    except AssertionError:
        pass
    else:
        raise SystemExit(f"hosted-audit repair meta-test did not fail after removing {marker}")

# Pin the production repairs themselves: each synthetic removal must trip the
# source contract rather than letting the live audit regress silently.
for marker in (
    "private var libraryCommandBar",
    ".onChange(of: presentedSurface)",
    ".accessibilityLabel(Self.title(for: surface))",
):
    try:
        check_audit_repairs(shell.replace(marker, "removed.repair", 1), game_row, tokens, focus_ring)
    except AssertionError:
        pass
    else:
        raise SystemExit(f"audit-repair meta-test did not fail after removing {marker}")

if "experiential" not in docs or "VoiceOver" not in docs or "Controller hardware itself remains unproven" not in docs:
    raise SystemExit("accessibility evidence boundary is overstated")
PY

printf 'plan 05 static surface contract: passed\n'
