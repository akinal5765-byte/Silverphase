#!/usr/bin/env python3
"""Build public Release binaries without personal signing/provisioning material."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DESKTOP = ROOT / 'modern_UI/Spektrafilm'
SOURCE_REPOSITORY = 'https://github.com/akinal5765-byte/Silverphase'
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--platform', choices=['macos', 'ios'], required=True)
p.add_argument('--tag', required=True, help='For example macos-v1.1.0 or v1.1.1')
p.add_argument('--output', type=Path, required=True)
p.add_argument('--derived-data', type=Path, help='Optional existing Xcode cache; not included in release assets')
p.add_argument('--preflight-only', action='store_true', help='Check release source and output path without building')
a = p.parse_args()
version_tag = a.tag.removeprefix('macos-') if a.platform == 'macos' else a.tag
if not re.fullmatch(r'v\d+\.\d+\.\d+(?:-[A-Za-z0-9.]+)?', version_tag):
    p.error('Use a version tag without path characters')
out = a.output.expanduser().resolve()
if ROOT not in out.parents or not out.is_relative_to(ROOT / 'output'):
    p.error('Use an ignored directory under output/')
if subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT):
    p.error('Commit the source first so the binaries identify an exact clean revision')
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
tag_ref = 'refs/tags/' + a.tag
if subprocess.run(['git', 'check-ref-format', tag_ref], cwd=ROOT).returncode:
    p.error('Use a valid Git tag name')
tag_status = subprocess.run(['git', 'show-ref', '--verify', '--quiet', tag_ref], cwd=ROOT).returncode
if tag_status == 0:
    tagged = subprocess.run(['git', 'rev-parse', '--verify', '--quiet', tag_ref + '^{commit}'],
                            cwd=ROOT, text=True, capture_output=True)
    if tagged.returncode:
        p.error(f'Tag {a.tag!r} does not identify a commit')
    if tagged.stdout.strip() != commit:
        p.error(f'Tag {a.tag!r} points to {tagged.stdout.strip()[:12]}, not HEAD {commit[:12]}; '
                'check out the intended release revision before packaging')
elif tag_status == 1:
    print(f'warning: tag {a.tag!r} does not exist locally; before publishing, '
          f'verify that the release tag points to {commit}', file=sys.stderr)
else:
    p.error(f'Could not inspect local release tag {a.tag!r}')
source = {'tag': a.tag, 'source_commit': commit, 'source_repository': SOURCE_REPOSITORY,
          'source_url': f'{SOURCE_REPOSITORY}/tree/{commit}', 'local_tag_verified_at_build': tag_status == 0}
if a.preflight_only:
    print(json.dumps(source, indent=2))
    raise SystemExit(0)
out.mkdir(parents=True, exist_ok=True)
version = version_tag[1:].split('-', 1)[0]
env = dict(os.environ, SILVERPHASE_LOCAL_MATERIALS='0')
log = (out / ('build-' + a.platform + '.log')).open('w')

def run(args, **kwargs):
    return subprocess.run(list(map(str, args)), cwd=ROOT, env=env, check=True,
                          stdout=log, stderr=subprocess.STDOUT, **kwargs)

def capture(args):
    return subprocess.check_output(list(map(str, args)), cwd=ROOT, env=env, text=True, stderr=subprocess.STDOUT)

work = out / 'work' / a.platform
work.mkdir(parents=True, exist_ok=True)
derived = a.derived_data.resolve() if a.derived_data else work / 'DerivedData'
if a.platform == 'macos':
    run(['engine/build.sh', 'bundle'])
    project, scheme, product, resdir = DESKTOP / 'Spektrafilm.xcodeproj', 'Spektrafilm', 'Release', 'Contents/Resources/Resources'
    extra = ['-destination', 'generic/platform=macOS']
else:
    project, scheme, product, resdir = ROOT / 'ios/Silverphase/Silverphase.xcodeproj', 'Silverphase', 'Release-iphoneos', 'AppResources'
    extra = ['-sdk', 'iphoneos', '-destination', 'generic/platform=iOS']
run(['xcodebuild', '-project', project, '-scheme', scheme, '-configuration', 'Release',
     '-derivedDataPath', derived, *extra, 'CODE_SIGNING_ALLOWED=NO',
     'ENABLE_DEBUG_DYLIB=NO', 'build'])
source_app = derived / 'Build/Products' / product / 'Silverphase.app'
app = work / ('dmg/Silverphase.app' if a.platform == 'macos' else 'Payload/Silverphase.app')
if app.parent.exists():
    shutil.rmtree(app.parent)
app.parent.mkdir(parents=True)
shutil.copytree(source_app, app, symlinks=True)
resources = app / resdir
info = plistlib.loads((app / ('Contents/Info.plist' if a.platform == 'macos' else 'Info.plist')).read_bytes())
assert info['CFBundleShortVersionString'] == version, 'Tag and application versions disagree'
assert info['CFBundleIdentifier'] == 'com.silverphase.editor', 'Unexpected Silverphase application identity'
public = json.loads((DESKTOP / 'Spektrafilm/Resources/StockCatalog.json').read_text())['stocks']
shipped = json.loads((resources / 'StockCatalog.json').read_text())['stocks']
assert shipped == public and not any(s['id'].endswith('_experimental') for s in shipped)
run([sys.executable, ROOT / 'tools/stock-artwork.py', '--resources', resources])
assert not (resources / 'LocalMaterials').exists(), 'Private local catalog was packaged'
assert not list((resources / 'engine/profiles').glob('*_experimental.json'))
assert len(list((resources / 'engine/profiles').glob('*.json'))) == len(public)
notices = DESKTOP / 'Spektrafilm/Resources/Licenses'
for f in notices.iterdir():
    if f.is_file():
        assert (resources / 'Licenses' / f.name).read_bytes() == f.read_bytes(), f.name
private_ext = {'.arw', '.nef', '.dng', '.p12', '.pfx', '.pem', '.key', '.spektrapair', '.mobileprovision'}
assert not any(f.suffix.lower() in private_ext or f.name.endswith('.spektra.json') for f in app.rglob('*'))
# Check actual deployed binaries, not only build settings.
magic = {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
executables = []
floor = 15 if a.platform == 'macos' else 18
minimum = info['LSMinimumSystemVersion' if a.platform == 'macos' else 'MinimumOSVersion']
assert int(minimum.split('.')[0]) == floor
for f in app.rglob('*'):
    if not f.is_file() or f.is_symlink():
        continue
    with f.open('rb') as stream:
        is_macho = stream.read(4) in magic
    if is_macho:
        archs = capture(['lipo', '-archs', f]).strip()
        assert archs == 'arm64', (f.name, archs)
        build = capture(['xcrun', 'vtool', '-show-build', f])
        minos = re.search(r'\bminos\s+(\S+)', build).group(1)
        assert int(minos.split('.')[0]) <= floor, (f.name, minos)
        executables.append(f)
assert executables, 'No application executable found'
metal_platforms = []
for f in app.rglob('*.metallib'):
    header = capture(['xcrun', '-sdk', 'macosx' if a.platform == 'macos' else 'iphoneos', 'metal-readobj', '--file-headers', f])
    major = int(re.search(r'PlatformMajor:\s*(\d+)', header).group(1))
    assert major <= floor, (f.name, major)
    metal_platforms.append({'path': str(f.relative_to(app)), 'minimum_platform_major': major})
manifest = {**source,
            'platform': a.platform, 'version': version, 'build': info['CFBundleVersion'],
            'architecture': 'arm64', 'minimum_os': minimum, 'public_materials': len(public),
            'local_materials': 0, 'notices': sorted(f.name for f in notices.iterdir() if f.is_file()),
            'metallibs': metal_platforms,
            'signing': 'ad-hoc, no Developer ID, not notarized' if a.platform == 'macos' else 'unsigned; user must sign and provision',
            'required_entitlements': {} if a.platform == 'macos' else plistlib.loads((ROOT / 'ios/Silverphase/Silverphase.entitlements').read_bytes())}
(resources / 'PublicRelease.json').write_text(json.dumps(manifest, indent=2) + '\n')
if a.platform == 'macos':
    main = app / 'Contents/MacOS/Silverphase'
    assert executables == [main], 'Unexpected extra macOS binary in application bundle'
    assert list(main.parent.iterdir()) == [main], 'Unexpected macOS executable or wrapper'
    run(['codesign', '--force', '--sign', '-', '--timestamp=none', '--options', 'runtime',
         '--entitlements', DESKTOP / 'Spektrafilm/Spektrafilm.entitlements', app])
    run(['codesign', '--verify', '--deep', '--strict', app])
    os.symlink('/Applications', app.parent / 'Applications')
    shutil.copytree(resources / 'Licenses', app.parent / 'Licenses')
    (app.parent / 'INSTALL.txt').write_text(
        'Silverphase ' + a.tag + '\nApple Silicon; macOS 15 or later.\nDrag Silverphase to Applications.\n\n'
        'Upgrading from 1.3.1 or earlier? Keep the old app and back up your edits and presets before replacing it. '
        'The new app does not migrate them automatically. Copy only the files you recognize; keep the old copies until the new app opens your edits correctly.\n'
        '从 1.3.1 或更早版本升级：替换前保留旧应用并备份编辑与导出配方。新版不会自动迁移；请按指南选择性复制，确认编辑能正常打开后再处理旧文件。\n'
        f'Migration / 迁移指南: {SOURCE_REPOSITORY}/blob/{commit}/docs/MACOS-IDENTITY-UPGRADE.md\n\n'
        'This build has no Developer ID signature and is not notarized.\n'
        'If macOS blocks it, review System Settings > Privacy & Security and use Open Anyway only if you trust this download.\n'
        'Do not disable Gatekeeper globally.\n'
        f'Source: {source["source_url"]}\nCommit: {commit}\n')
    asset = out / ('Silverphase-' + version_tag[1:] + '-macOS-arm64.dmg')
    run(['hdiutil', 'create', '-volname', 'Silverphase ' + version_tag[1:], '-srcfolder', app.parent,
         '-ov', '-format', 'UDZO', asset])
    run(['hdiutil', 'verify', asset])
else:
    for f in executables:
        subprocess.run(['codesign', '--remove-signature', str(f)], stdout=log, stderr=subprocess.STDOUT)
        signed = subprocess.run(['codesign', '-dv', str(f)], stdout=log, stderr=subprocess.STDOUT)
        assert signed.returncode != 0, 'iOS binary still has a signature'
    for f in app.rglob('_CodeSignature'):
        if f.is_dir(): shutil.rmtree(f)
    assert not list(app.rglob('embedded.mobileprovision'))
    asset = out / ('Silverphase-' + version_tag[1:] + '-iOS-unsigned.ipa')
    run(['ditto', '-c', '-k', '--norsrc', '--noextattr', '--noqtn', '--keepParent', app.parent, asset])
    run(['unzip', '-tq', asset])
manifest['asset'] = asset.name
manifest['bytes'] = asset.stat().st_size
manifest['sha256'] = hashlib.sha256(asset.read_bytes()).hexdigest()
(out / (a.platform + '-build.json')).write_text(json.dumps(manifest, indent=2) + '\n')
log.close()
print(json.dumps(manifest, indent=2))
