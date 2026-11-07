#!/bin/sh
tool=$(basename "$0")
on_host='PATH="$HOME/.local/share/swiftly/bin:$HOME/.swiftly/bin:$PATH"
if ! command -v "$1" >/dev/null 2>&1; then
    case "$1" in
        swift*|sourcekit-lsp|lldb*|clang*)
            echo "SwiftCode: no Swift toolchain was found on this computer ($1 is missing)." >&2
            echo "The SwiftCode Flatpak builds with the Swift toolchain installed on the host. Install Swift 6 or newer from https://www.swift.org/install/linux/ and try again." >&2 ;;
        *)
            echo "SwiftCode: $1 was not found on this computer. Install it with your package manager and try again." >&2 ;;
    esac
    exit 127
fi
exec "$@"'
pick_shell='script=$1; shift
shell=$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f7)
case "$shell" in
    */bash|*/zsh|*/ksh|*/ksh93|*/mksh) [ -x "$shell" ] && exec "$shell" -lc "$script" swiftcode-host-tool "$@" ;;
esac
if /bin/sh -lc : </dev/null >/dev/null 2>&1; then
    exec /bin/sh -lc "$script" swiftcode-host-tool "$@"
fi
exec /bin/sh -c "$script" swiftcode-host-tool "$@"'
set -- /bin/sh -c "$pick_shell" swiftcode-host-tool "$on_host" "$tool" "$@"
for name in $(env | sed -n 's/^\(SWIFTCODE_[A-Za-z0-9_]*\|SWIFT[A-Za-z0-9_]*\|NO_COLOR\|TERM\|CC\|CXX\|SSH_AUTH_SOCK\|GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do
    case "$name" in SWIFTCODE|SWIFTCODE_SWB) continue ;; esac
    eval "value=\${$name}"
    set -- "--env=$name=$value" "$@"
done
if ! flatpak-spawn --host /bin/true 2>/dev/null; then
    echo "SwiftCode: cannot reach the host to run $tool. The Flatpak needs the permission --talk-name=org.freedesktop.Flatpak (flatpak override --user --talk-name=org.freedesktop.Flatpak io.github.MarcoDotIO.Ycode)." >&2
    exit 127
fi
exec flatpak-spawn --host --watch-bus --directory="$PWD" "$@"
