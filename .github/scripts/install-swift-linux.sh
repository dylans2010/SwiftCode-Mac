#!/bin/sh
set -eu
SWIFT="$1"
TARGET="$2"
if [ -x "$TARGET/usr/bin/swift" ]; then
    "$TARGET/usr/bin/swift" --version
    exit 0
fi
VERSION_ID="$(. /etc/os-release && printf '%s' "$VERSION_ID")"
UBUNTU="ubuntu${VERSION_ID}"
FOLDER="ubuntu$(printf '%s' "$VERSION_ID" | tr -d .)"
SUFFIX=""
case "$(uname -m)" in
    aarch64) FOLDER="$FOLDER-aarch64"; SUFFIX="-aarch64" ;;
    x86_64) ;;
    *) echo "No Swift release for $(uname -m)" >&2; exit 1 ;;
esac
NAME="swift-${SWIFT}-RELEASE-${UBUNTU}${SUFFIX}.tar.gz"
URL="https://download.swift.org/swift-${SWIFT}-release/${FOLDER}/swift-${SWIFT}-RELEASE/${NAME}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
curl -fsSL --retry 3 -o "$WORK/$NAME" "$URL"
curl -fsSL --retry 3 -o "$WORK/$NAME.sig" "$URL.sig"
export GNUPGHOME="$WORK/gnupg"
mkdir -m 700 "$GNUPGHOME"
gpg --batch --quiet --import "$(dirname "$0")/../ci/swift-signing-keys.asc"
gpg --batch --quiet --verify "$WORK/$NAME.sig" "$WORK/$NAME"
mkdir -p "$TARGET"
tar -xzf "$WORK/$NAME" -C "$TARGET" --strip-components=1
"$TARGET/usr/bin/swift" --version
