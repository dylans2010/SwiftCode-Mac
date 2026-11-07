#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
crate=$here/..
out=${1:?usage: build-mac.sh <out dir> <program.m> [sources...]}
src=${2:?usage: build-mac.sh <out dir> <program.m> [sources...]}
shift 2
mkdir -p "$out"
name=$(basename "$src" .m)
TARGET=arm64-apple-macos14.0
lib="$out/libycobjc.dylib"
if [ ! -f "$lib" ] || [ -n "$(find "$crate/src" "$crate/Cargo.toml" -newer "$lib" 2>/dev/null | head -1)" ]; then
    (cd "$crate" && cargo build --release --features host-bench --target-dir target/host-bench)
    clang -target $TARGET -dynamiclib -o "$lib" -install_name @rpath/libycobjc.dylib \
        -Wl,-force_load,"$crate/target/host-bench/release/libycobjc.a" \
        -Wl,-exported_symbols_list,"$crate/exports.txt" -Wl,-dead_strip
fi
clang -target $TARGET -O2 -fno-objc-arc ${CFLAGS:-} -c "$src" -o "$out/$name.o"
extra=""
for f in "$@"; do
    case "$f" in
    *.m | *.c)
        o="$out/$(basename "$f" | sed 's/\.[mc]$//').o"
        clang -target $TARGET -O2 -fno-objc-arc ${CFLAGS:-} -c "$f" -o "$o"
        extra="$extra $o"
        ;;
    esac
done
clang -target $TARGET -o "$out/$name-apple" "$out/$name.o" $extra -lobjc
clang -target $TARGET -o "$out/$name" "$out/$name.o" $extra -lobjc
clang -target $TARGET -o "$out/$name-swiftcode" "$out/$name.o" $extra "$lib" -Wl,-rpath,@executable_path
python3 -I "$here/rename_sections.py" "$out/$name-swiftcode" > /dev/null
codesign -f -s - "$out/$name-swiftcode" 2> /dev/null
echo "build-mac.sh: $out/$name-apple $out/$name-swiftcode $out/$name"
