#!/bin/bash
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
[ -f "$HERE/swiftcode-sim.conf" ] && . "$HERE/swiftcode-sim.conf"
Y=${SWIFTCODE_SIM_TREE:?SWIFTCODE_SIM_TREE is not set}
DATA=${SWIFTCODE_SIM_DATA:?SWIFTCODE_SIM_DATA is not set}
LOCKS=${SWIFTCODE_SIM_LOCKS:-$DATA/locks}
SLOTS=${SWIFTCODE_SIM_SLOTS:-3}
SIMD=$Y/.build/release/swiftcode-simd
AIRC=$Y/Translator/build/swiftcode-airc
[ -x "$AIRC" ] || [ ! -x "$Y/.build/release/swiftcode-airc" ] || AIRC=$Y/.build/release/swiftcode-airc
HOST_ARGS=(--shim "$Y/SimShim/out/shim.bin" --host-stubs "$Y/SimShim/out/host_stubs.bin" --host-libs "$Y/SimHostLibs/out"
           --runtime-paths --metal-translator "$AIRC"
           --gpu-cache-dir "${SWIFTCODE_SIM_GPU_CACHE:-$DATA/gpu-cache}" --timeout-ms "${SWIFTCODE_SIM_TIMEOUT_MS:-1500000}")
[ -n "${SWIFTCODE_SIM_GUEST_TOOLS:-}" ] && HOST_ARGS+=(--guest-tools "$SWIFTCODE_SIM_GUEST_TOOLS")
say() { echo "swiftcode-sim: $*"; note "$*"; }
note() { [ -d "${RUN:-}" ] && printf '%(%F %T)T %s\n' -1 "$*" >> "$RUN/swiftcode-sim.log"; return 0; }
now_ns() { date +%s%N; }
tick() { local t=${EPOCHREALTIME//[!0-9]/}; if [ -n "$t" ]; then NOW_NS=${t}000; else NOW_NS=$(date +%s%N); fi; }
fsecs() { local d=$(( ($3 - $2) / 100000000 )); printf -v "$1" '%d.%d' $((d / 10)) $((d % 10)); }
secs() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", (b - a) / 1e9 }'; }
T_BEGIN=$(now_ns)
mkdir -p "$LOCKS"
take_slot() {
  local waited=0 i
  while :; do
    for i in $(seq 1 "$SLOTS"); do
      exec 9>>"$LOCKS/boot.$i"
      if flock -n 9; then
        echo "$(date +%T) slot boot.$i: ide-remote swiftcode-sim" >> "$LOCKS/history.txt"
        say "boot slot $i acquired after $(secs "$T_BEGIN" "$(now_ns)") s"
        return
      fi
      exec 9>&-
    done
    [ $waited = 0 ] && echo "swiftcode-sim: waiting for a free boot slot" >&2
    waited=1; sleep 10
  done
}
backtrace_settings() {
  echo "enable=yes,interactive=no,symbolicate=off,threads=all,images=all,registers=crashed,timeout=60s,output-to=$1"
}
SYMBOLIZER='
import os, re, shutil, subprocess, sys
src = sys.argv[1]
text = open(src, errors="replace").read().splitlines()
images = []
for l in text:
    m = re.match(r"^(0x[0-9a-f]+)\S(0x[0-9a-f]+)\s+\S+\s+\S+\s+(/.*)$", l.strip())
    if m: images.append((int(m.group(1), 16), int(m.group(2), 16), m.group(3).strip()))
tool = shutil.which("llvm-symbolizer")
dem = shutil.which("swift-demangle") or next((p for p in [os.path.expanduser("~/.local/share/swiftly/bin/swift-demangle")]
                                              if os.access(p, os.X_OK)), None)
frames, want = {}, {}
for i, l in enumerate(text):
    m = re.match(r"^\s*\d+\s+(\[[a-z]+\]\s+)?(0x[0-9a-f]+)\b", l)
    if not m: continue
    a = int(m.group(2), 16); ra = (m.group(1) or "").strip() == "[ra]"
    for (s, e, p) in images:
        if s <= a < e:
            off = a - s - (1 if ra else 0)
            frames[i] = (p, off); want.setdefault(p, set()).add(off); break
names = {}
for p, offs in want.items():
    if not tool: break
    offs = sorted(offs)
    try:
        out = subprocess.run([tool, "--obj=" + p, "--functions=linkage", "--no-inlines"] + ["0x%x" % o for o in offs],
                             capture_output=True, text=True, timeout=600).stdout
    except Exception:
        out = ""
    blocks = [b.strip().splitlines() for b in out.strip().split("\n\n")]
    for o, b in zip(offs, blocks):
        names[(p, o)] = (b[0] if b else "?", b[1] if len(b) > 1 else "")
if dem and names:
    keys = list(names)
    try:
        d = subprocess.run([dem, "--simplified"], input="\n".join(names[k][0] for k in keys) + "\n",
                           capture_output=True, text=True, timeout=120).stdout.splitlines()
        if len(d) == len(keys):
            for k, v in zip(keys, d): names[k] = (v, names[k][1])
    except Exception:
        pass
with open(src + ".sym.txt", "w") as f:
    for i, l in enumerate(text):
        if i in frames:
            p, o = frames[i]; fn, loc = names.get((p, o), ("?", ""))
            f.write("%s  %s+0x%x  %s  %s\n" % (l.rstrip(), os.path.basename(p), o, fn, loc))
        else:
            f.write(l + "\n")
'
symbolize_crash() {
  python3 -I -c "$SYMBOLIZER" "$1" </dev/null >/dev/null 2>&1 9>&- 8>&-
}
keep_newest() {
  local f
  ls -1t "$1"/$2 2>/dev/null | tail -n +$(($3 + 1)) | while IFS= read -r f; do
    case "$f" in "$1"/?*) rm -f -- "$f" ;; esac
  done
}
for a in "$@"; do
  case "$a" in --control|--fold|--orientation|--rotate|--fold-state|--crown|--gesture|--button|--vision|--ui|--accessibility|--location|--audio|--overrides|--settings|--health)
    exec "$SIMD" "$@" ;; esac
