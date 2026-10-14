#!/bin/bash
# Explicit opt-in: run inside a nested compositor, never the primary desktop.
set -euo pipefail
[[ ${OMARCHY_QUATTRO_RUNTIME_TEST:-0} == 1 ]] || {
  echo 'SKIP: opt in with OMARCHY_QUATTRO_RUNTIME_TEST=1 inside nested Hyprland'; exit 0;
}
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source=${OMARCHY_QUATTRO_TEST_TREE:?set OMARCHY_QUATTRO_TEST_TREE}
[[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} && -n ${WAYLAND_DISPLAY:-} ]]
hyprctl -j monitors >/dev/null
ulimit -c 0
t=$(mktemp -d)
pid=""
cleanup() {
  status=$?
  if [[ -n $pid ]]; then
    kill -TERM -- "-$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  # Detached QML helpers may leave the shell's process group. Only signal
  # children whose environment still identifies this exact scratch checkout.
  for environ in /proc/[0-9]*/environ; do
    if grep -qzxF "OMARCHY_PATH=$t/omarchy" "$environ" 2>/dev/null; then
      child=${environ#/proc/}; child=${child%/environ}
      kill -TERM "$child" 2>/dev/null || true
    fi
  done
  if ((status)); then echo "Runtime failure details: $t" >&2; else rm -rf "$t"; fi
}
trap cleanup EXIT
mkdir -p "$t/omarchy" "$t/home/.config/omarchy"
cp -a "$source/shell" "$t/omarchy/shell"
for dir in bin config default; do ln -s "$source/$dir" "$t/omarchy/$dir"; done
python3 - "$ROOT" "$t/home/.config/omarchy/shell.json" <<'PY'
import json,pathlib,sys
root=pathlib.Path(sys.argv[1]);c=json.loads((root/'overlay/quattro/config/omarchy/shell.json').read_text())
for e in c['bar']['layout']['center']:
    if e['id']=='omarchy.elsewhen': e['zones']='Custom Tokyo|Asia/Tokyo, Custom Phoenix|America/Phoenix'
pathlib.Path(sys.argv[2]).write_text(json.dumps(c))
PY
cp "$t/home/.config/omarchy/shell.json" "$t/before.json"
# A dedicated session makes all watcher/probe children safe to terminate.
HOME="$t/home" XDG_CONFIG_HOME="$t/home/.config" XDG_STATE_HOME="$t/home/.local/state" OMARCHY_PATH="$t/omarchy" QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1 setsid quickshell -n -p "$t/omarchy/shell" >"$t/shell.log" 2>&1 &
pid=$!
ready=0
for _ in {1..80}; do
  kill -0 "$pid"
  if quickshell ipc --pid "$pid" call shell ping 2>/dev/null | grep -qx ok; then ready=1; break; fi
  sleep 0.1
done
[[ $ready == 1 ]]
sleep 3
quickshell ipc --pid "$pid" call shell listShellConfig >"$t/loaded.json"
python3 - "$t" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);a=json.loads((p/'before.json').read_text());n=json.loads((p/'home/.config/omarchy/shell.json').read_text());loaded=json.loads((p/'loaded.json').read_text())
assert n==a, 'startup overwrote saved user settings'
assert loaded==a, 'shell did not load canonical user settings'
PY
! grep -Eq 'Failed to load configuration|Type .* unavailable|Syntax error' "$t/shell.log"
echo 'Quattro runtime configuration preservation passed'
