#!/bin/sh
# The SwiftCode module of the Flatpak: runs inside flatpak-builder, in the unpacked
# source, with no network. See io.github.MarcoDotIO.Ycode.yml.
set -eu

root=$PWD
arch=$(uname -m)
export HOME="$root/.home"
mkdir -p "$HOME"

python3 packaging/flatpak/prepare-swift-deps.py deps swiftcode swiftcode/Tools/swiftcode-swb

# Source paths in the binaries become relative; lld because the runtime has no gold.
# The package runs from wherever it is unpacked: libraries are found relative to
# the binary, from bin/ and from lib/swiftcode-sim/.build/release/. llbuild asks for
# ncurses for its terminal queries, which this runtime keeps in libtinfo.
# shellcheck disable=SC2016 # $ORIGIN is for the dynamic linker
swift_build() { # package-dir label product
    (cd "$1" && swift build -c release --force-resolved-versions -Xswiftc -use-ld=lld -Xlinker -ltinfo \
        -Xlinker -rpath -Xlinker '$ORIGIN/../lib' -Xlinker -rpath -Xlinker '$ORIGIN/../../..' \
        -Xswiftc -file-prefix-map -Xswiftc "$PWD=$2" -Xcc -ffile-prefix-map="$PWD=$2" \
        -Xcxx -ffile-prefix-map="$PWD=$2" --product "$3")
}

# What every package ships. swiftcode-ide comes first: it builds most of the rest.
tools="swiftcode-ide swiftcode swiftcodebuild swiftcode-bsp swiftcode-sim-viewer"
[ "$arch" = aarch64 ] && tools="$tools swiftcode-simd swiftcode-simhost"
for tool in $tools SwiftCodeGaugeAgent; do
    swift_build swiftcode swiftcode "$tool"
done
for tool in swiftcode-swb SWBBuildServiceBundle; do
    swift_build swiftcode/Tools/swiftcode-swb swiftcode-swb "$tool"
done

bin=$(cd swiftcode && swift build -c release --show-bin-path)
swb=$(cd swiftcode/Tools/swiftcode-swb && swift build -c release --show-bin-path)
install -d /app/bin /app/lib /app/libexec/swiftcode-host /app/share/doc/swiftcode
for tool in $tools; do
    [ "$tool" = swiftcode-simd ] || install -m755 "$bin/$tool" /app/bin/
done
install -m755 "$bin/libSwiftCodeGaugeAgent.so" /app/lib/
install -m755 "$swb/swiftcode-swb" "$swb/SWBBuildServiceBundle" /app/bin/
# SwiftPM resource folders: a tool looks for them next to itself (the UI's fonts,
# swift-build's specifications, both open source; see THIRD_PARTY_NOTICES.md).
for folder in "$bin"/*.resources "$bin"/*.bundle "$swb"/*.resources "$swb"/*.bundle; do
    if [ -d "$folder" ]; then cp -R "$folder" /app/bin/; fi
done

# The script a run on a simulator host builds with (ShellRemoteRun.toolsRoot finds
# a scripts/ folder up to three levels above the executable).
install -Dm755 swiftcode/scripts/swiftcode-ios-build-linux /app/scripts/swiftcode-ios-build-linux

# Tools that run on the host, through flatpak-spawn.
install -m755 packaging/flatpak/host-tool.sh /app/libexec/swiftcode-host/host-tool
for tool in swift swiftc swift-build swift-test swift-package swift-run sourcekit-lsp lldb lldb-dap clang clang++ \
            git ssh scp rsync make pkg-config; do
    ln -sf host-tool "/app/libexec/swiftcode-host/$tool"
done

# aarch64: the simulator tools, laid out like the source tree the scripts and
# swiftcode-simd expect (they look for each other by relative path).
if [ "$arch" = aarch64 ]; then
    sim=/app/lib/swiftcode-sim
    (cd swiftcode && sh SimShim/build.sh)
    (cd swiftcode && SWIFTCODE="$bin/swiftcode" sh SimHostLibs/build.sh)
    (cd swiftcode && sh SimGuestFrameworks/build.sh)
    # libLLVM is in /app/lib, three levels up from swiftcode-airc. Not LDFLAGS: under
    # Ninja the $ORIGIN in it is lost (the 1.0.0-beta.1 binary had /../../..).
    # shellcheck disable=SC2016 # $ORIGIN is for the dynamic linker
    SWIFTCODE_AIRC_RPATH='$ORIGIN/../../..' PKG_CONFIG_PATH=/app/lib/pkgconfig LLVM_DIR=/usr/lib/sdk/llvm22/lib/cmake/llvm \
        PATH="/usr/lib/sdk/llvm22/bin:$PATH" sh swiftcode/Translator/build.sh "$root/airc-build"
    install -d "$sim/.build/release" "$sim/scripts"
    install -m755 "$bin/swiftcode-simd" "$root/airc-build/swiftcode-airc" "$sim/.build/release/"
    ln -sf ../lib/swiftcode-sim/.build/release/swiftcode-simd /app/bin/swiftcode-simd
    ln -sf ../lib/swiftcode-sim/.build/release/swiftcode-airc /app/bin/swiftcode-airc
    install -m755 swiftcode/scripts/swiftcode-sim.sh swiftcode/scripts/swiftcode-sim-serve "$sim/scripts/"
    for part in SimShim SimHostLibs SimGuestFrameworks; do
        install -d "$sim/$part"
        cp -R "swiftcode/$part/out" "$sim/$part/"
    done
    # Build leftovers are not shipped (objects, linker scripts, listings).
    find "$sim" \( -name '*.o' -o -name '*.ld' -o -name '*.elf' \) -delete
    # Relative to where the package is.
    cat > /app/bin/swiftcode-sim <<'SCRIPT'
#!/bin/sh
sim=$(cd "$(dirname "$(readlink -f "$0")")/../lib/swiftcode-sim" && pwd)
export SWIFTCODE_SIM_TREE="${SWIFTCODE_SIM_TREE:-$sim}"
exec "$sim/scripts/swiftcode-sim.sh" "$@"
SCRIPT
    chmod 755 /app/bin/swiftcode-sim
    # libLLVM for swiftcode-airc, from the SDK extension.
    cp -L /usr/lib/sdk/llvm22/lib/libLLVM.so.22.1 /app/lib/
fi

# The Swift runtime libraries the tools load, and nothing else of the toolchain.
python3 packaging/flatpak/copy-runtime-libraries.py /app/swift/usr/lib/swift/linux /app/lib /app/bin /app/lib

# Desktop integration.
id=io.github.MarcoDotIO.Ycode
install -Dm644 "packaging/flatpak/$id.desktop" "/app/share/applications/$id.desktop"
install -Dm644 "packaging/flatpak/$id.metainfo.xml" "/app/share/metainfo/$id.metainfo.xml"
if [ -d packaging/icon/hicolor ]; then
    install -d /app/share/icons
    cp -R packaging/icon/hicolor /app/share/icons/
else
    echo "build-swiftcode: warning: no packaging/icon/hicolor; the package has no icon" >&2
fi

install -m644 LICENSE THIRD_PARTY_NOTICES.md /app/share/doc/swiftcode/
