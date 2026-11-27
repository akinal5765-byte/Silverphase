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
media_extensions = {'.png', '.jpg', '.jpeg', '.svg', '.webp', '.gif', '.heic', '.tif', '.tiff', '.exr', '.pdf', '.mp4'}
cover_root = 'modern_UI/Spektrafilm/Spektrafilm/Resources/FilmCovers/'
manifests = {}
for m in (ROOT / 'modern_UI/design/film-artwork').glob('generated-*-manifest.json'):
    for item in json.loads(m.read_text()).get('items', []):
        if 'file' in item:
            manifests[cover_root + item['file']] = str(m.relative_to(ROOT))
        if 'web' in item:
            manifests[item['web']['path']] = str(m.relative_to(ROOT))
website_manifest = "docs/site/media-provenance.json"
website = json.loads((ROOT / website_manifest).read_text())["assets"]
website_scopes = {
    "web-photo": "Published Silverphase website demonstration only. No RAW redistribution or general photograph reuse grant.",
    "web-ui": "Published website screenshot only. No general photograph reuse grant; system UI, fonts and packaging retain their terms.",
}
for name, record in website.items():
    path = Path(name)
    if (path.as_posix() != name or path.parent.as_posix() not in {
            "docs/site/gallery", "docs/site/interface", "docs/site/plates"}
            or path.suffix.lower() not in {".webp", ".mp4"} or record["kind"] not in website_scopes
            or name in manifests or not (ROOT / path).is_file() or name not in names
            or (ROOT / path).is_symlink()):
        raise SystemExit(f"Invalid website media provenance entry: {name}")
entries = []
for name in names:
    path = ROOT / name
    if not path.is_file() or path.suffix.lower() not in media_extensions:
        continue
    if name in manifests:
        kind, evidence = 'generated-cover', manifests[name]
        terms = 'Project-controlled portion: CC-BY-SA-4.0; third-party packaging/brand elements excluded.'
    elif name in website:
        record = website[name]
        if hashlib.sha256(path.read_bytes()).hexdigest() != record["sha256"]:
            raise SystemExit(f"Website media bytes changed; update reviewed provenance for: {name}")
        kind = record["kind"]
        evidence = (f"{website_manifest}: {record['case']} {record['evidence']}; "
                    f"published as {record['published_commit']}.")
        terms = website_scopes[kind]
    elif name.startswith((cover_root, 'modern_UI/film_covers/')):
        kind, evidence = 'legacy-cover', 'Maintainer AI-origin statement, 2026-10-31; exact historical prompt not recorded.'
        terms = 'Project-controlled portion: CC-BY-SA-4.0; third-party packaging/brand elements excluded.'
    elif ('Silverphase' in name and '.icon/' in name) or name.startswith(('design/app-icon/previews/', 'screenshots/app-icon.')):
        kind, evidence = 'icon-artwork', 'design/app-icon/README.md and local vector generators; Git history retains authorship.'
        terms = 'Silverphase-controlled additions: CC-BY-SA-4.0; existing upstream rights and platform-renderer rights retained.'
    elif name in {
        'docs/showcase/01-paper-study.png', 'docs/showcase/02-film-studies.png',
        'docs/showcase/03-800t-night.png', 'docs/showcase/04-film-edge-covers.png',
    }:
        kind, evidence = 'approved-product-showcase', 'docs/showcase/README.md; maintainer-approved project fixtures and release of the derived cards.'
        terms = 'Silverphase project demonstration only for photos. No RAW redistribution; third-party packaging is excluded from the project artwork grant.'
    elif name == 'docs/site/silverphase-icon.png':
        kind, evidence = 'icon-artwork', 'Reduced copy of the tracked screenshots/app-icon.png for the project website.'
        terms = 'Silverphase-controlled additions: CC-BY-SA-4.0; existing upstream rights and platform-renderer rights retained.'
    elif name == 'docs/site/layerlight-icon.png':
        kind, evidence = 'related-app-promotional-icon', 'Reduced copy of the tracked screenshots/related-apps/layerlight-icon.png for owner-requested promotion.'
        terms = 'Layerlight proprietary app icon; promotional identification only, excluded from Silverphase GPL and CC-BY-SA grants.'
    elif name.startswith('screenshots/current/'):
        kind, evidence = 'approved-current-ui-case', 'screenshots/current/manifest.json and maintainer authorization, 2026-10-31.'
        terms = 'Project demonstration screenshot use approved; RAW photographs remain local-only and are not blanket relicensed.'
    elif name.startswith('screenshots/related-apps/'):
        kind, evidence = 'related-app-promotional-icon', 'screenshots/related-apps/layerlight-source.json; app-owner request, 2026-10-31.'
        terms = 'Layerlight proprietary app icon; promotional identification only, excluded from Silverphase GPL and CC-BY-SA grants.'
    elif name.startswith('screenshots/ios/2026-11-27/'):
        record_path = 'screenshots/ios/2026-11-27/manifest.json'
        records = json.loads((ROOT / record_path).read_text())['items']
        approved = next((row for row in records if row['file'] == path.name), None)
        if not approved or approved['sha256'] != hashlib.sha256(path.read_bytes()).hexdigest():
            raise SystemExit(f'Review and record new iOS screenshot bytes: {name}')
        kind, evidence = 'approved-ios-ui-case', record_path + '; native iPhone/iPad simulator capture using maintainer-approved photo inputs.'
        terms = 'Silverphase project presentation only for photos. No RAW redistribution or blanket photo relicensing; system UI, fonts and packaging retain their terms.'
    elif name.startswith('screenshots/ios/2026-11-02/'):
        kind, evidence = 'current-ios-ui-layout-capture', 'screenshots/ios/2026-11-02/manifest.json; native portrait simulator capture with self-authored synthetic gradient, no private photographs.'
        terms = 'Silverphase-controlled UI and synthetic fixture follow project licensing; system UI, fonts and bundled third-party material packaging retain existing rights and notices.'
    elif name in {
        'docs/images/lightroom-classic/01-external-editing-preferences.png',
        'docs/images/lightroom-classic/02-select-silverphase.png',
        'docs/images/lightroom-classic/03-edit-in-silverphase.png',
    }:
        kind, evidence = 'third-party-ui-workflow-reference', 'User-supplied annotated screenshots on 2026-11-09, supplied with a request to document Lightroom Classic external editing.'
        terms = 'Workflow documentation only. Adobe and Apple UI and trademarks retain their respective rights; no new third-party UI licence grant is asserted.'
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
