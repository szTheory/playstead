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
install_adapter = app_root[app_root.find("func installAdapter() async -> Bool {"):app_root.find("func selectExistingAdapter(appURL:")]
docs = (root / "docs/ACCESSIBILITY.md").read_text()
runner = (root / "scripts/ci/run-mac-verification.sh").read_text()
navigation_tests = (root / "PlaysteadTests/ControllerTests/ControllerNavigationTests.swift").read_text()
plan = (root.parent / ".planning/phases/03.5-mac-verification-automation/03.5-05-PLAN.md").read_text()

routes = {
    "playstead.surface.library": shell,
    "playstead.surface.sidebar": sidebar,
    "playstead.surface.filter": shell,
    "playstead.surface.game-card": shell,
    "playstead.surface.game-list": shell,
    "playstead.surface.readiness": readiness,
    "playstead.surface.adapter": adapter,
    "playstead.surface.bios": bios,
    "playstead.surface.controller-settings": controller,
}
controls = (
    "playstead.control.show-cards",
    "playstead.control.show-list",
    "playstead.control.open-readiness",
    "playstead.control.open-adapter",
    "playstead.control.open-controller-settings",
)

granular_coverage = {
    "testLibraryRouteInventorySettlesOnProductionProfile": (
        "playstead.surface.library", "playstead.surface.sidebar",
        "playstead.surface.filter", "playstead.surface.game-card",
        "validateNativeSearchField()",
    ),
    "testLibraryListRadioControlOpensAndArrowKeysSelectRows": (
        "playstead.control.show-list", "type: .radioButton",
        "playstead.surface.game-list", ".downArrow",
    ),
    "testDownloadsSidebarRouteOpensAndReturnsToLibrary": (
        'selectSidebar("Downloads")', 'selectSidebar("All Games")',
        "playstead.surface.downloads", "XCTAssertFalse",
    ),
    "testLibrarySemanticTargetsHaveRolesLabelsAndFrames": (
        "validateSemanticTargets(libraryTargets)", "validateNativeSearchField()", "sanitizedTrace",
    ),
    "testContextualOpenersHaveRolesLabelsAndFrames": (
        "validateSemanticTargets(contextualOpenerTargets)",
    ),
    "testAdapterSettingsContainsKeyboardFocus": (
        "launchAdapterSettings()", "assertSheetFocusContained",
    ),
    "testAdapterSettingsRouteReturnsToStoragePane": (
        "launchAdapterSettings()", "open-storage", "radioButton", "XCTAssertFalse",
    ),
    "testAdapterSettingsRouteReturnsToLibrary": (
        "launchAdapterSettings()", 'selectSidebar("All Games")', "XCTAssertFalse",
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
    # Plan 09's D-18 whole-surface inventory. Pinned on the two assertions that
    # make it non-vacuous: a fixed-size expected inventory, and the final
    # equality proving every surface was actually visited.
    "testKeyboardOnlySurfaceInventoryAndLiveAudit": (
        "XCTAssertEqual(expectedSurfaces.count, 19",
        "XCTAssertEqual(visited, expectedSurfaces",
        "sanitizedTrace()",
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
readiness_routes_test = tests[
    tests.find("    func testReadinessRoutesReachBIOSAndControllerSettings("):
    tests.find("    func testReadinessSheetContainsKeyboardFocus(")
]
if "playstead.surface.controller-settings" not in readiness_routes_test:
    raise AssertionError("readiness/controller inventory no longer reaches the production Settings route")

if ".searchable(" not in shell or "app.searchFields.firstMatch" not in tests:
    raise AssertionError("library search must be checked through its native accessibility role")

check_granular_coverage(tests)
for marker in (
    "playstead.surface.readiness", "playstead.surface.bios",
):
    helper = tests[tests.find("    private func launchReadinessRoutes") :]
    if marker not in helper:
        raise AssertionError(f"readiness route helper lost coverage: {marker}")
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
    "rootIdentifier: String",
    "let rootFrame = root.frame.insetBy(dx: -1, dy: -1)",
    "let auditedElements = [root] + root.descendants(matching: .any).allElementsBoundByIndex",
    "!auditedElements.contains(where: { $0 == issueElement })",
    "!rootFrame.contains(issueFrame)",
    'rawIdentifier.hasPrefix("playstead.")',
    'rawIdentifier.hasPrefix("library.")',
    "hasOnlyAllowedCharacters",
    'boundedRole = "role-\\(issue.element?.elementType.rawValue ?? 0)"',
    ': "unidentified"',
    "PLAYSTEAD_A11Y_ISSUES[\\(category.rawValue)]",
    "XCTAssertTrue(",
    "issueIdentifiers.isEmpty",
):
    if marker not in harness:
        raise SystemExit(f"bounded fail-closed audit identity is missing: {marker}")
expected_audit_roots = {
    "auditLibrary": "playstead.surface.library",
    "auditContextualOpeners": "playstead.surface.library",
    "auditAdapter": "playstead.surface.adapter",
    "auditReadiness": "playstead.surface.readiness",
}
for helper, root_identifier in expected_audit_roots.items():
    start = tests.find(f"    private func {helper}")
    end = tests.find("    private func", start + 1)
    section = tests[start:end if end >= 0 else len(tests)]
    if f'try harness.audit(category, rootIdentifier: "{root_identifier}")' not in section:
        raise SystemExit(f"{helper} does not scope the public audit to its production root")
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
        "root.descendants(matching: .button)",
    )
    missing = [marker for marker in required_harness if marker not in harness_source]
    if missing or harness_source.count("root.descendants(matching: .button)") < 2 or "0..<expected.count where !foundActivationTarget" in harness_source:
        raise AssertionError(f"focus traversal uses a content-dependent bound or lacks containment: {missing}")
    if harness_source.count("descendantIDs.contains(focused[0].identifier)") != 1:
        raise AssertionError("named-action traversal rejects unnamed intermediate controls inside the sheet")
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
    required = {
        "PLAYSTEAD_UI_TESTING": '"1"',
        "PLAYSTEAD_UI_TEST_PROFILE": "profile.rawValue",
    }
    # Plan 06 added an opt-in per-session identity so a deterministic profile
    # survives process relaunch. It is the ONLY permitted addition, it must be a
    # freshly generated UUID (never a fixed or caller-supplied value, which would
    # let one test observe another's store), and it must stay gated behind
    # `persistentSession` so the default launch is still exactly mode + profile.
    optional = {
        "PLAYSTEAD_UI_TEST_SESSION_ID": "UUID().uuidString.lowercased()",
    }
    for key, value in required.items():
        if assignments.get(key) != value:
            raise AssertionError(f"UI harness launch environment lost required {key}: {assignments}")
    unexpected = set(assignments) - set(required) - set(optional)
    if unexpected:
        raise AssertionError(f"UI harness launch environment gained unexpected keys: {sorted(unexpected)}")
    for key, value in optional.items():
        if key in assignments and assignments[key] != value:
            raise AssertionError(f"{key} must be a freshly generated UUID, got: {assignments[key]}")
    if "PLAYSTEAD_UI_TEST_SESSION_ID" in assignments and "if persistentSession {" not in harness_source:
        raise AssertionError("per-session identity must stay gated behind persistentSession")
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
    # Plan 06 threads the opt-in per-session identity into the fixture so a
    # deterministic profile survives relaunch; composition is otherwise unchanged.
    "let fixture = try profile.makeFixture(sessionID: processEnvironment[sessionIDKey])",
    "uiTestingPaths: fixture.paths",
    "localStore: fixture.localStore",
    "appEnvironment.blockExternalIOForUITesting()",
):
    if marker not in bootstrap:
        raise SystemExit(f"deterministic UI profile composition drifted: {marker}")
