#!/usr/bin/env python3
"""Every test on disk must be selected by a plan CI actually runs.

The UI and Rendering plans enumerate `selectedTests` by name, so a newly added
suite is invisible by default: it compiles, it looks registered, and it never
runs. That is the same shape as phase 04's deferred UI layer, which hid five
real defects behind 583 green unit tests until the suites were finally executed.

This guard closes the gap statically -- a test method that no plan selects is a
test that does not exist, and CI says so at the guard step rather than never.
"""
import json
import pathlib
import re
import sys

CLASS = re.compile(r"^\s*(?:public\s+|final\s+|@MainActor\s+)*(?:final\s+)?class\s+(\w+)\s*:\s*([\w\s,.]+)\{?")
FUNC = re.compile(r"^\s*(?:@MainActor\s+)?func\s+(test\w*)\s*\(")

TARGET_DIRS = {"PlaysteadTests": "PlaysteadTests", "PlaysteadUITests": "PlaysteadUITests"}


def discover(root: pathlib.Path):
    """-> {target: {class: set(methods)}}"""
    found = {}
    for target, rel in TARGET_DIRS.items():
        base = root / rel
        classes = {}
        for swift in sorted(base.rglob("*.swift")):
            current = None
            for line in swift.read_text().splitlines():
                m = CLASS.match(line)
                if m:
                    current = m.group(1) if "XCTestCase" in m.group(2) else None
                    if current:
                        classes.setdefault(current, set())
                    continue
                f = FUNC.match(line)
                if f and current:
                    classes[current].add(f.group(1))
        found[target] = classes
    return found


def plan_selections(plans_dir: pathlib.Path):
    """-> {target: list of (selected_or_None, skipped_set)}"""
    sel = {}
    for plan in sorted(plans_dir.glob("*.xctestplan")):
        data = json.loads(plan.read_text())
        for t in data.get("testTargets", []):
            name = t["target"]["name"]
            entry = (
                set(t["selectedTests"]) if "selectedTests" in t else None,
                set(t.get("skippedTests", [])),
            )
            sel.setdefault(name, []).append(entry)
    return sel


def covered(cls, method, entries):
    ident = "%s/%s()" % (cls, method)
    for selected, skipped in entries:
        if selected is None:
            if cls in skipped or ident in skipped:
                continue
            return True
        if cls in selected or ident in selected:
            return True
    return False


def main():
    root = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(".")
    plans = plan_selections(root / "TestPlans")
    allow_path = root / "TestPlans" / "unregistered-allowlist.txt"
    allowed = set()
    if allow_path.exists():
        for line in allow_path.read_text().splitlines():
            line = line.split("#", 1)[0].strip()
            if line:
                allowed.add(line)

    discovered = discover(root)
    # A detector that finds nothing also reports "clean". Refuse to pass on an
    # empty sweep -- a moved directory or a broken parser must fail loudly, not
    # silently bless an unscanned tree.
    for target, classes in discovered.items():
        if not classes:
            print("discovered no XCTestCase classes in target %s -- refusing to"
                  " report a clean sweep" % target, file=sys.stderr)
            return 1

    missing = []
    for target, classes in discovered.items():
        entries = plans.get(target, [])
        for cls, methods in sorted(classes.items()):
            for method in sorted(methods):
                ident = "%s/%s/%s()" % (target, cls, method)
                if ident in allowed:
                    continue
                if not covered(cls, method, entries):
                    missing.append(ident)

    if missing:
        print("These tests exist on disk but no test plan runs them:\n", file=sys.stderr)
        for ident in missing:
            print("  %s" % ident, file=sys.stderr)
        print(
            "\nAdd them to a plan in TestPlans/, or record a reason in\n"
            "TestPlans/unregistered-allowlist.txt (one identifier per line).",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
