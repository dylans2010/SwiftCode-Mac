#!/bin/sh
set -eu
BASE="${1:-}"
HEAD="${2:-HEAD}"
everything() {
    echo "swiftcode=true"
    echo "frameworks=true"
    echo "lint=true"
    exit 0
}
case "$BASE" in
    "" | *[!0]*) ;;
    *) everything ;;
esac
[ -n "$BASE" ] || everything
FILES="$(git diff --name-only --no-renames "$BASE" "$HEAD" 2>/dev/null)" || everything
if printf '%s\n' "$FILES" | grep -Eq '^(\.github/(workflows/ci\.yml|scripts/|ci/known-flaky\.txt|actions/))'; then
    everything
fi
CODE="$(printf '%s\n' "$FILES" | grep -Ev '\.md$' || true)"
area() { printf '%s\n' "$CODE" | grep -Eq "$1" && echo true || echo false; }
echo "swiftcode=$(area '^(swiftcode/|frameworks/swiftui/)')"
echo "frameworks=$(area '^(frameworks/|composer/)')"
echo "lint=$(area '^(swiftcode/|frameworks/|composer/|\.swiftlint\.yml$)')"
