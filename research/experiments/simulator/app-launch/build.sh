#!/bin/sh
set -e
OUT=${1:?output directory}
HERE=$(cd "$(dirname "$0")" && pwd)
PROBE="$HERE/../ProbeApp"
TARGET=arm64-apple-ios27.0-simulator
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
mkdir -p "$OUT/YcodeProbe.app"
xcrun --sdk iphonesimulator swiftc -target $TARGET -sdk "$SDK" -module-name YcodeProbe \
    -O -o "$OUT/YcodeProbe.app/YcodeProbe" "$PROBE/main.swift"
cp "$PROBE/Info.plist" "$OUT/YcodeProbe.app/Info.plist"
printf 'APPL????' > "$OUT/YcodeProbe.app/PkgInfo"
codesign -s - -f "$OUT/YcodeProbe.app" >/dev/null
xcrun --sdk iphonesimulator clang -target $TARGET -fobjc-arc -O1 -g -Wall \
    -framework Foundation -framework Security -Wl,-sectcreate,__TEXT,__entitlements,"$HERE/ylaunch.entitlements" \
    -o "$OUT/ylaunch" "$HERE/ylaunch.m"
codesign -s - -f "$OUT/ylaunch" >/dev/null
xcrun --sdk iphonesimulator clang -target $TARGET -dynamiclib -O1 -Wall \
    -o "$OUT/lookuptrace.dylib" "$HERE/lookuptrace.c"
codesign -s - -f "$OUT/lookuptrace.dylib" >/dev/null
xcrun --sdk iphonesimulator clang -target $TARGET -dynamiclib -O1 -Wall \
    -o "$OUT/enttrace.dylib" "$HERE/enttrace.c"
codesign -s - -f "$OUT/enttrace.dylib" >/dev/null
echo "built $OUT/enttrace.dylib"
echo "built $OUT/YcodeProbe.app $OUT/ylaunch $OUT/lookuptrace.dylib"
