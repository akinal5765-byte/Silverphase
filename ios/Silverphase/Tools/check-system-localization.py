#!/usr/bin/env python3
"""Verify permission and camera action localization source files or built bundles."""
import json
import plistlib
from pathlib import Path
import subprocess
import sys


def table(path):
    data = subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', '--', str(path)])
    return json.loads(data)


root = Path(__file__).resolve().parents[1]
locales = tuple(sorted(folder.stem for folder in (root / 'Resources/System').glob('*.lproj')))
camera = 'NSCameraUsageDescription'
base = plistlib.loads((root / 'Info.plist').read_bytes())
permission = {key: value for key, value in base.items() if key.endswith('UsageDescription')}
actions = {
    'Silverphase Camera', 'Open the Silverphase camera after unlocking your device.',
    'Open Silverphase Camera', 'Silverphase Screen', 'Camera', 'Screen',
}
expected = {
    ('System', 'InfoPlist.strings'): set(permission),
    ('System', 'Localizable.strings'): actions,
    ('LockedCamera', 'InfoPlist.strings'): {camera},
}
for (directory, filename), keys in expected.items():
    for locale in locales:
        path = root / 'Resources' / directory / (locale + '.lproj') / filename
        values = table(path)
        assert values.keys() == keys and all(values.values()), path
        if locale == 'en' and filename == 'InfoPlist.strings':
            assert values == {key: permission[key] for key in keys}, path
        if directory == 'LockedCamera':
            host = root / 'Resources/System' / (locale + '.lproj') / filename
            assert values[camera] == table(host)[camera], path
        if locale == 'en' and filename == 'Localizable.strings':
            assert all(k == v for k, v in values.items()), path

if len(sys.argv) > 1:
    app = Path(sys.argv[1])
    for bundle, tables in {
        app: {'InfoPlist.strings': 'System', 'Localizable.strings': 'System'},
        app / 'PlugIns/CameraControl.appex': {'Localizable.strings': 'System'},
        app / 'Extensions/LockedCamera.appex': {
            'InfoPlist.strings': 'LockedCamera', 'Localizable.strings': 'System',
        },
    }.items():
        for locale in set(locales) - {'en', 'zh-Hans', 'zh-Hant'}:
            relative = Path(locale + '.lproj') / 'MobileCopy.json'
            assert json.loads((bundle / relative).read_text()) == json.loads(
                (root / 'Resources/MobileCopy' / relative).read_text()), bundle
        for filename, directory in tables.items():
            for locale in locales:
                relative = Path(locale + '.lproj') / filename
                assert table(bundle / relative) == table(root / 'Resources' / directory / relative), bundle

print('System localization verified: ' + ', '.join(locales))
