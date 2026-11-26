#!/usr/bin/env python3
"""Regression checks for the stage-local-materials fingerprint consumer."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest

ROOT = Path(__file__).resolve().parents[1]
STAGE = ROOT / "tools/stage-local-materials.py"
FINGERPRINT = ROOT / "tools/material-pack-fingerprint.py"
MANIFEST = "material-pack-fingerprint.json"


class MaterialPackTest(unittest.TestCase):
    def run_script(self, *args, ok=True):
        result = subprocess.run([sys.executable, *map(str, args)], capture_output=True,
                                env={**os.environ, "SILVERPHASE_LOCAL_MATERIALS": "0"})
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr.decode())
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def test_staged_public_bundle_and_local_difference(self):
        with TemporaryDirectory() as tmp:
            resources = Path(tmp) / "Resources"
            engine = resources / "engine"
            shutil.copytree(ROOT / "engine/resources", engine)
            product = ROOT / "engine/resources_product"
            for source in (product / "profiles").glob("*.json"):
                shutil.copyfile(source, engine / "profiles" / source.name)
            shutil.copyfile(product / "paper_grades.json", engine / "paper_grades.json")
            self.run_script(STAGE, resources)
            manifest = engine / MANIFEST
            public = json.loads(manifest.read_text())
            self.assertFalse(public["includes_local_materials"])
            self.assertGreater(public["profile_count"], 0)
            self.assertRegex(public["sha256"], r"^[0-9a-f]{64}$")
            self.assertNotIn(tmp, manifest.read_text())
            self.run_script(FINGERPRINT, engine, "--check")

            # Paths, mtimes and unrelated binary artifacts are not the material data.
            copied = Path(tmp) / "AppResources" / "engine"
            shutil.copytree(engine, copied, copy_function=shutil.copyfile)
            (copied / "spektrafilm.metallib").write_bytes(b"ignored shader")
            self.run_script(FINGERPRINT, copied, "--check")

            local = engine / "profiles" / "test_experimental.json"
            local.write_text("{}\n")
            self.run_script(FINGERPRINT, engine, "--check", ok=False)
            self.run_script(FINGERPRINT, engine)
            staged = json.loads(manifest.read_text())
            self.assertNotEqual(staged["sha256"], public["sha256"])
            self.assertTrue(staged["includes_local_materials"])
            self.assertEqual(staged["profile_count"], public["profile_count"] + 1)
            self.assertNotIn("test_experimental", manifest.read_text())
            self.run_script(STAGE, resources)
            self.assertFalse(local.exists())
            self.assertEqual(json.loads(manifest.read_text()), public)

            filters = engine / "neutral_print_filters.json"
            with filters.open("ab") as f:
                f.write(b"\n")
            self.run_script(FINGERPRINT, engine, "--check", ok=False)
            filters.unlink()
            self.run_script(FINGERPRINT, engine, ok=False)


if __name__ == "__main__":
    unittest.main()
