"""Strict parser for marker-only, numeric UI layout evidence."""

import re

_RECORD = re.compile(
    r"PLAYSTEAD_LAYOUT_V1 kind=(?P<kind>moveUp|dragCell|orderCell) "
    r"hittable=(?P<hittable>true|false) "
    r"element=\((?P<element>-?[0-9]+,-?[0-9]+,[0-9]+,[0-9]+)\) "
    r"pane=\((?P<pane>-?[0-9]+,-?[0-9]+,[0-9]+,[0-9]+)\) "
    r"window=\((?P<window>-?[0-9]+,-?[0-9]+,[0-9]+,[0-9]+)\)"
    r"(?: slot=(?P<slot>[1-9][0-9]{0,2}))?"
)


def _frame(value):
    values = [int(part) for part in value.split(",")]
    x, y, width, height = values
    if any(abs(number) > 100000 for number in values) or width < 0 or height < 0:
        return None
    return values


def parse_layout_marker(text):
    """Return only exact allowlisted marker records; discard free-form text."""
    records = []
    for match in _RECORD.finditer(text):
        element = _frame(match.group("element"))
        pane = _frame(match.group("pane"))
        window = _frame(match.group("window"))
        if element is None or pane is None or window is None:
            continue
        slot = match.group("slot")
        kind = match.group("kind")
        if (kind == "orderCell") != (slot is not None):
            continue
        record = {
            "kind": kind,
            "hittable": match.group("hittable") == "true",
            "element": element,
            "pane": pane,
            "window": window,
        }
        if slot is not None:
            record["slot"] = int(slot)
        records.append(record)
    return records
