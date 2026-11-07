#!/bin/sh
set -eu
set +x
here=$(cd "$(dirname "$0")" && pwd)
swiftcode_dir=$(cd "$here/.." && pwd)
root=$(cd "$swiftcode_dir/.." && pwd)
macos="$root/packaging/macos"
cd "$swiftcode_dir"
SWIFTCODE_ARCHS=${SWIFTCODE_ARCHS:-arm64 x86_64}
export SWIFTCODE_ARCHS
OUT=${1:-.build-ide/dist}
VERSION=$(cat VERSION)
VOLUME="SwiftCode $VERSION"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
DMG="$OUT/SwiftCode-$VERSION.dmg"
work=$(mktemp -d)
keychain=""
previous_keychains=""
mount_point=""
cleanup() {
    [ -n "$mount_point" ] && hdiutil detach -quiet -force "$mount_point" 2>/dev/null
    if [ -n "$keychain" ]; then
        eval "security list-keychains -d user -s $previous_keychains" 2>/dev/null
        security delete-keychain "$keychain" 2>/dev/null
    fi
    rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 1' INT TERM
if [ -z "${SWIFTCODE_SIGN_IDENTITY:-}" ] && [ -n "${MACOS_CERTIFICATE_P12_BASE64:-}" ]; then
    : "${MACOS_CERTIFICATE_PASSWORD:?MACOS_CERTIFICATE_PASSWORD is needed with MACOS_CERTIFICATE_P12_BASE64}"
    umask 077
    printf '%s' "$MACOS_CERTIFICATE_P12_BASE64" | base64 -D > "$work/certificate.p12"
    keychain="$work/signing.keychain-db"
    keychain_password=$(uuidgen)
    previous_keychains=$(security list-keychains -d user | tr -d '\n')
    security create-keychain -p "$keychain_password" "$keychain"
    security set-keychain-settings -lut 21600 "$keychain"
    security unlock-keychain -p "$keychain_password" "$keychain"
    security import "$work/certificate.p12" -k "$keychain" -P "$MACOS_CERTIFICATE_PASSWORD" -f pkcs12 -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null
    eval "security list-keychains -d user -s \"$keychain\" $previous_keychains"
    rm -f "$work/certificate.p12"
    SWIFTCODE_SIGN_IDENTITY=$(security find-identity -v -p codesigning "$keychain" | awk -F'"' '/Developer ID Application/ { print $2; exit }')
    [ -n "$SWIFTCODE_SIGN_IDENTITY" ] || { echo "make-dmg: the certificate holds no Developer ID Application identity" >&2; exit 1; }
    export SWIFTCODE_SIGN_IDENTITY
fi
IDENTITY=${SWIFTCODE_SIGN_IDENTITY:--}
if [ "$IDENTITY" = "-" ]; then
    echo "make-dmg: no signing identity: signing ad hoc (the image will not pass Gatekeeper)" >&2
else
    echo "make-dmg: signing with a Developer ID identity" >&2
fi
STAGE="$OUT/stage"
if [ "${SWIFTCODE_DMG_SKIP_APP:-0}" != 1 ]; then
    "$here/make-app.sh" "$STAGE" >/dev/null
fi
APP="$STAGE/SwiftCode.app"
if [ -n "${APPLE_TEAM_ID:-}" ] && [ "$IDENTITY" != "-" ]; then
    codesign -dvv "$APP" 2>&1 | grep -q "^TeamIdentifier=$APPLE_TEAM_ID\$" \
        || { echo "make-dmg: the app is not signed by team APPLE_TEAM_ID" >&2; exit 1; }
fi
notarizing=0
if [ -n "${NOTARY_KEY_P8_BASE64:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER_ID:-}" ]; then
    if [ "$IDENTITY" = "-" ]; then
        echo "make-dmg: notary variables exist but there is no signing identity: not notarizing" >&2
    else
        notarizing=1
        umask 077
        printf '%s' "$NOTARY_KEY_P8_BASE64" | base64 -D > "$work/notary-key.p8"
    fi
else
    echo "make-dmg: no notary variables: not notarizing" >&2
fi
notary() {
    xcrun notarytool "$@" --key "$work/notary-key.p8" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID"
}
notarize() {
    for attempt in 1 2 3; do
        notary submit "$1" --output-format json > "$work/notary-submit.json" && break
        [ "$attempt" = 3 ] && { echo "make-dmg: notarytool submit failed" >&2; return 1; }
        sleep $((attempt * 20))
    done
    submission=$(/usr/bin/plutil -extract id raw "$work/notary-submit.json" 2>/dev/null || echo "")
    [ -n "$submission" ] || { echo "make-dmg: notarytool returned no submission id" >&2; return 1; }
    echo "make-dmg: notary submission $submission" >&2
    status=unknown
    for attempt in 1 2 3 4 5 6; do
        notary wait "$submission" --timeout 30m > /dev/null || true
        if notary info "$submission" --output-format json > "$work/notary-info.json"; then
            status=$(/usr/bin/plutil -extract status raw "$work/notary-info.json" 2>/dev/null || echo unknown)
            case "$status" in Accepted|Invalid|Rejected) break ;; esac
        fi
        sleep $((attempt * 20))
    done
    if [ "$status" != Accepted ]; then
        echo "make-dmg: notarization status: $status" >&2
        notary log "$submission" >&2 || true
        return 1
    fi
}
if [ "$notarizing" = 1 ]; then
    echo "make-dmg: notarizing the app" >&2
    ditto -c -k --keepParent "$APP" "$work/SwiftCode.zip"
    notarize "$work/SwiftCode.zip"
    xcrun stapler staple "$APP" >/dev/null
    rm -f "$work/SwiftCode.zip"
fi
app_kb=$(du -sk "$APP" | cut -f1)
rw="$work/rw.dmg"
hdiutil create -quiet -size "$((app_kb / 1024 + 64))m" -fs HFS+ -volname "$VOLUME" -ov "$rw"
mount_root="$work/mnt"
mkdir -p "$mount_root"
hdiutil attach -quiet -nobrowse -noautoopen -noverify -mountroot "$mount_root" "$rw"
mount_point="$mount_root/$VOLUME"
ditto "$APP" "$mount_point/SwiftCode.app"
ln -s /Applications "$mount_point/Applications"
mkdir "$mount_point/.background"
cp "$macos/dmg-background.tiff" "$mount_point/.background/background.tiff"
cat > "$work/layout.json" <<'JSON'
{"window": [660, 400], "icon_size": 128, "icons": {"SwiftCode.app": [170, 205], "Applications": [490, 205]}}
JSON
/usr/bin/python3 -I "$macos/make-dsstore.py" "$mount_point" .background/background.tiff "$work/layout.json"
rm -rf "$mount_point/.fseventsd" "$mount_point/.Trashes"
hdiutil detach -quiet "$mount_point"
mount_point=""
rm -f "$DMG"
hdiutil convert -quiet "$rw" -format ULFO -o "$DMG"
rm -f "$rw"
if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$DMG"
else
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi
if [ "$notarizing" = 1 ]; then
    echo "make-dmg: notarizing the image" >&2
    notarize "$DMG"
    xcrun stapler staple "$DMG" >/dev/null
fi
"$macos/verify-dmg.sh" "$DMG"
(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
ls -l "$DMG" >&2
echo "$DMG"
