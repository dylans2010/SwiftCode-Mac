#!/bin/sh
set -eu
root=$PWD
arch=$(uname -m)
export HOME="$root/.home"
mkdir -p "$HOME"
python3 packaging/flatpak/prepare-swift-deps.py deps swiftcode swiftcode/Tools/swiftcode-swb
swift_build() {
    (cd "$1" && swift build -c release --force-resolved-versions -Xswiftc -use-ld=lld -Xlinker -ltinfo \
        -Xlinker -rpath -Xlinker '$ORIGIN/../lib' -Xlinker -rpath -Xlinker '$ORIGIN/../../..' \
        -Xswiftc -file-prefix-map -Xswiftc "$PWD=$2" -Xcc -ffile-prefix-map="$PWD=$2" \
        -Xcxx -ffile-prefix-map="$PWD=$2" --product "$3")
}
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
for folder in "$bin"/*.resources "$bin"/*.bundle "$swb"/*.resources "$swb"/*.bundle; do
    if [ -d "$folder" ]; then cp -R "$folder" /app/bin/; fi
done
install -Dm755 swiftcode/scripts/swiftcode-ios-build-linux /app/scripts/swiftcode-ios-build-linux
install -m755 packaging/flatpak/host-tool.sh /app/libexec/swiftcode-host/host-tool
for tool in swift swiftc swift-build swift-test swift-package swift-run sourcekit-lsp lldb lldb-dap clang clang++ \
            git ssh scp rsync make pkg-config; do
    ln -sf host-tool "/app/libexec/swiftcode-host/$tool"
done
if [ "$arch" = aarch64 ]; then
    sim=/app/lib/swiftcode-sim
    (cd swiftcode && sh SimShim/build.sh)
    (cd swiftcode && SWIFTCODE="$bin/swiftcode" sh SimHostLibs/build.sh)
    (cd swiftcode && sh SimGuestFrameworks/build.sh)
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
    find "$sim" \( -name '*.o' -o -name '*.ld' -o -name '*.elf' \) -delete
    cat > /app/bin/swiftcode-sim <<'SCRIPT'
sim=$(cd "$(dirname "$(readlink -f "$0")")/../lib/swiftcode-sim" && pwd)
export SWIFTCODE_SIM_TREE="${SWIFTCODE_SIM_TREE:-$sim}"
exec "$sim/scripts/swiftcode-sim.sh" "$@"
SCRIPT
    chmod 755 /app/bin/swiftcode-sim
    cp -L /usr/lib/sdk/llvm22/lib/libLLVM.so.22.1 /app/lib/
fi
python3 packaging/flatpak/copy-runtime-libraries.py /app/swift/usr/lib/swift/linux /app/lib /app/bin /app/lib
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