if "guard !uiTestingBlocksExternalIO else { return false }" not in install_adapter:
    raise SystemExit("deterministic adapter activation can reach the production downloader")

def check_audit_repairs(shell_source, row_source, token_source, focus_source):
    required_shell = (
        'Picker("Library view", selection: $libraryLayout)',
        '.accessibilityLabel("Library view")',
        ".accessibilityLabel(Self.title(for: surface))",
        ".background(DesignTokens.background.ignoresSafeArea())",
        ".accessibilityHidden(true)",
    )
    missing = [marker for marker in required_shell if marker not in shell_source]
    if missing or "ToolbarItem(placement: .primaryAction)" not in shell_source:
        raise AssertionError(f"native view switch or labeled sheet contract regressed: {missing}")
    if "static let background = Color(nsColor: .windowBackgroundColor)" not in token_source:
        raise AssertionError("the app canvas must follow the semantic macOS window color")
    if ".accessibilityHidden(true)" not in focus_source:
        raise AssertionError("decorative focus-ring shape leaked into the accessibility tree")
    # 03.5-07 (73cd594) moved the row from `.combine` to `.contain`. `.combine`
    # flattens children away, which would have hidden the per-row favorite/queue/
    # pin buttons that plans 06/07 require as individually addressable targets.
    # The requirement the marker encodes is unchanged: the row is one explicitly
    # described accessibility element, not an unlabeled pile of leaves.
    for marker in (".accessibilityElement(children: .contain)", ".accessibilityLabel(rowSummaryAccessibilityLabel)"):
        if marker not in row_source:
            raise AssertionError("game-row summary is not one described accessibility element")