done
case "${1:-}" in
  pair|unpair|pair-activate|list-pairs)
    verb=$1; shift
    SET_ARGS=()
    [ -n "${SWIFTCODE_SIM_DEVICE_SET:-}" ] && SET_ARGS=(--device-set "$SWIFTCODE_SIM_DEVICE_SET")
    [ "$verb" = unpair ] || exec "$SIMD" "${SET_ARGS[@]}" "--$verb" "$@"
    out=$("$SIMD" "${SET_ARGS[@]}" --unpair "$@"); rc=$?
    [ -n "$out" ] && printf '%s\n' "$out"
    erased=$(printf '%s\n' "$out" | sed -n 's/^erased //p')
    if [ -n "$erased" ] && [ -d "$DATA/snapshots/$(basename "$erased")" ]; then
      snap=$DATA/snapshots/$(basename "$erased")
      t="$snap/trash.$(date +%s%N)"
      [ -e "$snap/current" ] && mv -- "$snap/current" "$t" && rm -rf -- "${t:?}"
      rm -f -- "$snap/device-sync" "$snap/device-ino"
    fi
    exit $rc ;;
esac
STATUS=1; RESULT=failed
DEV=""; RR=""; BASE_ARGS=(); prev=""; ERASE=0
for a in "$@"; do
  case "$prev" in
    --device) DEV=$a ;;
    --runtime-root) RR=$a ;;
  esac
  case "$prev" in
    --install-app|--launch|--app-arg|--app-env|--app-url|--profile|--profile-rate|--profile-hang-ms|--profile-seconds|--profile-process|--debug-server|--room) ;;
    *) case "$a" in --install-app|--launch|--app-arg|--app-env|--app-url|--room|--environment-overrides|--profile|--profile-rate|--profile-hang-ms|--profile-seconds|--profile-process|--profile-no-signposts|--debug-server|--debug-server-log) ;; --erase) ERASE=1 ;; *) BASE_ARGS+=("$a") ;; esac ;;
  esac
  prev=$a
