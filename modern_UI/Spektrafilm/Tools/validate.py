#!/usr/bin/env python3
"""Run XCTest with hash-pinned external photos in isolated temporary copies.

Standard library only. Never publishes/copies private photos into the checkout.
Use --scope photos for a zero-skip real-photo gate, full for the integration run.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[3]
MANIFEST = REPO / 'modern_UI/Spektrafilm/SpektrafilmTests/Fixtures/validation-manifest.json'
CASES_MANIFEST = MANIFEST.with_name('release-case-manifest.json')


def sha256(path):
    result = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def run(command, log, cwd=REPO, env=None):
    with log.open('w') as stream:
        return subprocess.run(command, cwd=cwd, env=env, stdout=stream,
                              stderr=subprocess.STDOUT).returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--photos-root', type=Path, required=True)
    parser.add_argument('--scope', choices=('photos', 'full', 'cases'), default='full')
    parser.add_argument('--manifest', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--derived-data', type=Path, default=Path('/tmp/silverphase-validation-dd'))
    parser.add_argument('--batch-count', type=int, default=0)
    parser.add_argument('--batch-format', choices=('jpeg', 'tiff'), default='jpeg')
    args = parser.parse_args()
    if args.batch_count < 0:
        parser.error('--batch-count must be nonnegative')
    root = args.photos_root.expanduser().resolve(strict=True)
    output = (args.output or Path(tempfile.mkdtemp(prefix='silverphase-validation-report-'))).resolve()
    output.mkdir(parents=True, exist_ok=True)
    if (output / 'TestResults.xcresult').exists() or (output / 'summary.json').exists():
        parser.error('output already contains a run; select a new output directory')
    selected_manifest = args.manifest or (CASES_MANIFEST if args.scope == 'cases' else MANIFEST)
    manifest = json.loads(selected_manifest.expanduser().read_text())
    roles = [item['role'] for item in manifest['fixtures']]
    if args.scope == 'cases':
        if not roles or len(roles) != len(set(roles)):
            raise ValueError('cases manifest must contain nonempty distinct roles')
        if args.batch_count:
            parser.error('cases scope exports exactly the pinned manifest; omit --batch-count')
    elif sorted(roles) != sorted(('raw-standard', 'raw-high-resolution', 'encoded-jpeg', 'encoded-tiff')):
        raise ValueError('manifest must contain exactly the four distinct validation roles')
    inputs = []
    for fixture in manifest['fixtures']:
        source = (root / fixture['relative_path']).resolve(strict=True)
        if not source.is_relative_to(root):
            raise ValueError('fixture path escapes photo root')
        digest = sha256(source)
        if digest != fixture['sha256']:
            raise ValueError(f"fixture checksum mismatch: {fixture['role']}")
        inputs.append((source, fixture))
    if args.scope == 'cases' and (len({fixture['sha256'] for _, fixture in inputs}) != len(inputs) or
                                  any(source.suffix.lower() not in {'.arw', '.nef', '.cr2', '.cr3', '.dng', '.raf'} for source, _ in inputs)):
        raise ValueError('cases must be distinct RAW inputs')
    print(f'Validated {len(inputs)} selected photo checksums. Report: {output}', flush=True)
    checks = {}
    checks['project'] = run([sys.executable, 'modern_UI/Spektrafilm/Tools/gen-project.py', '--check'], output / 'project.log')
    checks['resources'] = run(['modern_UI/Spektrafilm/Tools/check-bundle-resources.sh'], output / 'resources.log')
    if any(checks.values()):
        raise RuntimeError('project/resource preflight failed; see logs')
    with tempfile.TemporaryDirectory(prefix='silverphase-validation-work-') as temporary:
        work = Path(temporary)
        mirror = work / 'repo'
        shutil.copytree(REPO, mirror, ignore=shutil.ignore_patterns('.git', 'build', '.venv', '__pycache__', '.DS_Store', 'private-fixtures', 'output'))
        photos = work / 'photos'
        for source, fixture in inputs:
            target = photos / fixture['relative_path']
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        staged_manifest = work / 'fixtures.json'
        staged_manifest.write_text(json.dumps(manifest))
        standard = inputs[0][1] if args.scope == 'cases' else next(item for _, item in inputs if item['role'] == 'raw-standard')
        env = os.environ.copy()
        env['TEST_RUNNER_SILVERPHASE_VALIDATION_PHOTOS'] = str(photos)
        env['TEST_RUNNER_SILVERPHASE_VALIDATION_MANIFEST'] = str(staged_manifest)
        env['TEST_RUNNER_SILVERPHASE_TEST_RAW'] = str(photos / standard['relative_path'])
        batch_hashes = []
        batch_count = len(inputs) if args.scope == 'cases' else args.batch_count
        if batch_count:
            batch = work / 'batch'
            batch.mkdir()
            candidates = [source for source, _ in inputs] if args.scope == 'cases' else sorted(
                path for path in root.rglob('*')
                if path.is_file() and path.suffix.lower() in {'.arw', '.nef', '.cr2', '.cr3', '.dng', '.raf'})
            if len(candidates) < batch_count:
                raise ValueError('not enough distinct RAW files for the requested batch')
            for index, source in enumerate(candidates[:batch_count]):
                target = batch / f'{index:03d}-{source.name}'
                shutil.copyfile(source, target)
                batch_hashes.append({'relative_path': str(source.relative_to(root)), 'sha256': sha256(source)})
            env['TEST_RUNNER_SILVERPHASE_PERF_BATCH_DIR'] = str(batch)
            env['TEST_RUNNER_SILVERPHASE_PERF_BATCH_COUNT'] = str(batch_count)
            env['TEST_RUNNER_SILVERPHASE_PERF_BATCH_FORMAT'] = args.batch_format
            env['TEST_RUNNER_SILVERPHASE_PERF_RESULTS'] = str(output / 'batch.tsv')
        command = ['xcodebuild', '-project', 'modern_UI/Spektrafilm/Spektrafilm.xcodeproj',
                   '-scheme', 'SpektrafilmTests', '-configuration', 'Debug',
                   '-derivedDataPath', str(args.derived_data.resolve()),
                   '-resultBundlePath', str(output / 'TestResults.xcresult')]
        if args.scope == 'cases':
            command += ['-only-testing:SpektrafilmTests/CanvasViewTests',
                        '-only-testing:SpektrafilmTests/DigitalIntermediateExportTests',
                        '-only-testing:SpektrafilmTests/PerformanceStressTests/testRealPhotoBatchExport']
        elif args.scope == 'photos':
            command += [f'-only-testing:SpektrafilmTests/{suite}' for suite in
                        ('CanvasViewTests', 'RealPhotoValidationTests', 'DigitalIntermediateExportTests')]
            if args.batch_count:
                command += ['-only-testing:SpektrafilmTests/PerformanceStressTests/testRealPhotoBatchExport']
        command += ['test']
        print('Running XCTest; detailed progress is in xcodebuild.log.', flush=True)
        code = run(command, output / 'xcodebuild.log', cwd=mirror, env=env)
        for source, fixture in inputs:
            if sha256(source) != fixture['sha256']:
                raise RuntimeError('source photograph changed during validation')
        for fixture in batch_hashes:
            if sha256(root / fixture['relative_path']) != fixture['sha256']:
                raise RuntimeError('batch source photograph changed during validation')
        result = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                                 '--path', str(output / 'TestResults.xcresult'), '--compact'],
                                capture_output=True, text=True)
        summary = json.loads(result.stdout) if result.returncode == 0 else None
        report = {'scope': args.scope, 'preflight': checks, 'exit_code': code,
                  'fixture_manifest': manifest, 'source_photos_unchanged': True,
                  'batch_format': args.batch_format if batch_count else None,
                  'batch_fixtures': batch_hashes, 'xctest': summary,
                  'coverage': ('failed: inspect build/test logs' if code or (summary and summary['failedTests']) else
                               'partial: inspect skipped tests' if summary and summary['skippedTests'] else
                               'selected gate complete' if summary else 'unavailable'),
                  'reference_oracle': 'Historical frozen Python oracle retired; this run is not oracle parity.',
                  'visual_qa': 'Not performed; in-process tests do not establish live-window frame pacing.'}
        (output / 'summary.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        if summary:
            print(f"XCTest: {summary['passedTests']} passed, {summary['failedTests']} failed, {summary['skippedTests']} skipped", flush=True)
        print(f'Report: {output / "summary.json"}', flush=True)
        # A selected photos gate must not succeed by silently skipping its fixtures.
        if code or summary is None or summary['failedTests'] or (args.scope in ('photos', 'cases') and summary['skippedTests']):
            return 1
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, StopIteration) as error:
        print(f'validation failed: {error}', file=sys.stderr)
        sys.exit(1)
