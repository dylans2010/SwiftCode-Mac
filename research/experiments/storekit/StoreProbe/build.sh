#!/bin/sh
set -eu
SRC=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?usage: build.sh OUTDIR}
mkdir -p "$OUT"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios27.0-simulator -sdk "$SDK" \
  -swift-version 5 -Onone -g -parse-as-library \
  -F "$SDK/Developer/Library/Frameworks" -framework StoreKitTest -framework StoreKit -framework UIKit \
  "$SRC/main.swift" -o "$OUT/StoreProbe.bin"
mk() {
  A="$OUT/$1.app"; rm -rf "$A"; mkdir -p "$A"
  cp "$OUT/StoreProbe.bin" "$A/StoreProbe"
  cp "$SRC"/*.storekit "$A/"
  cat > "$A/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$2</string>
<key>CFBundleExecutable</key><string>StoreProbe</string>
<key>CFBundleName</key><string>$1</string>
<key>CFBundleDisplayName</key><string>$1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.2</string>
<key>CFBundleVersion</key><string>12</string>
<key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
<key>MinimumOSVersion</key><string>27.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict>
  <key>UIApplicationSupportsMultipleScenes</key><false/>
</dict>
</dict></plist>
EOF
  codesign -f -s - "$A" >/dev/null 2>&1
}
mk StoreProbe dev.ycode.skprobe
mk StoreProbeB dev.ycode.skprobe.b
echo "built $OUT/StoreProbe.app $OUT/StoreProbeB.app"