done
cold_exec() {
  take_slot
  mkdir -p "$DATA/shots" "$DATA/crashes"
  [ -n "${SWIFT_BACKTRACE+x}" ] || export SWIFT_BACKTRACE="$(backtrace_settings "$DATA/crashes")"
  exec "$SIMD" "$@" "${HOST_ARGS[@]}" --screenshot "$DATA/shots/run.png" \
    --screenshot-at 180 --screenshot-at 300 --screenshot-at 420 --screenshot-at 540 --screenshot-at 660
}
if [ $ERASE = 1 ] && [ -z "$DEV" ]; then echo "swiftcode-sim: --erase needs --device" >&2; exit 64; fi
if [ $ERASE = 0 ]; then
  if [ "${SWIFTCODE_WARM_BOOT:-0}" != 1 ] || [ -z "$DEV" ]; then cold_exec "$@"; fi
  if ! grep -qa SWIFTCODE_SNAPSHOT_STOP_DIR "$SIMD"; then
    say "warm boot: this swiftcode-simd build cannot save the device at a stop; cold boot"
    cold_exec "$@"
  fi
  if ! python3 -I -c "import PIL" 2>/dev/null; then
    say "warm boot: python3 with PIL is needed to watch for the home screen; cold boot"
    cold_exec "$@"
  fi
fi
trap '' PIPE
NAME=$(basename "$DEV")
SR=$DATA/snapshots/$NAME
RUN=$DATA/runs/$NAME
KEEP=${SWIFTCODE_WARM_KEEP_LOGS:-10}
mkdir -p "$SR" "$RUN/frames" "$RUN/logs" "$RUN/crashes"
for m in restore cold; do
  [ -f "$RUN/log-$m.txt" ] && [ ! -L "$RUN/log-$m.txt" ] \
    && mv "$RUN/log-$m.txt" "$RUN/logs/$(date -r "$RUN/log-$m.txt" +%Y%m%d-%H%M%S)-$m.txt"
done
BT_OWN=0
[ -n "${SWIFT_BACKTRACE+x}" ] || { export SWIFT_BACKTRACE="$(backtrace_settings "$RUN/crashes")"; BT_OWN=1; }
[ "$(stat -c %s "$RUN/swiftcode-sim.log" 2>/dev/null || echo 0)" -gt 1048576 ] && mv "$RUN/swiftcode-sim.log" "$RUN/swiftcode-sim.log.1"
discard() {
  local p=$1 t
  [ -e "$p" ] || return 0
  case "$p" in
    "$SR"/?*) t="$SR/trash.$(now_ns)" ;;
    */devices/?*) t="$(dirname "$p")/.trash-$(basename "$p").$(now_ns)" ;;
    *) say "not discarding $p (unexpected path)"; return 1 ;;
  esac
  mv -- "$p" "$t" || return 1
  setsid nohup rm -rf -- "${t:?}" </dev/null >/dev/null 2>&1 9>&- 8>&- &
}
fingerprint() {
  {
    echo "swiftcode-sim warm boot 2"
    printf '%s\n' "${BASE_ARGS[@]}" "${HOST_ARGS[@]}"
    env | grep -E '^SWIFTCODE_LEAN_BOOT' | sort
    stat -L -c '%n %s %Y' "$SIMD" "$Y/SimShim/out/shim.bin" "$Y/SimShim/out/host_stubs.bin" "$AIRC" 2>&1
    find "$Y/SimHostLibs/out" "$Y/SimGuestFrameworks/out" -type f -printf '%p %s %T@\n' 2>/dev/null | sort
    stat -L -c '%n %s %Y' "$RR/System/Library/CoreServices/SystemVersion.plist" 2>&1
    grep -A1 -E '<key>Product(Name|BuildVersion)</key>' "$RR/System/Library/CoreServices/SystemVersion.plist" 2>&1
  } | sha256sum | cut -d' ' -f1
}
exec 8>>"$SR/.lock"
if ! flock -n 8; then
  say "warm boot: waiting for the previous run of this device to end and its save to finish"
  flock 8
fi
if [ $ERASE = 1 ]; then
  discard "$SR/current"; rm -f "${SR:?}/device-sync" "${SR:?}/device-ino"
  discard "$DEV"
  say "erased $DEV"
  exit 0
