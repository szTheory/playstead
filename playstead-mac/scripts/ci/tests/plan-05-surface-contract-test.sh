#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

python3 - "$MAC_ROOT" <<'PY'
import pathlib, sys

root = pathlib.Path(sys.argv[1])
identifiers = (root / "Playstead/Design/AccessibilityIdentifiers.swift").read_text()
shell = (root / "Playstead/Library/LibraryShellView.swift").read_text()
sidebar = (root / "Playstead/Library/SidebarView.swift").read_text()
adapter = (root / "Playstead/Adapter/AdapterSetupView.swift").read_text()
bios = (root / "Playstead/Adapter/BiosDropTarget.swift").read_text()
readiness = (root / "Playstead/Readiness/ReadinessSheetView.swift").read_text()
controller = (root / "Playstead/Controller/ControllerSettingsView.swift").read_text()
harness = (root / "PlaysteadUITests/Support/UITestHarness.swift").read_text()
tests = (root / "PlaysteadUITests/SurfaceAccessibilityTests.swift").read_text()
docs = (root / "docs/ACCESSIBILITY.md").read_text()

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

if "performAccessibilityAudit(for: .all)" not in harness or "else { return false }" not in harness:
    raise SystemExit("public accessibility audit must cover all categories and fail closed")
if "AUDIT-DISCOVERY" in harness or "Thread.sleep" in harness or "sleep(" in harness:
    raise SystemExit("live harness contains a discovery bypass or fixed sleep")
if "identifiers.map" not in harness or "identifiers.isEmpty" not in harness:
    raise SystemExit("exact test-owned focus sequence contract is missing")
if "experiential" not in docs or "VoiceOver" not in docs or "Controller hardware itself remains unproven" not in docs:
    raise SystemExit("accessibility evidence boundary is overstated")
PY

printf 'plan 05 static surface contract: passed\n'
