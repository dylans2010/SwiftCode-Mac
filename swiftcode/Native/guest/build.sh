#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
libs=${1:?usage: build.sh <dir with SwiftCode libsystem_kernel.dylib>}
out="$here/../out"
mkdir -p "$out"
[ "$(uname -s)" = Darwin ] || { echo "build.sh: needs macOS" >&2; exit 1; }
xcrun --sdk iphonesimulator clang -target arm64-apple-ios27.0-simulator -O2 \
    -nostdlib -fno-stack-protector -fno-builtin -ffreestanding \
    -o "$out/nt_probe" "$here/nt_probe.c" "$libs/libsystem_kernel.dylib"
xcrun otool -l "$out/nt_probe" | awk '/cmd LC_BUILD_VERSION/{b=1} b&&/platform/{print "platform", $2; exit}'
echo "build.sh: $out/nt_probe ok"
