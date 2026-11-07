#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="$here/../out/guest-tests/stage4"
die() {
    echo "guest-tests/build-stage4.sh: error: $*" >&2
    exit 1
}
[ "$(uname -s)" = "Darwin" ] || die "this script needs macOS (xcrun and the iOS simulator SDK)"
command -v xcrun >/dev/null 2>&1 || die "xcrun not found"
mkdir -p "$out"
out=$(cd "$out" && pwd)
if [ $# -eq 0 ]; then
    set -- $(cd "$here/stage4" && ls *.c | sed 's/\.c$//')
fi
for probe in "$@"; do
    src="$here/stage4/$probe.c"
    [ -f "$src" ] || die "no source $src"
    xcrun --sdk iphonesimulator clang -target arm64-apple-ios27.0-simulator -O2 \
        -o "$out/$probe" "$src" \
        || die "compiling $probe.c failed"
    [ -s "$out/$probe" ] || die "$probe is empty"
    platform=$(xcrun otool -l "$out/$probe" |
        awk '/cmd LC_BUILD_VERSION/ { inbv = 1; next }
             inbv && $1 == "platform" { print $2; exit }')
    case "$platform" in
        7|IOSSIMULATOR) ;;
        "") die "$probe has no LC_BUILD_VERSION" ;;
        *) die "$probe is platform '$platform', expected 7 (iOS simulator)" ;;
    esac
    arch=$(xcrun lipo -archs "$out/$probe")
    [ "$arch" = "arm64" ] || die "$probe is '$arch', expected arm64 only"
    size=$(wc -c < "$out/$probe" | tr -d ' ')
    echo "$out/$probe: $size bytes, arm64, platform $platform"
done
echo "guest-tests/build-stage4.sh: ok"
