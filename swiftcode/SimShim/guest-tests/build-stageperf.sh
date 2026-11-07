#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="${OUT:-$here/../out/guest-tests/stageperf}"
[ "$(uname -s)" = "Darwin" ] || { echo "build-stageperf.sh: needs macOS" >&2; exit 1; }
mkdir -p "$out"
if [ $# -eq 0 ]; then set -- $(cd "$here/stageperf" && ls p_*.c | sed 's/\.c$//'); fi
for probe in "$@"; do
    case "$probe" in
    p_loadtap)
        xcrun --sdk iphonesimulator clang -target arm64-apple-ios27.0-simulator -O2 -Wall -Wextra -Werror \
            -dynamiclib -install_name @executable_path/libp_loadtap.dylib \
            -o "$out/libp_loadtap.dylib" "$here/stageperf/$probe.c"
        echo "$out/libp_loadtap.dylib: $(wc -c < "$out/libp_loadtap.dylib" | tr -d ' ') bytes"
        continue ;;
    p_cpufeat_bench)
        xcrun --sdk iphonesimulator clang -target arm64-apple-ios27.0-simulator -O2 -Wall -Wextra -Werror \
            -framework Accelerate -framework JavaScriptCore -framework CoreFoundation -framework CoreGraphics \
            -framework ImageIO -lcompression -o "$out/$probe" "$here/stageperf/$probe.c"
        echo "$out/$probe: $(wc -c < "$out/$probe" | tr -d ' ') bytes"
        continue ;;
    esac
    xcrun --sdk iphonesimulator clang -target arm64-apple-ios27.0-simulator -O2 -Wall -Wextra -Werror \
        -o "$out/$probe" "$here/stageperf/$probe.c"
    echo "$out/$probe: $(wc -c < "$out/$probe" | tr -d ' ') bytes"
done
echo "build-stageperf.sh: ok"