fi
FP=$(fingerprint)
snapshot_problem() {
  local c=$SR/current id
  [ -f "$c/swiftcode-warm.stamp" ] || { echo "no snapshot yet"; return; }
  [ "$(sed -n 1p "$c/swiftcode-warm.stamp")" = "$FP" ] || { echo "the simulator build, the runtime or the boot options changed"; return; }
  [ -d "$DEV" ] || { echo "the device was erased"; return; }
  [ "$(stat -c %i "$DEV")" = "$(cat "$SR/device-ino" 2>/dev/null)" ] || { echo "the device directory was replaced"; return; }
  [ "$(head -n 1 "$c/device-path" 2>/dev/null)" = "$DEV" ] || { echo "the snapshot belongs to another device path"; return; }
  [ -f "$c/manifest.ysnap" ] && [ -f "$c/device-inodes" ] || { echo "the snapshot is incomplete"; return; }
  id=$(sed -n 3p "$c/swiftcode-warm.stamp")
  [ -n "$id" ] && [ "$(cat "$SR/device-sync" 2>/dev/null)" = "$id" ] \
    || { echo "the device changed since the snapshot (the last run ended without saving it)"; return; }
}
PROBLEM=$(snapshot_problem)
if [ -z "$PROBLEM" ] && [ "${SWIFTCODE_WARM_FORCE_COLD:-0}" = 1 ]; then PROBLEM="a cold boot was asked for"; fi
if [ -n "$PROBLEM" ] && [ -e "$SR/current" ]; then
  say "warm boot: discarding the snapshot ($PROBLEM)"
  discard "$SR/current"; rm -f "${SR:?}/device-sync"
fi
rm -f "${SR:?}/spare.ok"; discard "$SR/spare"
save_job() {
  local stage=$1 ino; ino=$(stat -c %i "$DEV")
  setsid nohup bash -c '
    stage=$1 SR=$2 FP=$3 ino=$4 id=$5 inc=$2/incoming.$(date +%s%N)
    t0=$(date +%s)
    if [ "${stage#$SR/}" != "$stage" ]; then mv "$stage" "$inc"; else ionice -c3 nice -n 19 cp -a "$stage" "$inc"; fi || exit 1
    printf "%s\n%s\n%s\n" "$FP" "captured $(date -Is)" "$id" > "$inc/swiftcode-warm.stamp"
    case "$SR" in */snapshots/?*) ;; *) exit 1 ;; esac
    [ -e "$SR/current" ] && mv "$SR/current" "$SR/trash.$(date +%s%N)"
    mv "$inc" "$SR/current" && echo "$ino" > "$SR/device-ino" && echo "$id" > "$SR/device-sync"
    case "$stage" in /run/user/[0-9]*/swiftcode-warm/?*) rm -rf -- "${stage:?}" ;; esac
    echo "$(date +%T) snapshot $id saved in $(( $(date +%s) - t0 )) s" >> "$SR/jobs.log"
    exec 8>&-
    for t in "$SR"/trash.*; do [ -e "$t" ] && ionice -c3 nice -n 19 rm -rf -- "${t:?}"; done
  ' save "$stage" "$SR" "$FP" "$ino" "$(basename "$stage")" </dev/null >>"$SR/jobs.log" 2>&1 9>&- &
}
WATCHER='
import os, re, sys, time
from PIL import Image
fd, t0, out, pid, limit = sys.argv[1], int(sys.argv[2]) / 1e9, sys.argv[3], int(sys.argv[4]), float(sys.argv[5])
seen, prev = set(), None
def alive():
    try: os.kill(pid, 0); return True
    except OSError: return False
while alive() and time.time() - t0 < limit:
    for f in sorted(os.listdir(fd), key=lambda n: int(re.sub(r"\D", "", n) or 0)):
        m = re.match(r"^f-(\d+)s\.png$", f)
        if not m or f in seen: continue
        p = os.path.join(fd, f)
        try: im = Image.open(p).convert("L").resize((70, 102))
        except Exception: continue
        seen.add(f)
        t = os.path.getmtime(p) - t0
        if sum(im.histogram()[:24]) < 0.9 * 70 * 102:
            if prev is not None:
                open(out + ".tmp", "w").write("%.1f\n" % prev); os.rename(out + ".tmp", out); sys.exit(0)
            prev = t
        else:
            prev = None
    time.sleep(0.5)
