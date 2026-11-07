#!/bin/bash
set -u
OUT=${1:?out dir}
HERE=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$OUT"
if [ -z "${INSIDE_SESSION:-}" ]; then
    INSIDE_SESSION=1 exec dbus-run-session -- "$0" "$OUT"
fi
pause() { timeout "$1" tail -f /dev/null; }
export OV_PLATFORM=sdl OV_ATSPI_TRACE=1 OV_SETTINGS_PORTAL=0
echo "session bus: $DBUS_SESSION_BUS_ADDRESS" > "$OUT/session.log"
gdbus call --session --dest org.a11y.Bus --object-path /org/a11y/bus --method org.a11y.Bus.GetAddress >> "$OUT/session.log" 2>&1
cd "$HERE"
OV_QUIT_AFTER=${QUIT_AFTER:-45} OV_SCREENSHOT="$OUT/atspi-final.png" timeout 90 .build/debug/ov-mini-ide > "$OUT/app.log" 2>&1 &
APP=$!
for _ in $(seq 1 100); do grep -q "embedded" "$OUT/app.log" 2>/dev/null && break; pause 0.1; done
pause 1
if [ -n "${XDOTOOL:-}" ]; then X=(--xdotool "$XDOTOOL"); else X=(); fi
python3 -I Scripts/atspi_client.py ov-mini-ide "${X[@]}" > "$OUT/client.log" 2>&1
echo "client exit $?" >> "$OUT/client.log"
wait $APP
echo "app exit $?" >> "$OUT/app.log"
grep -E "^(PASS|FAIL|RESULT)" "$OUT/client.log"
grep -E "^state:" "$OUT/app.log"
