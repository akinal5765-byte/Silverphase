#!/usr/bin/env python3
"""Exercise the release preflight through the real command, without Xcode."""

import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class ReleasePreflightTests(unittest.TestCase):
    def setUp(self):
        workspace = tempfile.TemporaryDirectory()
        self.addCleanup(workspace.cleanup)
        self.root = Path(workspace.name)
        tools = self.root / 'tools'
        tools.mkdir()
        self.script = tools / 'package-public-release.py'
        shutil.copyfile(Path(__file__).with_name(self.script.name), self.script)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Release Fixture')
        self.git('config', 'user.email', 'release@example.invalid')
        self.git('config', 'commit.gpgSign', 'false')
        self.git('config', 'tag.gpgSign', 'false')
        self.git('config', 'core.hooksPath', '/dev/null')
        self.git('add', 'tools')
        self.git('commit', '-qm', 'First release candidate')
        self.first = self.git('rev-parse', 'HEAD')
        self.git('commit', '--allow-empty', '-qm', 'Second release candidate')
        self.head = self.git('rev-parse', 'HEAD')
        self.output = self.root / 'output' / 'release'

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, text=True).strip()

    def preflight(self, tag, platform='macos', *, build=False, output=None):
        command = [sys.executable, str(self.script), '--platform', platform, '--tag', tag,
                   '--output', str(output or self.output)]
        if not build:
            command.append('--preflight-only')
        return subprocess.run(command, cwd=self.root, text=True, capture_output=True)

    def test_matching_annotated_macos_tag_has_exact_source_url(self):
        self.git('tag', '-a', 'macos-v1.2.3', '-m', 'Release 1.2.3')
        result = self.preflight('macos-v1.2.3')
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertTrue(report['local_tag_verified_at_build'])
        self.assertEqual(report['source_commit'], self.head)
        self.assertEqual(report['source_url'], f'{report["source_repository"]}/tree/{self.head}')
        self.assertFalse(self.output.exists())

    def test_matching_lightweight_ios_tag(self):
        self.git('tag', 'v1.2.3')
        result = self.preflight('v1.2.3', platform='ios')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)['local_tag_verified_at_build'])

    def test_mismatched_tag_stops_real_build_before_output_creation(self):
        self.git('tag', 'macos-v1.2.3', self.first)
        result = self.preflight('macos-v1.2.3', build=True)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn(f'{self.first[:12]}, not HEAD {self.head[:12]}', result.stderr)
        self.assertFalse(self.output.exists())

    def test_missing_local_tag_warns_and_pins_source_for_pre_tag_build(self):
        result = self.preflight('macos-v1.2.3-rc.1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('does not exist locally', result.stderr)
        report = json.loads(result.stdout)
        self.assertFalse(report['local_tag_verified_at_build'])
        self.assertTrue(report['source_url'].endswith('/tree/' + self.head))

    def test_tag_to_non_commit_is_not_a_release_revision(self):
        self.git('tag', 'macos-v1.2.3', 'HEAD^{tree}')
        result = self.preflight('macos-v1.2.3')
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn('does not identify a commit', result.stderr)

    def test_invalid_git_tag_name_fails_even_if_version_pattern_matches(self):
        result = self.preflight('macos-v1.2.3-rc..1')
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn('valid Git tag name', result.stderr)

    def test_preflight_still_rejects_dirty_checkout_and_outside_output(self):
        result = self.preflight('macos-v1.2.3', output=self.root / 'not-output')
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn('directory under output/', result.stderr)
        (self.root / 'local-edit.txt').write_text('Uncommitted changes')
        result = self.preflight('macos-v1.2.3')
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn('exact clean revision', result.stderr)


if __name__ == '__main__':
    unittest.main()
