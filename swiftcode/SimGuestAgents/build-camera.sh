#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="${OUT:-$here/out}"
[ "$(uname -s)" = "Darwin" ] || { echo "SimGuestAgents/build-camera.sh: needs macOS" >&2; exit 1; }
mkdir -p "$out/obj-camera"
cc="xcrun --sdk iphonesimulator clang -target arm64-apple-ios27.0-simulator -O2 -Wall -Wextra -Werror -Wno-unused-parameter -fvisibility=hidden"
src="$here/camera"
$cc -fobjc-arc -c -o "$out/obj-camera/YCHost.o" "$src/YCHost.m"
$cc -fobjc-arc -c -o "$out/obj-camera/YCCapture.o" "$src/YCCapture.m"
$cc -fobjc-arc -c -o "$out/obj-camera/YCInit.o" "$src/YCInit.m"
$cc -fno-objc-arc -c -o "$out/obj-camera/YCRuntime.o" "$src/YCRuntime.m"
$cc -c -o "$out/obj-camera/YCPixels.o" "$src/YCPixels.c"
$cc -dynamiclib -install_name @rpath/libSwiftCodeCamera.dylib \
    -framework Foundation -framework CoreFoundation -framework CoreMedia -framework CoreVideo -framework IOSurface \
    -framework QuartzCore -framework CoreGraphics -framework ImageIO \
    -o "$out/libSwiftCodeCamera.dylib" "$out/obj-camera/"*.o
if xcrun dyld_info -dependents "$out/libSwiftCodeCamera.dylib" 2>/dev/null | grep -q AVFoundation \
   || xcrun otool -L "$out/libSwiftCodeCamera.dylib" | grep -q AVFoundation; then
    echo "SimGuestAgents/build-camera.sh: the library must not link AVFoundation" >&2
    exit 1
fi
echo "$out/libSwiftCodeCamera.dylib: $(wc -c < "$out/libSwiftCodeCamera.dylib" | tr -d ' ') bytes"
echo "SimGuestAgents/build-camera.sh: ok"
