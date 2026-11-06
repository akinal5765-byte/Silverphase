#!/bin/bash
# Sign an unsigned device build with an existing local development profile.
# Device/team/profile details belong in the local invocation, not source control.
set -euo pipefail
app=${1:?Usage: SIGN_IDENTITY=... sign-device.sh APP PROFILE CONTROL_PROFILE LOCKED_CAMERA_PROFILE}
profile=${2:?Pass a local development provisioning profile}
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to a valid local Apple Development identity}"
task_entitlements=$(mktemp /tmp/silverphase-signing.XXXXXX)
trap 'rm -f "$task_entitlements"' EXIT
sign_bundle() {
    local bundle=$1 bundle_profile=$2 requested_path=${3:-}
    python3 - "$bundle" "$bundle_profile" "$task_entitlements" "$requested_path" "$profile" <<'PY'
import fnmatch,plistlib,subprocess,sys
from pathlib import Path
app,profile,output,requested_path,host_profile=sys.argv[1:]
app,profile,output=map(Path,(app,profile,output))
info=plistlib.loads((app/'Info.plist').read_bytes())
p=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(profile)]))
team=p['TeamIdentifier'][0]
host=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',host_profile]))
if team != host['TeamIdentifier'][0]:
    sys.exit('Extension and app profiles must belong to the same team')
identity=team+'.'+info['CFBundleIdentifier']
e=dict(p['Entitlements'])
if not fnmatch.fnmatchcase(identity,e['application-identifier']):
    sys.exit('Profile does not cover this bundle identifier')
if not p.get('ProvisionedDevices') or not e.get('get-task-allow'):
    sys.exit('An existing device development profile is required')
requested=plistlib.loads(Path(requested_path).read_bytes()) if requested_path else {}
for key,value in requested.items():
    if e.get(key) != value: sys.exit('Profile is missing required capability: '+key+'; regenerate it with Xcode automatic signing')
e.update(requested)
e['application-identifier']=identity
e['keychain-access-groups']=[identity]
output.write_bytes(plistlib.dumps(e))
PY
    cp "$bundle_profile" "$bundle/embedded.mobileprovision"
    codesign --force --sign "$SIGN_IDENTITY" --entitlements "$task_entitlements" "$bundle"
}

control="$app/PlugIns/CameraControl.appex"
locked_camera="$app/Extensions/LockedCamera.appex"
if [[ -d "$control" || -d "$locked_camera" ]]; then
    control_profile=${3:?Pass the CameraControl development profile}
    locked_camera_profile=${4:?Pass the LockedCamera development profile}
fi
# Xcode Debug's main executable can use a separate debug dylib. Sign nested
# code first, then seal the bundle with its application entitlements.
while IFS= read -r -d '' library; do
    codesign --force --sign "$SIGN_IDENTITY" "$library"
done < <(find "$app" -name '*.dylib' -type f -print0)
if [[ -d "$control" ]]; then sign_bundle "$control" "$control_profile"; fi
if [[ -d "$locked_camera" ]]; then sign_bundle "$locked_camera" "$locked_camera_profile"; fi
sign_bundle "$app" "$profile" "$(dirname "$0")/../Silverphase.entitlements"
codesign --verify --deep --strict "$app"
