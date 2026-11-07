#!/bin/bash
set -eu
here=$(cd "$(dirname "$0")" && pwd)
work=$(mkdir -p "$1" && cd "$1" && pwd)
ide=$2 package=$3 sources=$4 steps=$5
shots=${6:-$work/shots}
rm -rf "$work/config" "$work/data" "$work/cache" "$work/state" "$work/run" "$work/package" "$work/dconf-keys"
mkdir -p "$work/config/dconf" "$work/data" "$work/cache" "$work/state" "$work/run" "$work/dconf-keys" "$shots"
chmod 700 "$work/run"
cp -a "$package" "$work/package"
cat > "$work/dconf-keys/00-test" <<KEYS
[org/gnome/desktop/input-sources]
sources=$sources
KEYS
dconf compile "$work/config/dconf/user" "$work/dconf-keys"
cat > "$work/session.sh" <<'SESSION'
env | grep '^DBUS_SESSION_BUS_ADDRESS=' > "$IME_WORK/bus.env"
gnome-shell --headless --virtual-monitor 1400x926 --wayland-display swiftcode-ime --no-x11 > "$IME_WORK/shell.log" 2>&1 &
echo $! > "$IME_WORK/shell.pid"
wait
SESSION
chmod +x "$work/session.sh"
env -u WAYLAND_DISPLAY -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS -u IBUS_ADDRESS \
    XDG_CONFIG_HOME="$work/config" XDG_DATA_HOME="$work/data" \
    XDG_CACHE_HOME="$work/cache" XDG_STATE_HOME="$work/state" XDG_RUNTIME_DIR="$work/run" HOME="$work" \
    XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=GNOME IME_WORK="$work" NO_AT_BRIDGE=1 GTK_A11Y=none \
    dbus-run-session -- "$work/session.sh" > "$work/session.log" 2>&1 &
session=$!
for _ in $(seq 100); do [ -S "$work/run/swiftcode-ime" ] && [ -s "$work/bus.env" ] && break; sleep 0.2; done
sleep 4
shell=$(cat "$work/shell.pid")
cleanup() {
    kill "$shell" 2>/dev/null || true
    wait "$session" 2>/dev/null || true
    for e in /proc/[0-9]*/environ; do
        p=${e#/proc/}; p=${p%/environ}
        if [ "$p" = $$ ] || [ ! -r "$e" ]; then continue; fi
        if { tr '\0' '\n' < "$e"; } 2>/dev/null | grep -qxF "XDG_RUNTIME_DIR=$work/run"; then
            echo "stopping leftover $p: $({ tr '\0' ' ' < "/proc/$p/cmdline"; } 2>/dev/null | cut -c1-80)"
            kill "$p" 2>/dev/null || true
        fi
    done
}
trap cleanup EXIT
set -a
. "$work/bus.env"
set +a
unset DISPLAY IBUS_ADDRESS
export XDG_CONFIG_HOME="$work/config" XDG_DATA_HOME="$work/data" XDG_CACHE_HOME="$work/cache" \
    XDG_STATE_HOME="$work/state" XDG_RUNTIME_DIR="$work/run" HOME="$work" WAYLAND_DISPLAY=swiftcode-ime
gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell \
    --method org.freedesktop.DBus.Properties.Set org.gnome.Shell OverviewActive "<false>" > /dev/null
log="$work/ide.log"
sed -e "s|LOG|$log|; s|SHOTS|$shots|" "$steps" > "$work/steps.txt"
WAYLAND_DEBUG=client OV_PLATFORM=sdl SDL_VIDEO_DRIVER=wayland OV_SHOT_REQUEST="$work/shot-request" SWIFTCODE_IDE_IME=1 \
    OV_QUIT_AFTER="${QUIT_AFTER:-25}" "$ide" "$work/package" > "$log" 2>&1 &
idepid=$!
IME_KEYS=gnome OV_SHOT_REQUEST="$work/shot-request" python3 -I "$here/type-keys.py" "$work/steps.txt"
wait "$idepid" || true
grep '^ime' "$log"
echo "--- the IDE's caret rectangles (text-input-v3), window coordinates:"
grep -o 'set_cursor_rectangle([^)]*)' "$log" | uniq
