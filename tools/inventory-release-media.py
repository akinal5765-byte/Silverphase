#!/usr/bin/env python3
"""Inventory candidate visual assets and their provenance evidence, without copying photos."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--check', action='store_true')
a = p.parse_args()
names = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=ROOT)
names = sorted(set(names.decode().rstrip('\0').split('\0')))
media_extensions = {'.png', '.jpg', '.jpeg', '.svg', '.webp', '.gif', '.heic', '.tif', '.tiff', '.exr', '.pdf'}
cover_root = 'modern_UI/Spektrafilm/Spektrafilm/Resources/FilmCovers/'
manifests = {}
for m in (ROOT / 'modern_UI/design/film-artwork').glob('generated-*-manifest.json'):
    for item in json.loads(m.read_text()).get('items', []):
        if 'file' in item:
            manifests[cover_root + item['file']] = str(m.relative_to(ROOT))
entries = []
for name in names:
    path = ROOT / name
    if not path.is_file() or path.suffix.lower() not in media_extensions:
        continue
    if name in manifests:
        kind, evidence = 'generated-cover', manifests[name]
        terms = 'Project-controlled portion: CC-BY-SA-4.0; third-party packaging/brand elements excluded.'
    elif name.startswith((cover_root, 'modern_UI/film_covers/')):
        kind, evidence = 'legacy-cover', 'Maintainer AI-origin statement, 2026-10-31; exact historical prompt not recorded.'
        terms = 'Project-controlled portion: CC-BY-SA-4.0; third-party packaging/brand elements excluded.'
    elif ('Silverphase' in name and '.icon/' in name) or name.startswith(('design/app-icon/previews/', 'screenshots/app-icon.')):
        kind, evidence = 'icon-artwork', 'design/app-icon/README.md and local vector generators; Git history retains authorship.'
        terms = 'Silverphase-controlled additions: CC-BY-SA-4.0; existing upstream rights and platform-renderer rights retained.'
    elif name.startswith('screenshots/current/'):
        kind, evidence = 'approved-current-ui-case', 'screenshots/current/manifest.json and maintainer authorization, 2026-10-31.'
        terms = 'Project demonstration screenshot use approved; RAW photographs remain local-only and are not blanket relicensed.'
    elif name.startswith('screenshots/related-apps/'):
        kind, evidence = 'related-app-promotional-icon', 'screenshots/related-apps/layerlight-source.json; app-owner request, 2026-10-31.'
        terms = 'Layerlight proprietary app icon; promotional identification only, excluded from Silverphase GPL and CC-BY-SA grants.'
    elif name.startswith(('modern_UI/design/snapshots/', 'modern_UI/reference_layout/', 'screenshots/', 'PRD/')):
        kind, evidence = 'historical-ui-reference', 'Inherited upstream UI/design history; some later typography captures reuse historical material.'
        terms = 'No new Silverphase photograph or third-party UI licence grant. Not a current product example.'
    elif name.startswith('modern_UI/control_asset/'):
        kind, evidence = 'inherited-ui-vector', 'Upstream design resource retained in repository history.'
        terms = 'Retain upstream notices; no new Silverphase artwork grant for inherited source.'
    else:
        raise SystemExit(f'Unclassified visual asset: {name}')
    entries.append({'path': name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                    'kind': kind, 'evidence': evidence, 'rights_scope': terms})
result = {'scope': 'Current tracked and nonignored candidate visual assets; no RAW originals or private input folders copied.',
          'policy': 'license/ARTWORK.md', 'entries': entries}
text = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
out = ROOT / 'license/media-inventory.json'
if a.check:
    if not out.is_file() or out.read_text() != text:
        raise SystemExit('Media inventory is stale; review and run tools/inventory-release-media.py')
else:
    out.write_text(text)
print(f'PASS: {len(entries)} visual assets classified and hashed; this is provenance tracking, not rights clearance.')
