import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from layout_evidence import parse_layout_marker


class LayoutEvidenceContractTests(unittest.TestCase):
    def test_fixed_numeric_marker_is_reduced_to_allowlisted_fields(self):
        marker = (
            "PLAYSTEAD_LAYOUT_V1 kind=moveUp hittable=false "
            "element=(12,34,56,78) pane=(1,2,300,400) window=(0,0,1200,900)"
        )
        self.assertEqual(parse_layout_marker(marker), [{
            "kind": "moveUp", "hittable": False,
            "element": [12, 34, 56, 78], "pane": [1, 2, 300, 400],
            "window": [0, 0, 1200, 900],
        }])

    def test_multiple_order_cells_keep_only_bounded_ordinal_and_geometry(self):
        markers = ";".join(
            f"PLAYSTEAD_LAYOUT_V1 kind=orderCell hittable=true "
            f"element=(0,{slot * 40},500,36) pane=(0,0,500,400) "
            f"window=(0,0,1200,900) slot={slot}"
            for slot in range(1, 4)
        )
        records = parse_layout_marker(markers)
        self.assertEqual([record["slot"] for record in records], [1, 2, 3])
        self.assertTrue(all(set(record) == {"kind", "hittable", "element", "pane", "window", "slot"} for record in records))

    def test_unmarked_or_free_form_failure_text_is_discarded_while_marker_is_reduced(self):
        marker = (
            "PLAYSTEAD_LAYOUT_V1 kind=dragCell hittable=true "
            "element=(0,80,500,36) pane=(0,0,500,400) window=(0,0,1200,900)"
        )
        expected = [{
            "kind": "dragCell", "hittable": True,
            "element": [0, 80, 500, 36], "pane": [0, 0, 500, 400],
            "window": [0, 0, 1200, 900],
        }]
        self.assertEqual(parse_layout_marker("curation-geometry " + marker), expected)
        self.assertEqual(parse_layout_marker(marker + " host=private-machine"), expected)
        for text in (
            "XCTAssertTrue failed: private filename.gba",
            "/Users/private/path without a marker",
        ):
            with self.subTest(text=text):
                self.assertEqual(parse_layout_marker(text), [])

    def test_invalid_geometry_and_kind_slot_pairs_are_rejected(self):
        prefix = "PLAYSTEAD_LAYOUT_V1 kind=moveUp hittable=true "
        suffix = " pane=(0,0,500,400) window=(0,0,1200,900)"
        for element in ("(0,0,-1,20)", "(0,0,100001,20)", "(0,0,10,20)"):
            text = prefix + f"element={element}" + suffix + " slot=1"
            with self.subTest(element=element):
                self.assertEqual(parse_layout_marker(text), [])


if __name__ == "__main__":
    unittest.main()
