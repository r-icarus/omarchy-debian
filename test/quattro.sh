#!/bin/bash
# Focused tests for the quattro Quickshell profile.
# Offline + hermetic: fakes HOME, fakes binaries, real repo files. No apt, no
# network, no pacman/yay. Run: test/quattro.sh   (exit 0 = pass)

set -uo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT" || exit 1

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAIL=0
pass() { printf 'ok   %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; FAIL=1; }
check() { # <description> <command...>
  local desc=$1
  shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else bad "$desc"; fi
}

# ---------------------------------------------------------------- shell.json
SJ="overlay/quattro/config/omarchy/shell.json"
check "shell.json is valid JSON" python3 -c "import json; json.load(open('$SJ'))"

python3 - "$SJ" <<'PY' || bad "shell.json bar contract"
import json, sys
cfg = json.load(open(sys.argv[1]))
bar = cfg["bar"]
assert bar["position"] == "top", "bar must be top"
ids = [w["id"] for sec in ("left", "center", "right") for w in bar["layout"][sec]]
required = {"omarchy.workspaces", "omarchy.clock", "omarchy.tray"}
missing = required - set(ids)
assert not missing, f"missing required widgets: {missing}"
known = {
  "omarchy.menu", "omarchy.workspaces", "omarchy.active-window",
  "omarchy.clock", "omarchy.tray", "omarchy.audio", "omarchy.indicators",
  "omarchy.keyboard-layout", "omarchy.microphone", "omarchy.spacer",
  "omarchy.system-update",
}
unknown = set(ids) - known
assert not unknown, f"unknown widget ids: {unknown}"
assert cfg.get("plugins") == [], "no plugins by default"
print("bar contract ok:", ids)
PY
[[ $? -eq 0 ]] && pass "shell.json bar contract (workspaces+clock+tray present, only known ids)"

# --------------------------------------------------------------- pikaos detect
PIKA_OS_RELEASE=$TMP/os-release-pika
cat >"$PIKA_OS_RELEASE" <<'EOF'
PRETTY_NAME="PikaOS 25"
NAME="PikaOS"
ID=pikaos
ID_LIKE="ubuntu debian"
VERSION_ID="25"
EOF

run_detect() { # <os-release> -> prints IS_PIKAOS
  env -i PATH=/usr/bin:/bin HOME=$TMP bash -c '
    source lib/detect.sh 2>/dev/null || true
    detect_distro >/dev/null 2>&1 || true
    echo "${IS_PIKAOS:-unset}"' 2>/dev/null
}

# detect with a fake os-release via the OMARCHY_DEBIAN_OS_RELEASE test seam
pika=$(bash -c '
  source "'"$ROOT"'/lib/detect.sh" && OMARCHY_DEBIAN_OS_RELEASE="'"$PIKA_OS_RELEASE"'" detect_distro >/dev/null && echo "${IS_PIKAOS:-0}"' 2>/dev/null)
if [[ $pika == "1" ]]; then pass "pikaos ID detected (ID=pikaos)"; else bad "pikaos ID not detected (got: ${pika:-none})"; fi

nopia=$(bash -c '
  source "'"$ROOT"'/lib/detect.sh" && detect_distro >/dev/null && echo "${IS_PIKAOS:-0}"' 2>/dev/null)
if [[ $nopia == "0" ]]; then pass "non-pika host reports IS_PIKAOS=0 (this host: $(. /etc/os-release; echo $ID))"; else bad "false pikaos positive (got $nopia)"; fi

# ------------------------------------------------------------ phase gating
gate_skip=$(OMARCHY_DEBIAN_ROOT=$ROOT OMARCHY_DEBIAN_PROFILE=none bash install/31-quattro-shell.sh 2>&1)
if [[ $gate_skip == *"not selected"* ]]; then pass "phase no-ops without --profile quattro"; else bad "phase gating (output: $gate_skip)"; fi

# ---------------------------------------------------------- helper contracts
check "omarchy-quattro-launch parses" bash -n overlay/bin/omarchy-quattro-launch
check "omarchy-quattro-bar-toggle parses" bash -n overlay/bin/omarchy-quattro-bar-toggle
check "omarchy-quattro-rollback parses" bash -n overlay/bin/omarchy-quattro-rollback

# bar-toggle flag protocol against a fake HOME
export HOME=$TMP/home && mkdir -p "$HOME"
TOG="$HOME/.local/state/omarchy/toggles/bar-off"
overlay/bin/omarchy-quattro-bar-toggle off >/dev/null 2>&1
[[ -f $TOG ]] && pass "bar-toggle off creates bar-off flag" || bad "bar-toggle off"
overlay/bin/omarchy-quattro-bar-toggle on >/dev/null 2>&1
[[ ! -f $TOG ]] && pass "bar-toggle on removes flag" || bad "bar-toggle on"
overlay/bin/omarchy-quattro-bar-toggle toggle >/dev/null 2>&1
[[ -f $TOG ]] && pass "bar-toggle toggle creates flag" || bad "bar-toggle toggle"
overlay/bin/omarchy-quattro-bar-toggle bogus >/dev/null 2>&1
[[ $? -ne 0 ]] && pass "bar-toggle rejects bad arg" || bad "bar-toggle bogus arg exit code"

# rollback against a fake HOME
mkdir -p "$HOME/.config/omarchy" "$HOME/.local/share"
echo '{"version":1,"bar":{"mine":true}}' >"$HOME/.config/omarchy/shell.json"
cp -a "$HOME/.config/omarchy/shell.json" "$HOME/.config/omarchy/shell.json.pre-omarchy"
mkdir -p "$HOME/.local/share/omarchy-quattro/.git"
out=$(overlay/bin/omarchy-quattro-rollback 2>&1)
grep -q "restored" <<<"$out" && pass "rollback restores shell.json" || bad "rollback restore (out: $out)"
[[ ! -d $HOME/.local/share/omarchy-quattro ]] && pass "rollback removes quattro clone" || bad "rollback clone removal"
grep -q '"mine": *true' "$HOME/.config/omarchy/shell.json" && pass "restored content is the backup" || bad "rollback content"

# ------------------------------------------------------------- hyprland.conf
HC=overlay/config/hypr/hyprland.conf
grep -q "omarchy-quattro-launch" "$HC" && pass "hyprland.conf launches quattro bar" || bad "quattro exec-once missing"
grep -q "exec waybar" "$HC" && pass "waybar fallback preserved" || bad "waybar fallback missing"
grep -q "omarchy-quattro-bar-toggle" "$HC" && pass "bar toggle binding present" || bad "bar toggle binding missing"
for b in "Return, exec" "SPACE, exec, fuzzel" "W, killactive" "F, fullscreen" "T, togglefloating" ", Print, exec" "XF86AudioRaiseVolume" "XF86MonBrightnessUp" "workspace, 1" "movetoworkspace, 1" "hyprlock"; do
  grep -q -- "$b" "$HC" && pass "binding present: $b" || bad "binding missing: $b"
done

# ---------------------------------------------------------------- pin check
# 31-quattro-shell.sh must pin a full 40-char ref and sha256 pins for both arches.
PINNED_REF=$(grep -oE 'OMARCHY_QUATTRO_REF:=[0-9a-f]{40}' install/31-quattro-shell.sh | head -1)
[[ -n $PINNED_REF ]] && pass "quattro ref pinned (40-hex)" || bad "quattro ref not pinned"
# pins are associative arrays now
grep -q '\[amd64\]="' install/31-quattro-shell.sh && pass "quattro sha256 pins (assoc array, both arches)" || bad "quattro sha256 pins"

# no pacman/yay anywhere in the new files
if grep -rnE '\b(pacman|yay)\b' install/31-quattro-shell.sh overlay/bin/omarchy-quattro-* >/dev/null 2>&1; then
  bad "pacman/yay referenced in quattro files"
else
  pass "no pacman/yay in quattro files"
fi

# upstream checkout stays read-only: phase only clones/fetches/checkouts
if grep -qE 'git (push|commit|reset|rebase|merge)' install/31-quattro-shell.sh; then
  bad "phase mutates upstream checkout"
else
  pass "phase never mutates the upstream checkout"
fi

echo
if ((FAIL)); then
  echo "QUATTRO TESTS: FAILED"
  exit 1
fi
echo "QUATTRO TESTS: OK"
