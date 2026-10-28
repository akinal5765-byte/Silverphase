#!/bin/bash
# Sign an unsigned device build with an existing local development profile.
# Device/team/profile details belong in the local invocation, not source control.
set -euo pipefail
app=${1:?Usage: SIGN_IDENTITY=... sign-device.sh APP PROFILE}
profile=${2:?Pass a local development provisioning profile}
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to a valid local Apple Development identity}"
task_entitlements=$(mktemp /tmp/silverphase-signing.XXXXXX)
trap 'rm -f "$task_entitlements"' EXIT
python3 - "$app" "$profile" "$task_entitlements" "$(dirname "$0")/../Silverphase.entitlements" <<'PY'
import fnmatch,plistlib,subprocess,sys
from pathlib import Path
app,profile,output,requested_path=map(Path,sys.argv[1:])
info=plistlib.loads((app/'Info.plist').read_bytes())
p=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(profile)]))
team=p['TeamIdentifier'][0]
identity=team+'.'+info['CFBundleIdentifier']
e=dict(p['Entitlements'])
if not fnmatch.fnmatchcase(identity,e['application-identifier']):
    sys.exit('Profile does not cover this bundle identifier')
if not p.get('ProvisionedDevices') or not e.get('get-task-allow'):
    sys.exit('An existing device development profile is required')
requested=plistlib.loads(requested_path.read_bytes())
for key,value in requested.items():
    if e.get(key) != value: sys.exit('Profile is missing required capability: '+key+'; regenerate it with Xcode automatic signing')
e.update(requested)
e['application-identifier']=identity
e['keychain-access-groups']=[identity]
output.write_bytes(plistlib.dumps(e))
PY
cp "$profile" "$app/embedded.mobileprovision"
# Xcode Debug's main executable can use a separate debug dylib. Sign nested
# code first, then seal the bundle with its application entitlements.
while IFS= read -r -d '' library; do
    codesign --force --sign "$SIGN_IDENTITY" "$library"
done < <(find "$app" -name '*.dylib' -type f -print0)
codesign --force --sign "$SIGN_IDENTITY" --entitlements "$task_entitlements" "$app"
codesign --verify --deep --strict "$app"
