#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
swiftcode_dir=$(cd "$here/.." && pwd)
root=$(cd "$swiftcode_dir/.." && pwd)
cd "$swiftcode_dir"
OUT=${1:-.build-ide/app}
VERSION=$(cat VERSION)
BUILD_NUMBER=${SWIFTCODE_BUILD_NUMBER:-1}
ARCHS=${SWIFTCODE_ARCHS:-arm64}
BUILD_ROOT=${SWIFTCODE_BUILD_ROOT:-.build-release}
ICON=${SWIFTCODE_ICON_ICNS:-$root/packaging/icon/SwiftCode.icns}
IDENTITY=${SWIFTCODE_SIGN_IDENTITY:--}
MINIMUM_SYSTEM=15.0
HOST_ARCH=$(uname -m)
PRODUCTS="SwiftCodeApp swiftcode-bsp"
HELPERS="swiftcode-bsp"
if [ "${SWIFTCODE_APP_MINIMAL:-0}" = 1 ]; then
    ARCHS=$HOST_ARCH
else
    PRODUCTS="$PRODUCTS swiftcode swiftcodebuild swiftcode-sim-viewer swiftcode-simhost SwiftCodeTestAgent"
    HELPERS="swiftcode-bsp swiftcode swiftcodebuild swiftcode-sim-viewer swiftcode-simhost"
fi
triple_for() {
    [ "$1" = "$HOST_ARCH" ] || echo "--triple $1-apple-macosx$MINIMUM_SYSTEM"
}
swift_build() {
    (cd "$1" && swift build -c release --scratch-path "$2" $(triple_for "$3") \
        -Xswiftc -file-prefix-map -Xswiftc "$2=build" -Xswiftc -file-prefix-map -Xswiftc "$PWD=$4" \
        -Xcc -ffile-prefix-map="$2=build" -Xcc -ffile-prefix-map="$PWD=$4" \
        -Xcxx -ffile-prefix-map="$2=build" -Xcxx -ffile-prefix-map="$PWD=$4" --product "$5" >&2)
}
SCRATCH_BASE=$(mkdir -p "$BUILD_ROOT" && cd "$BUILD_ROOT" && pwd)
SWB_BASE=${SWIFTCODE_SWB_BUILD_ROOT:-/tmp/swiftcode-release-$(id -u)}
mkdir -p "$SWB_BASE"
for arch in $ARCHS; do
    for product in $PRODUCTS; do
        echo "make-app: building $product ($arch)" >&2
        swift_build "$swiftcode_dir" "$SCRATCH_BASE/$arch" "$arch" swiftcode "$product"
    done
    if [ "${SWIFTCODE_APP_MINIMAL:-0}" != 1 ]; then
        for product in swiftcode-swb SWBBuildServiceBundle; do
            echo "make-app: building $product ($arch)" >&2
            swift_build "$swiftcode_dir/Tools/swiftcode-swb" "$SWB_BASE/swb-$arch" "$arch" swiftcode-swb "$product"
        done
    fi
done
bin_dir() {
    swift build -c release --scratch-path "$1" $(triple_for "$2") --show-bin-path
}
APP="$OUT/SwiftCode.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version)
install_binary() {
    tmp=$(mktemp -d)
    slices=""
    for arch in $ARCHS; do
        case "$1" in
            swiftcode-swb|swbuild|SWBBuildServiceBundle) dir=$(bin_dir "$SWB_BASE/swb-$arch" "$arch") ;;
            *) dir=$(bin_dir "$SCRATCH_BASE/$arch" "$arch") ;;
        esac
        src="$dir/$1"
        slice="$tmp/$arch"
        if [ "$3" = 1 ]; then
            vtool -set-build-version macos "$MINIMUM_SYSTEM" "$SDK_VERSION" -replace -output "$slice" "$src" 2>/dev/null \
                || cp "$src" "$slice"
        else
            cp "$src" "$slice"
        fi
        strip -S -x "$slice" 2>/dev/null || true
        otool -l "$slice" | awk '/LC_RPATH/ { f = 1 } f && / path / { print $2; f = 0 }' | while read -r rpath; do
            case "$rpath" in
                @*|/usr/lib/swift) ;;
                *) install_name_tool -delete_rpath "$rpath" "$slice" 2>/dev/null ;;
            esac
        done
        slices="$slices $slice"
    done
    lipo -create $slices -output "$2"
    chmod 755 "$2"
    rm -rf "$tmp"
}
install_binary SwiftCodeApp "$APP/Contents/MacOS/SwiftCode" 1
for helper in $HELPERS; do
    stamp=0
    [ "$helper" = swiftcode-sim-viewer ] && stamp=1
    install_binary "$helper" "$APP/Contents/Helpers/$helper" "$stamp"
done
if [ "${SWIFTCODE_APP_MINIMAL:-0}" != 1 ]; then
    install_binary libSwiftCodeTestAgent.dylib "$APP/Contents/Helpers/libSwiftCodeTestAgent.dylib" 0
    install_binary swiftcode-swb "$APP/Contents/Helpers/swiftcode-swb" 0
    install_binary SWBBuildServiceBundle "$APP/Contents/Helpers/SWBBuildServiceBundle" 0
    first_arch=${ARCHS%% *}
    for bundle in "$(bin_dir "$SWB_BASE/swb-$first_arch" "$first_arch")"/*.bundle; do
        [ -d "$bundle" ] || continue
        ditto "$bundle" "$APP/Contents/Helpers/$(basename "$bundle")"
    done
    mkdir -p "$APP/Contents/Resources/simulator-host"
    cp scripts/swiftcode-sim.sh "$APP/Contents/Resources/simulator-host/swiftcode-sim"
    cp scripts/swiftcode-sim-serve "$APP/Contents/Resources/simulator-host/swiftcode-sim-serve"
fi
sed -e "s|@VERSION@|$VERSION|g" -e "s|@BUILD_NUMBER@|$BUILD_NUMBER|g" -e "s|@MINIMUM_SYSTEM@|$MINIMUM_SYSTEM|g" \
    "$root/packaging/macos/Info.plist.in" > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [ -f "$ICON" ]; then
    cp "$ICON" "$APP/Contents/Resources/SwiftCode.icns"
else
    echo "make-app: warning: no icon at $ICON; the app gets the generic icon" >&2
fi
cp "$root/LICENSE" "$APP/Contents/Resources/LICENSE"
[ -f "$root/THIRD_PARTY_NOTICES.md" ] && cp "$root/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
sign() {
    log=$(mktemp)
    if [ "$IDENTITY" = "-" ]; then
        codesign --force --options runtime --sign - "$1" 2>"$log" || { cat "$log" >&2; exit 1; }
    else
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$1" 2>"$log" || { cat "$log" >&2; exit 1; }
    fi
    rm -f "$log"
}
for f in "$APP"/Contents/Helpers/*; do
    sign "$f"
done
sign "$APP"
codesign --verify --strict "$APP"
echo "$APP"
