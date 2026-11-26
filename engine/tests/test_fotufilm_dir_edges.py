"""Portable checks for the DIR diagnostic; these do not run either film engine."""
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import fotufilm_dir_edges as probe


class SyntheticSession:
    def __init__(self, pixels, recipe):
        self.pixels = pixels
        self.reply = {"params": dict(recipe, input_color_space="ProPhoto RGB",
                                     input_cctf_decoding=False, output_color_space="ProPhoto RGB",
                                     output_cctf_encoding=True)}
        self.active = recipe["dir_couplers_active"]
        self.tiers = []

    def set_params(self, delta):
        self.active = delta["dir_couplers_active"]

    def render(self, tier):
        self.tiers.append(tier)
        out = (self.pixels * 10000).round().astype(np.uint16)
        if self.active and self.pixels[0, 0, 0] == self.pixels[0, -1, 0]:
            out[:, :, 0] += 2
            out[:, :, 1] -= 1
        return out, None

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        pass


class SyntheticEngine:
    build_info = "test double (not a native capture)"

    def __init__(self):
        self.sessions = []

    def open(self, pixels, recipe):
        session = SyntheticSession(pixels, recipe)
        self.sessions.append(session)
        return session

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        pass


class DirEdgesTest(unittest.TestCase):
    def test_reports_both_directions_and_null_for_zero_span(self):
        row = np.full((probe.WIDTH, 3), (100, 200, 300), dtype=float)
        row[512:] = (200, 100, 300)
        row[507] = (80, 190, 290)
        row[516] = (225, 220, 320)
        result = probe.edge_channels(row)
        self.assertEqual(result["left_codes"], [100, 200, 300])
        self.assertEqual(result["right_codes"], [200, 100, 300])
        self.assertEqual(result["overshoot_percent"], [25.0, 20.0, None])
        self.assertEqual(result["undershoot_percent"], [20.0, 0.0, None])

    def test_weighted_measurement_matches_legacy_gate(self):
        row = np.full((probe.WIDTH, 3), 100, dtype=float)
        row[512:] = 200
        row[516] = 240
        self.assertAlmostEqual(probe.edge_overshoot(row), 40.0)

    def check_main(self, args, engine):
        with patch.object(sys, "argv", ["fotufilm_dir_edges.py", "--profile",
                                       "fujifilm_pro_160ns_fotufilm", *args]), \
             patch.object(probe, "Engine", return_value=engine), \
             redirect_stdout(io.StringIO()) as out:
            probe.main()
        self.assertIn("fujifilm_pro_160ns_fotufilm: worst sampled overshoot 0.00%", out.getvalue())

    def test_default_does_not_render_flat_fields(self):
        engine = SyntheticEngine()
        self.check_main([], engine)
        self.assertEqual(len(engine.sessions), 6)

    def test_report_uses_full_renders_and_signed_uint16_code_deltas(self):
        engine = SyntheticEngine()
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "edge.json"
            self.check_main(["--report", str(path)], engine)
            report = json.loads(path.read_text())
        self.assertEqual(len(engine.sessions), 2 * (3 + 5))
        self.assertTrue(all(s.tiers == ["full", "full"] for s in engine.sessions))
        self.assertEqual(report["engine_build"], engine.build_info)
        [stock] = report["profiles"]
        self.assertEqual(stock["print_stock"], "kodak_portra_endura")
        self.assertEqual(stock["colour"]["output_color_space"], "ProPhoto RGB")
        for condition in stock["conditions"]:
            self.assertEqual(condition["edges"][0]["off"]["overshoot_percent"], [0, 0, 0])
            self.assertEqual([x["ev_from_018"] for x in condition["flats"]], list(probe.FLAT_EVS))
            self.assertTrue(all(x["on_minus_off_codes"] == [2, -1, 0] for x in condition["flats"]))


if __name__ == "__main__":
    unittest.main()