check_audit_repairs(shell, game_row, tokens, focus_ring)

def check_hosted_audit_repairs(shell_source, readiness_source, row_source, slot_source, report_source):
    required_shell = (
        "@FocusState private var focusedSheetDismissal: Bool",
        ".focused($focusedSheetDismissal)",
        ".focusSection()",
        ".defaultFocus($focusedSheetDismissal, true)",
        ".background(DesignTokens.background.ignoresSafeArea())",
    )
    required_readiness = (
        "@FocusState private var doneHasFocus: Bool",
        ".focused($doneHasFocus)",
        ".focusSection()",
        ".defaultFocus($doneHasFocus, true)",
        ".background(DesignTokens.background.ignoresSafeArea())",
    )
    missing = [marker for marker in required_shell if marker not in shell_source]
    missing += [marker for marker in required_readiness if marker not in readiness_source]
    if missing or shell_source.count(".background(DesignTokens.background.ignoresSafeArea())") < 2:
        raise AssertionError(f"sheet focus or semantic system canvas regressed: {missing}")
    card_branch = row_source.find("case .card:")
    card_content_start = row_source.find("private var cardContent: some View {")
    card_content_end = row_source.find("\n    private var systemDisplayName", card_content_start)
    if min(card_branch, card_content_start, card_content_end) < 0 or card_branch > card_content_start:
        raise AssertionError("library card presentation is not routed through its production row")
    card_content = row_source[card_content_start:card_content_end]
    card_controls = ("actionButton", "favoriteButton", "queueButton", "curationMenu", "statusPair")
    missing_card_controls = [marker for marker in card_controls if marker not in card_content]
    if missing_card_controls or any(
        marker in card_content
        for marker in (".accessibilityElement(children: .ignore)", ".accessibilityElement(children: .combine)")
    ):
        raise AssertionError(f"actionable game card lost independent controls or status: {missing_card_controls}")
    required_actions = (
        "Self.downloadActionIdentifier(assetSetID: entry.id)",
        "Self.playActionIdentifier(assetSetID: entry.id)",
        "Self.retryActionIdentifier(assetSetID: entry.id)",
        ".accessibilityLabel(Self.favoriteActionLabel(",
        ".accessibilityLabel(Self.queueActionLabel(",
    )
    missing_actions = [marker for marker in required_actions if marker not in row_source]
    if missing_actions:
        raise AssertionError(f"production game card actions lost stable identifiers or accessible names: {missing_actions}")
    if '?? ""' in slot_source or "Color.clear" not in slot_source or ".accessibilityHidden(true)" not in slot_source:
        raise AssertionError("empty status slot can become an undescribed accessibility element")
    if ".accessibilityElement(children: .contain)" not in report_source or '.accessibilityLabel("\\(label). \\(check.finding)")' not in report_source or ".accessibilityHidden(true)" not in report_source:
        raise AssertionError("readiness row collapses its actionable remedy into the descriptive parent")

check_hosted_audit_repairs(shell, readiness, game_row, status_slot, readiness_report)

for marker, source_name in (
    ("@FocusState private var focusedSheetDismissal: Bool", "shell"),
    (".defaultFocus($focusedSheetDismissal, true)", "shell"),
    ("@FocusState private var doneHasFocus: Bool", "readiness"),
    (".defaultFocus($doneHasFocus, true)", "readiness"),
    ("case .card:", "card"),
    ("                actionButton\n                favoriteButton\n                queueButton\n                curationMenu", "card"),
    ("Self.downloadActionIdentifier(assetSetID: entry.id)", "card"),
    ("Self.playActionIdentifier(assetSetID: entry.id)", "card"),
    ("Self.retryActionIdentifier(assetSetID: entry.id)", "card"),
    ("Color.clear", "slot"),
    ('.accessibilityLabel("\\(label). \\(check.finding)")', "report"),
    (".accessibilityHidden(true)", "report"),
):
    sources = {
        "shell": shell,
        "readiness": readiness,
        "card": game_row,
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
    'Picker("Library view", selection: $libraryLayout)',
    '.accessibilityLabel("Library view")',
    ".accessibilityLabel(Self.title(for: surface))",
):
    try:
        check_audit_repairs(shell.replace(marker, "removed.repair", 1), game_row, tokens, focus_ring)
    except AssertionError:
        pass
    else:
        raise SystemExit(f"audit-repair meta-test did not fail after removing {marker}")

try:
    check_audit_repairs(shell, game_row, tokens.replace(
        "static let background = Color(nsColor: .windowBackgroundColor)",
        "removed.semantic.canvas",
        1,
    ), focus_ring)
except AssertionError:
    pass
else:
    raise SystemExit("semantic macOS canvas meta-test did not fail after removing its token")

