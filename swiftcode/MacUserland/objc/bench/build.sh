#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out=${1:?usage: build.sh <out dir>}
mkdir -p "$out/gen"
TARGET=arm64-apple-macos14.0
CC="clang -target $TARGET -O2 -fno-objc-arc"
python3 -I "$here/gen.py" "$out/gen"
sh "$here/build-mac.sh" "$out" "$here/../tests/t_message.m" > /dev/null
lib="$out/libycobjc.dylib"
$CC -c "$here/bench.m" -o "$out/bench.o"
$CC -c "$out/gen/bench_gen.m" -o "$out/bench_gen.o"
$CC -o "$out/bench-apple" "$out/bench.o" "$out/bench_gen.o" -lobjc
$CC -o "$out/bench" "$out/bench.o" "$out/bench_gen.o" -lobjc
$CC -o "$out/bench-swiftcode" "$out/bench.o" "$out/bench_gen.o" "$lib" -Wl,-rpath,@executable_path
ren="python3 -I $here/rename_sections.py"
for t in 0 1 2 3 4; do
    $CC -c "$out/gen/cats$t.m" -o "$out/cats$t.o"
    $CC -bundle -o "$out/cats$t-apple.bundle" "$out/cats$t.o" -bundle_loader "$out/bench-apple" -lobjc
    $CC -bundle -o "$out/cats$t-simd.bundle" "$out/cats$t.o" -bundle_loader "$out/bench" -lobjc
    $CC -bundle -o "$out/cats$t-swiftcode.bundle" "$out/cats$t.o" -bundle_loader "$out/bench-swiftcode" "$lib"
    for v in apple simd swiftcode; do
        cp "$out/cats$t-$v.bundle" "$out/cats$t-$v-control.bundle"
        $ren --to __none_ "$out/cats$t-$v-control.bundle" > /dev/null
        codesign -f -s - "$out/cats$t-$v-control.bundle" 2> /dev/null
    done
    $ren "$out/cats$t-swiftcode.bundle" > /dev/null
    codesign -f -s - "$out/cats$t-swiftcode.bundle" "$out/cats$t-apple.bundle" "$out/cats$t-simd.bundle" 2> /dev/null
done
printf 'int warm_up(void) { return 1; }\n' > "$out/gen/warm.c"
$CC -bundle -o "$out/warm.bundle" "$out/gen/warm.c"
python3 -I "$here/rename_sections.py" "$out/bench-swiftcode" > /dev/null
codesign -f -s - "$out/bench-swiftcode" 2> /dev/null
echo "build.sh: $out/bench-apple $out/bench-swiftcode $out/bench"
