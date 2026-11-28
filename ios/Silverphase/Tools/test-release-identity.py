#!/usr/bin/env python3
"""Regression tests for the source-project App Store identity preflight."""
from collections import Counter
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import unittest


CHECKER = Path(__file__).with_name("check-release-identity.py")
SPEC = spec_from_file_location("check_release_identity", CHECKER)
identity = module_from_spec(SPEC)
SPEC.loader.exec_module(identity)


class ProjectIdentityTests(unittest.TestCase):
    def setUp(self):
        self.document = identity.load_project(identity.PROJECT)
        self.objects = self.document["objects"]
        project = self.objects[self.document["rootObject"]]
        self.targets = {
            self.objects[reference]["name"]: self.objects[reference]
            for reference in project["targets"]
        }

    def listing(self, target):
        return self.objects[self.targets[target]["buildConfigurationList"]]

    def settings(self, target, configuration):
        for reference in self.listing(target)["buildConfigurations"]:
            record = self.objects[reference]
            if record["name"] == configuration:
                return record["buildSettings"]
        self.fail(f"missing {target} {configuration} fixture")

    def bundle_id_counts(self):
        key = identity.BUNDLE_ID_SETTING
        return Counter(
            record["buildSettings"][key]
            for record in self.objects.values()
            if key in record.get("buildSettings", {})
        )

    def test_current_generated_project(self):
        identity.check_project()

    def test_extension_ids_swapped_in_release_with_same_global_counts(self):
        key = identity.BUNDLE_ID_SETTING
        control = self.settings("CameraControl", "Release")
        locked = self.settings("LockedCamera", "Release")
        before = self.bundle_id_counts()
        control[key], locked[key] = locked[key], control[key]
        self.assertEqual(before, self.bundle_id_counts())
        with self.assertRaisesRegex(ValueError, r"\(Release\): expected com\.silverphase\.editor\.(camera-control|locked-camera)"):
            identity.check_project_document(self.document)

    def test_target_configuration_lists_swapped_with_same_global_counts(self):
        app = self.targets["Silverphase"]
        tests = self.targets["SilverphaseUITests"]
        key = "buildConfigurationList"
        before = self.bundle_id_counts()
        app[key], tests[key] = tests[key], app[key]
        self.assertEqual(before, self.bundle_id_counts())
        with self.assertRaisesRegex(ValueError, r"Silverphase(UITests)? \(Debug\): expected"):
            identity.check_project_document(self.document)

    def test_missing_release_reference_does_not_pass_with_orphaned_config(self):
        configs = self.listing("CameraControl")["buildConfigurations"]
        before = self.bundle_id_counts()
        configs[:] = [ref for ref in configs if self.objects[ref]["name"] != "Release"]
        self.assertEqual(before, self.bundle_id_counts())
        with self.assertRaisesRegex(ValueError, r"CameraControl: missing build configurations.*Release"):
            identity.check_project_document(self.document)

    def test_unexpected_device_specific_override(self):
        settings = self.settings("CameraControl", "Release")
        settings[identity.BUNDLE_ID_SETTING + "[sdk=iphoneos*]"] = identity.APP_ID
        with self.assertRaisesRegex(ValueError, r"CameraControl \(Release\).*\[sdk=iphoneos\*\]"):
            identity.check_project_document(self.document)


if __name__ == "__main__":
    unittest.main()
