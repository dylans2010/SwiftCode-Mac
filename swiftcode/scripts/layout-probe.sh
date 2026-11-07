#!/bin/sh
set -eu
[ $# -ge 1 ] || { echo "usage: $0 <local | ssh-target> [out-dir]" >&2; exit 2; }
target=$1
here=$(cd "$(dirname "$0")" && pwd)
swiftcode_dir=$(cd "$here/.." && pwd)
cd "$swiftcode_dir"
label=$(printf '%s' "$target" | tr -c 'A-Za-z0-9._-' '_')
OUT=${2:-.build-ide/layout-probe/$label}
APP=${SWIFTCODE_PROBE_APP:-.build-ide/probe-app/SwiftCode.app}
TIMEOUT=${SWIFTCODE_PROBE_TIMEOUT:-120}
SHOW=${SWIFTCODE_PROBE_SHOW:-0}
if [ ! -d "$APP" ]; then
    SWIFTCODE_APP_MINIMAL=1 scripts/make-app.sh "$(dirname "$APP")" >/dev/null
fi
mkdir -p "$OUT"
rm -rf "$OUT/shots" "$OUT/probe.json"
if [ "$target" = local ]; then
    abs_out=$(cd "$OUT" && pwd)
    abs_app=$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")
    sh scripts/layout-probe-run.sh "$abs_app" "$abs_out" "$SHOW" "$TIMEOUT"
else
    ssh_opts="-o BatchMode=yes -o ConnectTimeout=15"
    ssh $ssh_opts "$target" 'mkdir -p swiftcode-layout-probe'
    rsync -a --delete -e "ssh $ssh_opts" "$APP/" "$target:swiftcode-layout-probe/SwiftCode.app/"
    rsync -a -e "ssh $ssh_opts" scripts/layout-probe-run.sh "$target:swiftcode-layout-probe/"
    ssh $ssh_opts "$target" 'cd "$HOME/swiftcode-layout-probe" && sh layout-probe-run.sh "$PWD/SwiftCode.app" "$PWD/out" '"$SHOW $TIMEOUT"
    rsync -a -e "ssh $ssh_opts" "$target:swiftcode-layout-probe/out/" "$OUT/"
fi
echo "$OUT/probe.json"
