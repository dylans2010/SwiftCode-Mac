#!/bin/sh
set -eu
LC_ALL=C
export LC_ALL
here=$(cd "$(dirname "$0")" && pwd)
out="$here/out"
common="$here/../SimHostLibs/common"
CLANG=${CLANG:-clang}
LD64=${LD64:-ld64.lld}
NM=${NM:-llvm-nm}
OBJDUMP=${OBJDUMP:-llvm-objdump}
PYTHON=${PYTHON:-python3}
die() { echo "SimGuestFrameworks/build.sh: error: $*" >&2; exit 1; }
say() { echo "SimGuestFrameworks/build.sh: $*"; }
if [ "${1:-}" = clean ]; then rm -rf "$out"; exit 0; fi
for tool in "$CLANG" "$LD64" "$NM" "$OBJDUMP" "$PYTHON"; do
    command -v "$tool" >/dev/null 2>&1 || die "'$tool' not found in PATH"
done
TARGET=arm64-apple-ios27.0-simulator
CFLAGS="-target $TARGET -std=c11 -nostdlib -ffreestanding -fno-builtin -fno-stack-protector -fblocks
 -fno-exceptions -fPIC -O2 -fvisibility=hidden -fno-common -fno-strict-aliasing
 -mno-outline-atomics -Wall -Wextra -Werror"
mkdir -p "$out"
"$PYTHON" -I "$common/abi_check.py" --clang "$CLANG" --ld "$LD64" --objdump "$OBJDUMP" \
    --python "$PYTHON" --out "$out/abi-check" -- $CFLAGS -I"$common" || die "the ABI check failed"
write_tbds() {
    n=0
    grep -v '^#' "$1" | while read -r install symbols; do
        [ -n "$install" ] || continue
        n=$((n + 1))
        {
            echo "--- !tapi-tbd"
            echo "tbd-version:     4"
            echo "targets:         [ arm64-ios-simulator ]"
            echo "install-name:    \"$install\""
            echo "current-version: 1"
            echo "compatibility-version: 1"
            echo "exports:"
            echo "  - targets:     [ arm64-ios-simulator ]"
            echo "    symbols:"
            for s in $symbols; do echo "      - \"$s\""; done
            echo "..."
        } > "$2/import-$n.tbd"
    done
}
fw="$out/SimFramebuffer.framework"
obj="$out/obj/SimFramebuffer"
rm -rf "$obj" "$fw"
mkdir -p "$obj" "$fw"
"$CLANG" $CFLAGS -c -o "$obj/simframebuffer.o" "$here/SimFramebuffer/simframebuffer.c" || die "compiling simframebuffer.c failed"
"$PYTHON" -I "$common/strip_platform.py" "$obj/simframebuffer.o" || die "strip_platform failed"
write_tbds "$here/SimFramebuffer/imports.txt" "$obj"
"$LD64" -arch arm64 -platform_version ios-simulator 27.0 27.1 -dylib \
    -install_name @rpath/SimFramebuffer.framework/SimFramebuffer -current_version 1.0.0 -compatibility_version 1.0.0 \
    -fixup_chains -no_adhoc_codesign -o "$fw/SimFramebuffer" "$obj/simframebuffer.o" $(ls "$obj"/import-*.tbd) \
    || die "linking SimFramebuffer failed"
"$NM" -gU -j "$fw/SimFramebuffer" | sed 's/^_//' | sort -u > "$obj/exports.txt"
missing=$(grep -v '^#' "$here/SimFramebuffer/required.txt" | tr ' ' '\n' | grep -v '^$' | sort -u | comm -23 - "$obj/exports.txt")
[ -z "$missing" ] || die "SimFramebuffer does not export: $missing"
say "$fw/SimFramebuffer: $(wc -c < "$fw/SimFramebuffer" | tr -d ' ') bytes, $(wc -l < "$obj/exports.txt" | tr -d ' ') exports, all 61 required names"
fw="$out/SimHID.framework"
obj="$out/obj/SimHID"
rm -rf "$obj" "$fw"
mkdir -p "$obj" "$fw"
"$CLANG" $CFLAGS -c -o "$obj/simhid.o" "$here/SimHID/simhid.c" || die "compiling simhid.c failed"
"$PYTHON" -I "$common/strip_platform.py" "$obj/simhid.o" || die "strip_platform failed"
write_tbds "$here/SimHID/imports.txt" "$obj"
"$LD64" -arch arm64 -platform_version ios-simulator 27.0 27.1 -dylib \
    -install_name @rpath/SimHID.framework/SimHID -current_version 1.0.0 -compatibility_version 1.0.0 \
    -fixup_chains -no_adhoc_codesign -o "$fw/SimHID" "$obj/simhid.o" $(ls "$obj"/import-*.tbd) \
    || die "linking SimHID failed"
cp "$here/SimHID/Info.plist" "$fw/Info.plist"
"$NM" -m "$fw/SimHID" | grep -q "__mod_init_func\|__init_offsets\|make_class" || say "warning: no initializer section found in SimHID"
say "$fw: $(wc -c < "$fw/SimHID" | tr -d ' ') bytes"
HOSTCC=${HOSTCC:-cc}
if command -v "$HOSTCC" >/dev/null 2>&1; then
    "$HOSTCC" -std=c11 -Wall -Wextra -Werror -O1 -o "$out/obj/orientation_test" "$here/SimHID/tests/orientation_test.c" -lm \
        || die "compiling the orientation test failed"
    "$out/obj/orientation_test" || die "the orientation test failed"
fi
