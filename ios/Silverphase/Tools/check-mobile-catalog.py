#!/usr/bin/env python3
"""Check every installed iOS catalog against the source inventory."""
import json
from pathlib import Path
import re
import subprocess
import sys

tools = Path(__file__).resolve().parent
inventory = json.loads(Path(sys.argv[1]).read_text() if len(sys.argv) > 1 else
                       subprocess.check_output([str(tools / 'export-mobile-copy.sh')]))
root = tools.parent / 'Resources/MobileCopy'
slot = re.compile(r'\{([1-9][0-9]*)\}')
# A few pre-existing callers format a translated printf template after T(...).
# Translators must keep the entire formatting directive unchanged and in order.
printf = re.compile(r'(?<!%)%[+ #0-]*(?:\d+)?(?:\.\d+)?(?:hh|h|ll|l|z|t|j)?[gGfFeEdDsuixX@]')
category = re.compile(r'\|one:([1-9][0-9]*)$')
named = re.compile(r'\{([a-z][a-zA-Z]*)\}')
file_keys = {Path(r['file']).stem + '|' + r['english'] for r in inventory}
shared_keys = {r['english'] for r in inventory}
for path in sorted(root.glob('*.lproj/MobileCopy.json')):
    values = json.loads(path.read_text())
    problems = []
    for key, value in values.items():
        variant = category.search(key)
        if variant:
            base = key[:variant.start()]
            if (base not in file_keys | shared_keys or base not in values
                or variant[1] not in slot.findall(base) or not value.strip()
                or sorted(slot.findall(base)) != sorted(slot.findall(value))
                or printf.findall(base) != printf.findall(value)
                or sorted(named.findall(base)) != sorted(named.findall(value))):
                problems.append(f'invalid singular variant: {key!r}')
        elif key not in file_keys | shared_keys:
            problems.append(f'unknown key: {key!r}')
    for entry in inventory:
        source = entry['english']
        key = Path(entry['file']).stem + '|' + source
        localized = values.get(key, values.get(source, ''))
        if not localized.strip():
            problems.append(f'missing: {key!r}')
        elif (sorted(slot.findall(source)) != sorted(slot.findall(localized))
              or printf.findall(source) != printf.findall(localized)
              or sorted(named.findall(source)) != sorted(named.findall(localized))):
            problems.append(f'placeholder/format mismatch: {key!r} → {localized!r}')
    if problems:
        sys.exit(f'{path}:\n' + '\n'.join(dict.fromkeys(problems)))
    print(f'{path.parent.stem}: {len(file_keys)} contextual source keys covered')
