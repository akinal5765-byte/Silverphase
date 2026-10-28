#!/bin/bash
# Run after building Debug. Pick a simulator explicitly; never guess among devices.
set -euo pipefail
if [[ $# -lt 2 ]]; then echo "Usage: $0 SIMULATOR_UDID /absolute/path/to/Silverphase.app [LAUNCH_ARGS...]" >&2; exit 2; fi
device=$1
app=$2
shift 2
xcrun simctl install "$device" "$app"
xcrun simctl terminate "$device" com.silverphase.editor >/dev/null 2>&1 || true
container=$(xcrun simctl get_app_container "$device" com.silverphase.editor data)
report_name=smoke-report.json
for argument in "$@"; do
    case "$argument" in
        --flat-import-regression) report_name=flat-import-report.json ;;
        --raw-import-regression) report_name=raw-import-report.json ;;
    esac
done
report="$container/Documents/$report_name"
# Installation preserves app data. A previous report must never count as this
# launch's result (including the deliberately broken regression run).
rm -f "$report"
xcrun simctl launch "$device" com.silverphase.editor --smoke-test "$@"
for ((attempt=0; attempt<60; attempt++)); do
    if [[ -f "$report" ]]; then
        cat "$report"
        python3 - "$report" <<'PY'
import json,sys
with open(sys.argv[1]) as f: result=json.load(f)
if not result.get('passed'): sys.exit(1)
PY
        exit $?
    fi
    sleep 1
done
echo "No smoke report after 60 seconds: $report" >&2
exit 1