def check_accessibility_evidence_contract(document):
    machine_heading = "## Machine-observable evidence"
    human_heading = "## Human review and limits"
    machine_start = document.find(machine_heading)
    human_start = document.find(human_heading)
    if machine_start < 0 or human_start <= machine_start:
        raise AssertionError("machine evidence and human limits must be distinct sections")
    machine = document[machine_start:human_start]
    human = document[human_start:]
    required_machine = (
        "Keyboard reachability and activation",
        "Accessibility roles, names, values, parent-child hierarchy",
        "Non-color status communication",
        "public macOS accessibility audit categories",
        "`SurfaceAccessibilityTests` is live UI evidence",
        "`ControllerNavigationTests` proves deterministic controller-navigation state",
        "neither stands in for the other",
        "owner-run paired",
        "DualSense walkthrough",
    )
    required_human = (
        "Automation does not establish VoiceOver pronunciation",
        "rotor usefulness",
        "sentence quality",
        "human comprehension",
        "navigation intuition",
        "not a third-party conformance certification",
    )
    missing = [marker for marker in required_machine if marker not in machine]
    missing += [marker for marker in required_human if marker not in human]
    if missing:
        raise AssertionError(f"accessibility evidence contract is incomplete: {missing}")
    forbidden = (
        "automation proves VoiceOver comprehension",
        "automation establishes VoiceOver pronunciation",
        "ControllerNavigationTests proves visible focus",
        "unit tests prove physical controller behavior",
    )
    lowered = document.lower()
    overclaims = [claim for claim in forbidden if claim.lower() in lowered]
    if overclaims:
        raise AssertionError(f"unsupported accessibility claims found: {overclaims}")

check_accessibility_evidence_contract(docs)
for marker in (
    "Keyboard reachability and activation",
    "Non-color status communication",
    "public macOS accessibility audit categories",
    "neither stands in for the other",
    "Automation does not establish VoiceOver pronunciation",
    "rotor usefulness",
    "navigation intuition",
):
    try:
        check_accessibility_evidence_contract(docs.replace(marker, "removed.evidence.contract", 1))
    except AssertionError:
        pass
    else:
        raise SystemExit(f"accessibility claim meta-test did not fail after removing {marker}")

try:
    check_accessibility_evidence_contract(docs + "\nAutomation proves VoiceOver comprehension.\n")
except AssertionError:
    pass
else:
    raise SystemExit("accessibility claim meta-test did not fail after adding an overclaim")

def check_evidence_registration(runner_source, navigation_source):
    unit_start = runner_source.find("run_test_layer unit Unit")
    rendering_start = runner_source.find("run_test_layer rendering Rendering", unit_start)
    ui_start = runner_source.find("run_test_layer ui UI", rendering_start)
    live_start = runner_source.find("run_test_layer live-server LiveServer", ui_start)
    if min(unit_start, rendering_start, ui_start, live_start) < 0:
        raise AssertionError("recurring evidence layer boundaries are missing")
    unit_layer = runner_source[unit_start:rendering_start]
    ui_layer = runner_source[ui_start:live_start]
    expected_navigation = set(re.findall(r"^    func (test[A-Za-z0-9_]+)\(", navigation_source, re.MULTILINE))
    registered_navigation = set(re.findall(r"PlaysteadTests\.ControllerNavigationTests/(test[A-Za-z0-9_]+)", unit_layer))
    if not expected_navigation or expected_navigation != registered_navigation:
        raise AssertionError(
            f"controller transition evidence must be required in Unit independently: "
            f"missing={sorted(expected_navigation - registered_navigation)}, "
            f"unexpected={sorted(registered_navigation - expected_navigation)}"
        )
    live_audit = "PlaysteadUITests.SurfaceAccessibilityTests/testKeyboardOnlySurfaceInventoryAndLiveAudit"
    if live_audit not in ui_layer or "SurfaceAccessibilityTests/" in unit_layer:
        raise AssertionError("keyboard/live-tree evidence must remain a separately required UI test")

check_evidence_registration(runner, navigation_tests)
for test_identifier in (
    "PlaysteadTests.ControllerNavigationTests/testRightEntersRecentlyPlayedAtItsFirstAvailableGame",
    "PlaysteadUITests.SurfaceAccessibilityTests/testKeyboardOnlySurfaceInventoryAndLiveAudit",
):
    mutated_runner = runner.replace(test_identifier, "removed.required.evidence")
    try:
        check_evidence_registration(mutated_runner, navigation_tests)
    except AssertionError:
        pass
    else:
        raise SystemExit(f"evidence registration meta-test did not fail after removing {test_identifier}")
PY

printf 'plan 05 static surface contract: passed\n'
