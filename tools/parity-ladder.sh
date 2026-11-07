#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
order=$here/parity-ladder-order.txt
labels() { grep -v '^#' "$order" | sed '/^[[:space:]]*$/d' | awk '{print $1}'; }
count() { labels | wc -l | tr -d ' '; }
keep() {
    local k=$1 n; n=$(count)
    [[ $k =~ ^[0-9]+$ ]] && [ "$k" -le "$n" ] || { echo "parity-ladder: step must be 0..$n" >&2; exit 64; }
    [ "$k" -eq 0 ] && { echo ""; return; }
    labels | head -n "$k" | paste -sd, -
}
known() { labels | grep -qx "$1" || { echo "parity-ladder: $1 is not in $order" >&2; exit 64; }; }
all_but() { known "$1"; labels | grep -vx "$1" | paste -sd, -; }
thor() {
    : "${SWIFTCODE_THOR:?set SWIFTCODE_THOR=user@host}" "${SWIFTCODE_SX:?set SWIFTCODE_SX=<harness dir>}"
    ssh -o BatchMode=yes "$SWIFTCODE_THOR" "$@"
}
safe() { [[ $1 =~ ^[A-Za-z0-9._-]+$ ]] || { echo "parity-ladder: bad name '$1'" >&2; exit 64; }; }
case "${1:-}" in
order) labels | nl -w2 -s'  ' ;;
keep) keep "$2" ;;
mac)
    k=$(keep "$2")
    python3 -I "$here/mac-sim-lean-boot.py" --mode lean --runs "$3" --keep "$k" \
        --prefix "swiftcode-test-L-ladder$2" --out "$4" --start-index "${5:-1}" ;;
mac-pair)
    k=$(keep "$2")
    for i in $(seq 1 "$3"); do
        python3 -I "$here/mac-sim-lean-boot.py" --mode lean --runs 1 \
            --prefix swiftcode-test-L-ladder0 --out "$4" --start-index "$i"
        python3 -I "$here/mac-sim-lean-boot.py" --mode lean --runs 1 --keep "$k" \
            --prefix "swiftcode-test-L-ladder$2" --out "$4" --start-index "$i"
    done ;;
mac-only)
    known "$2"
    python3 -I "$here/mac-sim-lean-boot.py" --mode lean --runs "$3" --enable "$2" \
        --prefix "swiftcode-test-L-only-$(echo "$2" | sed 's/^com\.apple\.//; s/[^A-Za-z0-9]/_/g')" --out "$4" ;;
mac-summary) shift; python3 -I "$here/mac-sim-lean-summary.py" "$@" ;;
swiftcode|swiftcode-only)
    agent=${4:-L2}; safe "$3"; safe "$agent"
    if [ "$1" = swiftcode ]; then k=$(keep "$2"); else k=$(all_but "$2"); fi
    thor "SWIFTCODE_LEAN_BOOT=daemons SWIFTCODE_LEAN_BOOT_KEEP='$k' BENCH_TMPFS=1 BENCH_NOKILL=1 BENCH_KEEPDEV=1 BENCH_SECS=700 \
          $SWIFTCODE_SX/bin/bench.sh $agent $3" ;;
swiftcode-result)
    agent=${3:-L2}; safe "$2"; safe "$agent"
    progs=$(labels | sed 's/^com\.apple\.//; s/^accessibility\.//' | paste -sd' ' -)
    thor "r=$SWIFTCODE_SX/$agent/runs/$2; cat \$r/result.txt; grep -m1 'lean boot' \$r/log.txt || echo 'lean boot: off';
          echo \"guest processes ended by a signal other than 9: \$(grep 'ended with status' \$r/log.txt | grep signal | grep -vc 'signal 9;')\";
          u=\$(grep -m1 -o 'UDID [0-9A-F-]*' \$r/log.txt | cut -d' ' -f2);
          l=\$r/dev/private-var-tmp/com.apple.CoreSimulator.SimDevice.\$u/launchd.log;
          [ -f \$l ] && for p in $progs; do printf '%-34s spawns %s\\n' \$p \$(grep -c \"Successfully spawned \$p\\[\" \$l); done" ;;
*) sed -n '2,32p' "$0"; exit 64 ;;
esac