'
STOPPING=0; STOP_AT=0; CHILD=""; STOPPING_KILLED=0
forward() { if [ $STOPPING = 0 ]; then tick; STOP_AT=$NOW_NS; fi; STOPPING=1; [ -n "$CHILD" ] && kill -TERM "$CHILD" 2>/dev/null; }
trap forward INT TERM HUP
HAS_APP=0
for a in "$@"; do case "$a" in --install-app|--launch) HAS_APP=1 ;; esac; done
SETTLE_MS=${SWIFTCODE_WARM_SETTLE_MS:-60000}
APP_TIMEOUT=${SWIFTCODE_WARM_APP_TIMEOUT_S:-300}
STOP_TIMEOUT=${SWIFTCODE_WARM_STOP_TIMEOUT_S:-120}
LIVE_TIMEOUT=${SWIFTCODE_WARM_LIVE_TIMEOUT_S:-60}
FRAME_TIMEOUT=${SWIFTCODE_WARM_FRAME_TIMEOUT_S:-90}
new_stage() {
  local ram=${SWIFTCODE_WARM_STAGE:-/run/user/$(id -u)}
  if [ "$ram" != none ] && [ -d "$ram" ] && [ "$(df --output=avail -B1G "$ram" | tail -n 1 | tr -d ' ')" -ge 6 ]; then
    echo "$ram/swiftcode-warm/$NAME.$(now_ns)"
  else
    echo "$SR/new.$(now_ns)"
  fi
}
SAVED=""
run_simd() {
  local mode=$1; shift
  local envs=() at=() t stage launched=0 appfail=0 home="" home_s=0 deadline live=1 framed=1
  local log; log=$RUN/logs/$(date +%Y%m%d-%H%M%S)-$mode.txt
  find "$RUN/frames" -maxdepth 1 -name 'f-*s.png' -delete
  rm -f "${RUN:?}/home" "${RUN:?}/home.tmp" "${RUN:?}/settled"
  : > "$log"
  ln -sfn "logs/$(basename "$log")" "$RUN/log-$mode.txt"
  keep_newest "$RUN/logs" '*.txt' "$KEEP"
  local crashes_before; crashes_before=$(ls "$RUN/crashes" 2>/dev/null | grep -c '\.log$')
  SAVED=""
  stage=$(new_stage); mkdir -p "$(dirname "$stage")"
  rm -f "${SR:?}/device-sync"
  envs=(SWIFTCODE_EXIT_WITH_PARENT=1 SWIFTCODE_SNAPSHOT_STOP_DIR="$stage" SWIFTCODE_SNAPSHOT_DEADLINE_MS=15000 SWIFTCODE_SNAPSHOT_STOP_CLOSE_FDS=8,9
        SWIFTCODE_SNAPSHOT_STOP_REQUIRES="$RUN/settled")
  local settle=${SWIFTCODE_WARM_SAVE_SETTLE_S:-30}
  [ "$mode" = restore ] && settle=0
  [ "$mode" = restore ] && grep -qa "restore: guest live" "$SIMD" && live=0
  [ "$mode" = restore ] && [ "$FRAME_TIMEOUT" -gt 0 ] && grep -qa "restore: first new frame" "$SIMD" && framed=0
  if [ "$mode" = restore ]; then
    envs+=(SWIFTCODE_RESTORE_DIR="$SR/current" SWIFTCODE_RESTORE_LAZY=1 SWIFTCODE_RESTORE_LENIENT=1)
    for ((t = 2; t <= 60; t += 2)); do at+=(--screenshot-at "$t"); done
    for ((t = 65; t <= 180; t += 5)); do at+=(--screenshot-at "$t"); done
    deadline=${SWIFTCODE_WARM_HOME_TIMEOUT_S:-120}
  else
    envs+=(SWIFTCODE_SNAPSHOT_WHEN_FILE="$RUN/home" SWIFTCODE_SNAPSHOT_DELAY_MS="$SETTLE_MS" SWIFTCODE_SNAPSHOT_HOLD_APPS=480)
    for ((t = 5; t <= 400; t += 5)); do at+=(--screenshot-at "$t"); done
    deadline=420
  fi
  tick; local t0=$NOW_NS
  env "${envs[@]}" "$SIMD" "$@" "${HOST_ARGS[@]}" --screenshot "$RUN/frames/f.png" "${at[@]}" > >(tee -p -a "$log") 2>&1 &
  CHILD=$!
  [ $STOPPING = 1 ] && kill -TERM "$CHILD" 2>/dev/null
  python3 -I -c "$WATCHER" "$RUN/frames" "$t0" "$RUN/home" "$CHILD" "$deadline" </dev/null >/dev/null 2>&1 9>&- 8>&- &
  local watcher=$!
  while kill -0 "$CHILD" 2>/dev/null; do
    tick
    local elapsed=$(( (NOW_NS - t0) / 1000000000 ))
    if [ -z "$home" ] && [ -f "$RUN/home" ]; then
      read -r home < "$RUN/home"
      local hi=${home%%.*} hf=${home#*.} hb
      [ "$hf" = "$home" ] && hf=0
      home_s=$(( 10#$hi + 1 ))
      fsecs hb "$T_BEGIN" "$(( t0 + (10#$hi * 10 + 10#${hf:0:1}) * 100000000 ))"
      say "home screen at $home s after swiftcode-simd started ($hb s after this run began; $mode)"
    fi
    if [ $framed = 0 ] && grep -q "snapshot: restore: first new frame" "$log" 2>/dev/null; then
      framed=1; local fs; fsecs fs "$t0" "$NOW_NS"; note "first new frame $fs s after swiftcode-simd started"
    fi
    if [ $live = 0 ] && grep -q "snapshot: restore: guest live" "$log" 2>/dev/null; then
      live=1; local ls; fsecs ls "$t0" "$NOW_NS"; note "guest live $ls s after swiftcode-simd started"
    fi
    if [ -n "$home" ] && [ ! -f "$RUN/settled" ] && [ $live = 1 ] && [ "$elapsed" -ge $(( home_s + settle )) ]; then
      touch "$RUN/settled"; note "the device has settled; a stop now saves it"
    fi
    if [ $launched = 0 ] && grep -q "ylaunch: launched " "$log" 2>/dev/null; then
      launched=1; local a1 a2; fsecs a1 "$t0" "$NOW_NS"; fsecs a2 "$T_BEGIN" "$NOW_NS"
      note "app running $a1 s after swiftcode-simd started ($a2 s after this run began; $mode)"
    fi
    if [ "$mode" = restore ] && [ $STOPPING = 0 ] && [ $appfail = 0 ]; then
      local why=""
      if [ -z "$home" ] && ! kill -0 "$watcher" 2>/dev/null && [ ! -f "$RUN/home" ]; then
        why="no home screen ${deadline} s after the restore"
      elif [ $live = 0 ] && [ "$elapsed" -ge "$LIVE_TIMEOUT" ]; then
        why="the restored guest did not answer ${LIVE_TIMEOUT} s after the restore"
      elif [ $framed = 0 ] && [ "$elapsed" -ge "$FRAME_TIMEOUT" ]; then
        why="the restored guest presented no new frame ${FRAME_TIMEOUT} s after the restore"
      elif [ $HAS_APP = 1 ] && [ $launched = 0 ] && [ "$elapsed" -ge "$APP_TIMEOUT" ]; then
        why="the app steps did not finish ${APP_TIMEOUT} s after the restore"
      fi
      if [ -n "$why" ]; then
        say "warm boot: $why"
        kill -USR1 "$CHILD" 2>/dev/null
        local w=0; while [ $w -lt 10 ] && ! grep -q "swiftcode-simd: thread report on SIGUSR1" "$log" 2>/dev/null; do sleep 0.5; w=$((w + 1)); done
        sleep 3
        appfail=1; kill -KILL "$CHILD" 2>/dev/null
      fi
    fi
    if grep -q "snapshot: exiting after the snapshot" "$log" 2>/dev/null && [ -f "$stage/manifest.ysnap" ]; then
      SAVED=$stage; break
    fi
    if [ $STOPPING = 1 ] && [ $(( (NOW_NS - STOP_AT) / 1000000000 )) -ge "$STOP_TIMEOUT" ]; then
      note "stop: swiftcode-simd had not ended ${STOP_TIMEOUT} s after the stop; killed"
      if [ "$STOPPING_KILLED" = 0 ] && [ "$BT_OWN" = 1 ]; then
        kill -SEGV "$CHILD" 2>/dev/null; sleep 5
      fi
      STOPPING_KILLED=1
      kill -KILL "$CHILD" 2>/dev/null
    fi
    sleep 0.5
  done
  if [ -n "$SAVED" ]; then
    STATUS=0
  else
    wait "$CHILD"; STATUS=$?
    if [ $appfail = 0 ] && [ "$STATUS" = 0 ] && grep -q "snapshot: exiting after the snapshot" "$log" 2>/dev/null \
       && [ -f "$stage/manifest.ysnap" ]; then SAVED=$stage; fi
  fi
  CHILD=""
  kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
  if [ "$STATUS" -ge 128 ] && [ "$(ls "$RUN/crashes" 2>/dev/null | grep -c '\.log$')" != "$crashes_before" ]; then
    local report; report=$(ls -1t "$RUN/crashes"/*.log | head -n 1)
    symbolize_crash "$report"
    say "swiftcode-simd crashed (status $STATUS); crash report $report$([ -f "$report.sym.txt" ] && echo " (symbolized: $report.sym.txt)")"
    { echo "---- crash report (crashing thread), $report"
      sed -n '/crashed:$/,/^$/p' "$report.sym.txt" 2>/dev/null | head -n 80; } >> "$log"
    keep_newest "$RUN/crashes" '*.log' "$KEEP"
    ls -1 "$RUN/crashes"/*.sym.txt 2>/dev/null | while IFS= read -r f; do [ -f "${f%.sym.txt}" ] || rm -f -- "$f"; done
  fi
  if [ -n "$SAVED" ]; then
    note "stop: the device was saved ($(grep -o 'total pause [0-9]* ms' "$log" | tail -n 1))$([ $STOPPING = 1 ] && echo ", $(secs "$STOP_AT" "$(now_ns)") s after the stop")"
  else
    case "$stage" in /run/user/[0-9]*/swiftcode-warm/?*) rm -rf -- "${stage:?}" ;; "$SR"/new.*) discard "$stage" ;; esac
  fi
  if [ $STOPPING = 1 ]; then RESULT=stopped
  elif [ "$mode" = restore ] && { [ $appfail = 1 ] || { [ -z "$home" ] && [ ! -f "$RUN/home" ]; }; }; then RESULT=failed
  elif [ "$mode" = restore ] && [ "$STATUS" != 0 ] && [ -z "$SAVED" ]; then RESULT=crashed
  else RESULT=ok; fi
}
drop_snapshot() { discard "$SR/current"; rm -f "${SR:?}/device-sync"; }
take_slot
if [ -z "$PROBLEM" ]; then
  say "warm boot: restoring the device from its snapshot ($(sed -n 2p "$SR/current/swiftcode-warm.stamp"))"
  run_simd restore "$@"
  if [ "$RESULT" = failed ]; then
    say "warm boot: the restore failed (swiftcode-simd status $STATUS); discarding the snapshot and booting cold"
    drop_snapshot
    run_simd cold "$@"
  elif [ "$RESULT" = crashed ]; then
    say "warm boot: swiftcode-simd ended with status $STATUS after a restore; the snapshot is discarded"
    drop_snapshot
  fi
else
  say "warm boot: $PROBLEM; cold boot"
  run_simd cold "$@"
fi
if [ -n "$SAVED" ]; then
  save_job "$SAVED"
  say "warm boot: the device was saved; the next run continues from it"
else
  say "warm boot: the device was not saved; the next run boots it cold (its data stays)"
fi
exec 8>&-
exit "$STATUS"
