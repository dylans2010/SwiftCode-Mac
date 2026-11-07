#!/bin/sh
set -e
DEV=${1:?device udid}
OUT=${2:?build dir}
DATA="$HOME/Library/Developer/CoreSimulator/Devices/$DEV/data"
spawn() { xcrun simctl spawn "$DEV" "$OUT/ylaunch" "$@"; }
spawn uninstall-ix dev.ycode.probe || true
spawn install-ix "$OUT/YcodeProbe.app"
spawn lookup dev.ycode.probe
mkdir -p "$DATA/tmp/ycode"
rm -f "$DATA/tmp/ycode/probe.err"
spawn open-fbs dev.ycode.probe --err /tmp/ycode/probe.err --out /tmp/ycode/probe.out \
    --arg FROM-YLAUNCH --env YCODE_PROBE=ylaunch
sleep 3
sed -n '/== YCODE-PROBE BEGIN/,/== YCODE-PROBE END/p' "$DATA/tmp/ycode/probe.err" | grep -v '^env \|^image '
