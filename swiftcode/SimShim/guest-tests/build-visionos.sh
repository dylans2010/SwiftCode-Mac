#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="${OUT:-$here/../out/guest-tests/visionos}"
[ "$(uname -s)" = "Darwin" ] || { echo "build-visionos.sh: needs macOS" >&2; exit 1; }
mkdir -p "$out"
xcrun --sdk xrsimulator clang -target arm64-apple-xros27.0-simulator -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -framework Foundation -framework UIKit -framework Metal -o "$out/vprobe" "$here/visionos/vprobe.m"
echo "$out/vprobe: $(wc -c < "$out/vprobe" | tr -d ' ') bytes"
xcrun --sdk xrsimulator clang -target arm64-apple-xros27.0-simulator -fobjc-arc -O2 -Wall -Wextra -Werror -dynamiclib \
    -framework Foundation -framework Metal -o "$out/mtlwatch.dylib" "$here/visionos/mtlwatch.m"
echo "$out/mtlwatch.dylib: $(wc -c < "$out/mtlwatch.dylib" | tr -d ' ') bytes"
xcrun --sdk xrsimulator clang -target arm64-apple-xros27.0-simulator -fobjc-arc -O2 -Wall -Wextra -Werror -dynamiclib \
    -framework Foundation -framework Metal -framework IOSurface -lc++ -lMobileGestalt -Wl,-U,_REEngineInitWithConfiguration -o "$out/mtlrec.dylib" "$here/visionos/mtlrec.m"
echo "$out/mtlrec.dylib: $(wc -c < "$out/mtlrec.dylib" | tr -d ' ') bytes"
xcrun --sdk xrsimulator clang -target arm64-apple-xros27.0-simulator -O2 -Wall -Wextra -Werror -o "$out/symaddr" "$here/visionos/symaddr.c"
echo "$out/symaddr: $(wc -c < "$out/symaddr" | tr -d ' ') bytes"
xcrun --sdk xrsimulator swiftc -target arm64-apple-xros27.0-simulator -O -o "$out/rkprobe" "$here/visionos/rkprobe.swift"
echo "$out/rkprobe: $(wc -c < "$out/rkprobe" | tr -d ' ') bytes"
xcrun --sdk xrsimulator clang -target arm64-apple-xros27.0-simulator -O2 -Wall -Wextra -Werror -o "$out/exports" "$here/visionos/exports.c"
echo "$out/exports: $(wc -c < "$out/exports" | tr -d ' ') bytes"
xcrun --sdk xrsimulator clang -target arm64-apple-xros27.0-simulator -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -framework Foundation -framework Metal -framework IOSurface -o "$out/shtex" "$here/visionos/shtex.m"
echo "$out/shtex: $(wc -c < "$out/shtex" | tr -d ' ') bytes"
