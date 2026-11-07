#!/bin/bash
set -eu
here=$(cd "$(dirname "$0")" && pwd)
display_kind=$1 im=$2 engine=$3 layout=$4
work=$(mkdir -p "$5" && cd "$5" && pwd)
ide=$6 package=$7 steps=$8
shots=${9:-$work/shots}
case "$display_kind/$im" in
    x11/ibus|x11/fcitx5|sway/fcitx5) ;;
    *) echo "unsupported: $display_kind with $im" >&2; exit 2 ;;
esac
rm -rf "$work/config" "$work/data" "$work/cache" "$work/state" "$work/run" "$work/package"
mkdir -p "$work/config" "$work/data" "$work/cache" "$work/state" "$work/run" "$shots"
chmod 700 "$work/run"
cp -a "$package" "$work/package"
pids=()
cleanup() {
    for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
    sleep 0.5
    for e in /proc/[0-9]*/environ; do
        p=${e#/proc/}; p=${p%/environ}
        if [ "$p" = $$ ] || [ ! -r "$e" ]; then continue; fi
        if { tr '\0' '\n' < "$e"; } 2>/dev/null | grep -qxF "XDG_RUNTIME_DIR=$work/run"; then
            echo "stopping leftover $p: $({ tr '\0' ' ' < /proc/$p/cmdline; } 2>/dev/null | cut -c1-80)"
            kill "$p" 2>/dev/null || true
        fi
    done
}
trap cleanup EXIT
unset DISPLAY WAYLAND_DISPLAY SWAYSOCK DBUS_SESSION_BUS_ADDRESS IBUS_ADDRESS
export XDG_CONFIG_HOME="$work/config" XDG_DATA_HOME="$work/data" XDG_CACHE_HOME="$work/cache" \
    XDG_STATE_HOME="$work/state" XDG_RUNTIME_DIR="$work/run" HOME="$work" \
    GSETTINGS_BACKEND=memory NO_AT_BRIDGE=1 GTK_A11Y=none GTK_USE_PORTAL=0 GIO_USE_VFS=local
dbus-daemon --session --fork --print-address=4 --print-pid=5 4> "$work/bus" 5> "$work/bus.pid"
pids+=("$(cat "$work/bus.pid")")
export DBUS_SESSION_BUS_ADDRESS
DBUS_SESSION_BUS_ADDRESS=$(head -1 "$work/bus")
if [ "$display_kind" = x11 ]; then
    rm -f "$work/display"
    Xvfb -displayfd 3 -screen 0 1600x1000x24 -nolisten tcp 3> "$work/display" > "$work/xvfb.log" 2>&1 &
    pids+=("$!")
    for _ in $(seq 50); do [ -s "$work/display" ] && break; sleep 0.1; done
    export DISPLAY=":$(cat "$work/display")"
    setxkbmap $layout
    keys=xdotool
    export IME_SCREEN_SHOT="python3 -I $here/screen-x11.py"
else
    cat > "$work/sway.conf" <<CONF
output HEADLESS-1 resolution 1600x1000 position 0 0
xwayland disable
default_border none
CONF
    WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 sway -c "$work/sway.conf" > "$work/sway.log" 2>&1 &
    pids+=("$!")
    for _ in $(seq 50); do [ -S "$work/run/wayland-1" ] && break; sleep 0.1; done
    export WAYLAND_DISPLAY=wayland-1
    wtype -s 3600000 &
    pids+=("$!")
    keys=wtype
fi
case "$im" in
    ibus)
        ibus-daemon --xim --replace --verbose > "$work/im.log" 2>&1 &
        pids+=("$!")
        for _ in $(seq 100); do ibus address > /dev/null 2>&1 && break; sleep 0.1; done
        for _ in $(seq 30); do
            ibus engine "$engine" 2> /dev/null && [ "$(ibus engine 2> /dev/null)" = "$engine" ] && break
            sleep 0.5
        done
        echo "input method engine: $(ibus engine)"
        export XMODIFIERS=@im=ibus GTK_IM_MODULE=ibus QT_IM_MODULE=ibus SDL_IM_MODULE=ibus
        ;;
    fcitx5)
        mkdir -p "$work/config/fcitx5"
        cat > "$work/config/fcitx5/profile" <<CONF
[Groups/0]
Name=Test
Default Layout=${layout// /-}
DefaultIM=$engine
[Groups/0/Items/0]
Name=$engine
Layout=
[GroupOrder]
0=Test
CONF
        cat > "$work/config/fcitx5/config" <<CONF
[Behavior/DisabledAddons]
0=chttrans
1=ibusfrontend
2=fcitx4frontend
3=notificationitem
4=kimpanel
5=clipboard
6=cloudpinyin
CONF
        mkdir -p "$work/config/fcitx5/conf"
        if [ "${FCITX_XIM_ON_THE_SPOT:-0}" = 1 ]; then
            printf 'UseOnTheSpot=True\n' > "$work/config/fcitx5/conf/xim.conf"
        fi
        if [ "$display_kind" = sway ]; then
            WAYLAND_DEBUG=client fcitx5 --replace ${FCITX_VERBOSE:+--verbose="$FCITX_VERBOSE"} > "$work/im.log" 2>&1 &
        else
            fcitx5 --replace ${FCITX_VERBOSE:+--verbose="$FCITX_VERBOSE"} > "$work/im.log" 2>&1 &
        fi
        pids+=("$!")
        sleep 3
        export XMODIFIERS=@im=fcitx GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx SDL_IM_MODULE=fcitx
        ;;
esac
log="$work/ide.log"
sed -e "s|LOG|$log|; s|SHOTS|$shots|" "$steps" > "$work/steps.txt"
if [ "$display_kind" = sway ]; then
    WAYLAND_DEBUG=client OV_PLATFORM=sdl SDL_VIDEO_DRIVER=wayland OV_SHOT_REQUEST="$work/shot-request" SWIFTCODE_IDE_IME=1 \
        OV_QUIT_AFTER="${QUIT_AFTER:-25}" "$ide" "$work/package" > "$log" 2>&1 &
else
    OV_PLATFORM=sdl SDL_VIDEO_DRIVER=x11 OV_SHOT_REQUEST="$work/shot-request" SWIFTCODE_IDE_IME=1 \
        OV_QUIT_AFTER="${QUIT_AFTER:-25}" "$ide" "$work/package" > "$log" 2>&1 &
fi
idepid=$!
pids+=("$idepid")
if [ "$display_kind" = x11 ]; then
    for _ in $(seq 100); do grep -q '^ime: ready' "$log" 2>/dev/null && break; sleep 0.1; done
    for w in $(xdotool search --pid "$idepid" --name SwiftCode 2>/dev/null); do xdotool windowfocus "$w" 2>/dev/null || true; done
fi
IME_KEYS=$keys OV_SHOT_REQUEST="$work/shot-request" python3 -I "$here/type-keys.py" "$work/steps.txt"
wait "$idepid" || true
grep '^ime' "$log"
if [ "$display_kind" = sway ]; then
    echo "--- the IDE's caret rectangles (text-input-v3), window coordinates:"
    grep -o 'set_cursor_rectangle([^)]*)' "$log" | uniq
    echo "--- what the compositor told the input method (input-method-v2), surface coordinates:"
    grep -o 'text_input_rectangle([^)]*)' "$work/im.log" | uniq || true
fi
