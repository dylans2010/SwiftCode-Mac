#!/bin/sh
set -eu
app=$1
dir=$2
show=${3:-0}
timeout=${4:-120}
rm -rf "$dir/shots" "$dir/probe.json" "$dir/probe.json.pid" "$dir/probe.log"
mkdir -p "$dir"
if ! open -n -g --env "SWIFTCODE_LAYOUT_PROBE=$dir/probe.json" --env "SWIFTCODE_LAYOUT_PROBE_SHOTS=$dir/shots" \
    --env "SWIFTCODE_LAYOUT_PROBE_SHOW=$show" --stdout "$dir/probe.log" --stderr "$dir/probe.log" "$app"; then
    echo "layout-probe: open failed; running the executable directly" >&2
    exe=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")
    SWIFTCODE_LAYOUT_PROBE="$dir/probe.json" SWIFTCODE_LAYOUT_PROBE_SHOTS="$dir/shots" SWIFTCODE_LAYOUT_PROBE_SHOW="$show" \
        "$app/Contents/MacOS/$exe" >"$dir/probe.log" 2>&1 &
fi
waited=0
while [ ! -f "$dir/probe.json" ] && [ "$waited" -lt "$timeout" ]; do
    sleep 1
    waited=$((waited + 1))
done
if [ ! -f "$dir/probe.json" ]; then
    echo "layout-probe: no report after ${timeout}s" >&2
    pid=$(cat "$dir/probe.json.pid" 2>/dev/null || true)
    case "$pid" in
        "" | *[!0-9]*) ;;
        *) kill "$pid" 2>/dev/null || true ;;
    esac
    exit 1
fi
waited=0
while [ -f "$dir/probe.json.pid" ] && [ "$waited" -lt 10 ]; do
    sleep 1
    waited=$((waited + 1))
done
