#!/bin/sh
set -eu
cd "$(dirname "$0")"
APP_ID=io.github.MarcoDotIO.Ycode
render() {
    if [ "$1" -le 32 ]; then src=swiftcode-icon-small.svg; else src=swiftcode-icon.svg; fi
    rsvg-convert -w "$1" -h "$1" "$src" -o "$2"
}
rm -rf hicolor
for s in 16 22 24 32 48 64 128 256 512; do
    mkdir -p "hicolor/${s}x${s}/apps"
    render "$s" "hicolor/${s}x${s}/apps/$APP_ID.png"
done
mkdir -p hicolor/scalable/apps
cp swiftcode-icon.svg "hicolor/scalable/apps/$APP_ID.svg"
if command -v iconutil >/dev/null 2>&1; then
    set_dir="$(mktemp -d)/SwiftCode.iconset"
    mkdir -p "$set_dir"
    for s in 16 32 128 256 512; do
        render "$s" "$set_dir/icon_${s}x${s}.png"
        render "$((s * 2))" "$set_dir/icon_${s}x${s}@2x.png"
    done
    iconutil -c icns -o SwiftCode.icns "$set_dir"
    rm -rf "$(dirname "$set_dir")"
fi
