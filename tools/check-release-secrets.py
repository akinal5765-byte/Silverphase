#!/usr/bin/env python3
"""Run Gitleaks locally on a named ref and candidate source files, with redaction."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--gitleaks', default='gitleaks', help='Gitleaks 8.30.1 executable')
p.add_argument('--ref', default='main', help='Published history candidate (default: main)')
p.add_argument('--output', type=Path, required=True, help='New local report directory outside Git')
a = p.parse_args()
scanner = shutil.which(a.gitleaks)
if not scanner:
    p.error('Gitleaks executable not found; use --gitleaks /path/to/gitleaks')
version = subprocess.check_output([scanner, 'version'], text=True).strip()
if version != '8.30.1':
    p.error(f'Expected the reviewed Gitleaks 8.30.1, got {version}')
ref = subprocess.check_output(['git', 'rev-parse', '--verify', a.ref + '^{commit}'], cwd=ROOT, text=True).strip()
out = a.output.expanduser().resolve()
if out == ROOT or ROOT in out.parents:
    p.error('Keep potentially sensitive reports outside the source repository')
out.mkdir(parents=True, exist_ok=False)
env = os.environ.copy()
for key in ('GITLEAKS_CONFIG', 'GITLEAKS_CONFIG_TOML'):
    env.pop(key, None)
common = ['--redact=100', '--ignore-gitleaks-allow', '--no-banner', '--no-color',
          '--report-format=json', '--config', str(ROOT / '.gitleaks.toml')]
results = []
with tempfile.TemporaryDirectory(prefix='silverphase-source-scan-') as temp:
    candidate = Path(temp)
    names = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=ROOT)
    count = 0
    for name in set(os.fsdecode(names).rstrip('\0').split('\0')):
        source = ROOT / name
        if source.is_symlink():
            raise SystemExit(f'Review source symlink before scanning: {name}')
        if source.is_file():
            target = candidate / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            count += 1
    for scope, command in [('history', ['git', str(ROOT), '--log-opts=' + ref + ' --full-history']),
                           ('candidate', ['dir', str(candidate), '--max-archive-depth=2'])]:
        report = out / f'{scope}-redacted.json'
        with (out / f'{scope}.log').open('w') as log:
            code = subprocess.run([scanner, *command, *common, '--report-path', str(report)],
                                  cwd=ROOT, env=env, stdout=log, stderr=log).returncode
        findings = json.loads(report.read_text()) if report.is_file() else None
        results.append({'scope': scope, 'exit_code': code,
                        'findings': len(findings) if isinstance(findings, list) else None})
summary = {'scanner': 'Gitleaks', 'version': version, 'ref': a.ref, 'commit': ref,
           'candidate_files': count, 'results': results,
           'limits': 'Pattern-based local scan; excludes reflogs, unreachable objects and ignored files. Not proof of absence of secrets.'}
(out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))
raise SystemExit(0 if all(r['exit_code'] == 0 and r['findings'] == 0 for r in results) else 1)
