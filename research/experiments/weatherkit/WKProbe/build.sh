#!/bin/sh
set -eu
SRC=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?usage: build.sh OUTDIR}
mkdir -p "$OUT"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
cat > "$OUT/ent.plist" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.developer.weatherkit</key><true/></dict></plist>
XML
xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios27.0-simulator -sdk "$SDK" \
  -swift-version 5 -parse-as-library -Onone -g "$SRC/main.swift" -o "$OUT/WKProbe.bin"
xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios27.0-simulator -sdk "$SDK" \
  -swift-version 5 -parse-as-library -Onone -g "$SRC/main.swift" -o "$OUT/WKProbeEnt.bin" \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker "$OUT/ent.plist"
plist() {
  cat <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$2</string>
<key>CFBundleExecutable</key><string>WKProbe</string>
<key>CFBundleName</key><string>$1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
<key>MinimumOSVersion</key><string>27.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict>
  <key>UIApplicationSupportsMultipleScenes</key><false/>
</dict>
$3
</dict></plist>
XML
}
mk() {
  rm -rf "$OUT/$1.app"; mkdir -p "$OUT/$1.app"
  cp "$OUT/$3" "$OUT/$1.app/WKProbe"
  plist "$1" "$2" "$4" > "$OUT/$1.app/Info.plist"
  if [ -n "${5:-}" ]; then
    codesign -f -s - --entitlements "$5" "$OUT/$1.app" >/dev/null 2>&1
  else
    codesign -f -s - "$OUT/$1.app" >/dev/null 2>&1
  fi
}
LOC='<key>NSLocationWhenInUseUsageDescription</key><string>WKProbe location test</string>'
mk WKProbe dev.ycode.wkprobe WKProbe.bin "$LOC"
mk WKProbeEnt dev.ycode.wkprobe.ent WKProbeEnt.bin "$LOC"
mk WKProbeEntSig dev.ycode.wkprobe.entsig WKProbeEnt.bin "$LOC" "$OUT/ent.plist"
mk WKProbeNoLoc dev.ycode.wkprobe.noloc WKProbe.bin ""
if [ -n "${OWNER_BUNDLE_ID:-}" ]; then
  mk WKProbeOwner "$OWNER_BUNDLE_ID" WKProbeEnt.bin "$LOC"
fi
echo "built into $OUT"
