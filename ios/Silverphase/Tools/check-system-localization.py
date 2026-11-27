#!/usr/bin/env python3
"""Verify permission and camera action localization source files or built bundles."""
import json
import plistlib
from pathlib import Path
import re
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
    'Could not open the library', 'OK',
    'Open Camera', 'Open the film camera in Silverphase.',
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

# Compare against the Swift declarations so changing an invocation phrase cannot
# silently leave the dedicated system catalog stale.
shortcut_source = (root / 'Sources/MobileCameraShortcut.swift').read_text()
metadata = re.findall(r'(?:LocalizedStringResource = |IntentDescription\(|shortTitle: )"([^"]+)"', shortcut_source)
assert set(metadata) == {'Open Camera', 'Open the film camera in Silverphase.'} and len(metadata) == 3, metadata
phrase_source = re.search(r'phrases: \[(.*?)\]', shortcut_source, re.S)[1]
token = '${applicationName}'
phrases = [value.replace(r'\(.applicationName)', token)
           for value in re.findall(r'"([^"]+)"', phrase_source)]
catalog = json.loads((root / 'Resources/AppShortcuts.xcstrings').read_text())
assert catalog['sourceLanguage'] == 'en' and set(catalog['strings']) == {phrases[0]}
localizations = catalog['strings'][phrases[0]]['localizations']
assert set(localizations) == set(locales)
phrase_sets = {}
for locale, entry in localizations.items():
    row = entry['stringSet']
    values = row['values']
    assert row['state'] == 'translated' and len(set(values)) == len(values) == len(phrases), locale
    assert all(text.count(token) == 1 for text in values), locale
    phrase_sets[locale] = values
assert phrase_sets['en'] == phrases
assert all(values != phrases for locale, values in phrase_sets.items() if locale != 'en')

if len(sys.argv) > 1:
    app = Path(sys.argv[1])
    for locale, values in phrase_sets.items():
        compiled = table(app / (locale + '.lproj') / 'AppShortcuts.strings')
        assert set(compiled.values()) == set(values) and len(compiled) == len(values), locale
    extracted = json.loads((app / 'Metadata.appintents/extract.actionsdata').read_text())
    action_id = 'OpenSilverphaseCameraIntent'
    action = extracted['actions'][action_id]
    assert action['title']['key'] == metadata[0]
    assert action['descriptionMetadata']['descriptionText']['key'] == metadata[1]
    shortcut, = [row for row in extracted['autoShortcuts'] if row['actionIdentifier'] == action_id]
    assert shortcut['shortTitle']['key'] == metadata[2]
    assert [row['key'] for row in shortcut['phraseTemplates']] == phrases
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
