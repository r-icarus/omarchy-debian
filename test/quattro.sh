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
  if "$@"; then pass "$desc"; else bad "$desc"; fi
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
required = {"omarchy.menu", "omarchy.workspaces", "omarchy.clock", "omarchy.tray",
            "omarchy.network", "omarchy.power", "omarchy.bluetooth", "omarchy.monitor",
            "omarchy.keyboard-layout", "omarchy.indicators", "omarchy.elsewhen",
            "omarchy.weather", "omarchy.agents", "omarchy.system-update"}
missing = required - set(ids)
assert not missing, f"missing required widgets: {missing}"
known = {
  "omarchy.menu", "omarchy.workspaces", "omarchy.active-window",
  "omarchy.clock", "omarchy.tray", "omarchy.audio", "omarchy.indicators",
  "omarchy.keyboard-layout", "omarchy.microphone", "omarchy.spacer",
  "omarchy.system-update", "omarchy.network", "omarchy.power",
  "omarchy.bluetooth", "omarchy.monitor", "omarchy.agents",
  "omarchy.elsewhen", "omarchy.weather",
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
check "Quickshell app menu installs gtk-launch dependency" grep -q 'apt_install libgtk-3-bin' install/31-quattro-shell.sh
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
if grep -rnE '\b(pacman|yay)\b' install/31-quattro-shell.sh overlay/bin/omarchy-quattro-* lib/target.sh >/dev/null 2>&1; then
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

# =============================================================================
# Target user + initial Quattro theme (OMARCHY_TARGET_USER / OMARCHY_THEME)
#
# Interface under test (nothing else):
#   CLI:   ./install.sh --user <name> --theme <theme>
#   env:   OMARCHY_TARGET_USER / OMARCHY_THEME
#   order: CLI > environment > interactive prompt > safe unattended default
#   unattended default user: valid non-root SUDO_USER (root installer), else
#                            the invoking non-root user
#   theme default: tokyo-night; validated against the pinned quattro checkout
#   target home: resolved with `getent passwd` (never /home/$USER)
#   deployment: into the target home, owned by the target user, backup-first,
#               idempotent; rollback restores pre-existing theme state.
#
# Harness notes:
#   * The real account ${OMARCHY_TEST_USER:-rice} (same uid as the test
#     runner) provides identity/ownership checks, but a getent shim maps its
#     home to a disposable directory under TMP. Tests never clean the real home.
#   * A local git repo fakes upstream omarchy@quattro with the genuine theme
#     layout; the run passes OMARCHY_QUATTRO_REF=<fake HEAD>; no network.
#   * sudo/apt/apt-cache/curl/quickshell/systemctl shims keep it offline; the
#     sudo shim satisfies install.sh's auth probes and denies real commands.
#   * `script` provides a real pty for the interactive prompt tests.
# =============================================================================

TEST_USER=${OMARCHY_TEST_USER:-rice}
TEST_UID=$(id -u "$TEST_USER" 2>/dev/null || true)
TEST_GROUP=$(id -gn "$TEST_USER" 2>/dev/null || true)
REAL_TEST_HOME=$(getent passwd "$TEST_USER" | cut -d: -f6)
GT="$TMP/target-home"
mkdir -p "$GT"
INVOKING_UID=$(id -u)
if [[ -z $TEST_UID || -z $TEST_GROUP || -z $REAL_TEST_HOME ]]; then
  bad "test account '$TEST_USER' must exist (getent) for target-user tests"
elif [[ $TEST_UID == 0 || $TEST_UID != "$INVOKING_UID" ]]; then
  bad "test account '$TEST_USER' (uid ${TEST_UID}) must be non-root and match the invoking uid ${INVOKING_UID}"
else
  pass "test account $TEST_USER (uid $TEST_UID, home $GT) usable as target"
fi
command -v script >/dev/null || bad "'script' (util-linux) required for interactive prompt tests"
command -v timeout >/dev/null || bad "'timeout' (coreutils) required"

SHIM=$TMP/shim
H=$TMP/invoke
FQ=$TMP/quattro-src
mkdir -p "$SHIM" "$H"

# Keep target-user resolution realistic while confining all writes to TMP.
cat >"$SHIM/getent" <<'EOF'
#!/bin/bash
if [[ ${1:-} == passwd && ${2:-} == ${FAKE_TARGET_USER:-} && -n ${FAKE_TARGET_HOME:-} ]]; then
  printf '%s:x:%s:%s:Quattro test user:%s:/bin/bash\n' \
    "$FAKE_TARGET_USER" "$FAKE_TARGET_UID" "$FAKE_TARGET_GID" "$FAKE_TARGET_HOME"
  exit 0
fi
exec /usr/bin/getent "$@"
EOF
chmod +x "$SHIM/getent"

# --- fake upstream repo: branch quattro with the genuine theme layout ----------
mkdir -p "$FQ/themes/tokyo-night/backgrounds" "$FQ/themes/gruvbox/backgrounds" "$FQ/shell"
printf 'mode = "dark"\naccent = "#7aa2f7"\n' >"$FQ/themes/tokyo-night/colors.toml"
printf 'text = "#a9b1d6"\n' >"$FQ/themes/tokyo-night/shell.toml"
printf 'X' >"$FQ/themes/tokyo-night/backgrounds/0-dawn.jpg"
printf 'Y' >"$FQ/themes/tokyo-night/backgrounds/1-dusk.jpg"
printf 'mode = "dark"\naccent = "#fb4934"\n' >"$FQ/themes/gruvbox/colors.toml"
printf 'G' >"$FQ/themes/gruvbox/backgrounds/0-gruv.jpg"
printf 'root\n' >"$FQ/shell/qml"
git -C "$FQ" init -q -b quattro
git -C "$FQ" add -A
git -C "$FQ" -c user.email=test@test -c user.name=test commit -qm "themes"
FQREF=$(git -C "$FQ" rev-parse HEAD)

# --- shims ---------------------------------------------------------------------
cat >"$SHIM/sudo" <<'EOF'
#!/bin/bash
# Satisfy install.sh's auth probes; deny (but log) every real command so the
# test can never mutate the host through sudo.
case "$*" in
  true | -v | -n\ true) exit 0 ;;
  *) ;;
esac
printf 'SUDO-DENIED %s\n' "$*" >>"${FAKE_SHIM_LOG:-/dev/null}"
exit 1
EOF
cat >"$SHIM/apt-get" <<'EOF'
#!/bin/bash
printf 'APT-GET %s\n' "$*" >>"${FAKE_SHIM_LOG:-/dev/null}"
exit 0
EOF
cat >"$SHIM/apt" <<'EOF'
#!/bin/bash
printf 'APT %s\n' "$*" >>"${FAKE_SHIM_LOG:-/dev/null}"
exit 0
EOF
cat >"$SHIM/apt-cache" <<'EOF'
#!/bin/bash
# no candidates ever -> packages read as unavailable
exit 0
EOF
cat >"$SHIM/curl" <<'EOF'
#!/bin/bash
printf 'CURL %s\n' "$*" >>"${FAKE_SHIM_LOG:-/dev/null}"
exit 1
EOF
cat >"$SHIM/quickshell" <<'EOF'
#!/bin/bash
echo "0.3.2-testshim"
EOF
cat >"$SHIM/systemctl" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$SHIM"/*
export FAKE_SHIM_LOG=$TMP/shim.log
: >"$FAKE_SHIM_LOG"

# --- runners -------------------------------------------------------------------
EXTRA_ENV=()
run_install() { # <invoking-home> <install.sh args...> -> combined output
  local h=$1
  shift
  env -i PATH="$SHIM:$PATH" HOME="$h" TERM=dumb \
    FAKE_TARGET_USER="$TEST_USER" FAKE_TARGET_UID="$TEST_UID" \
    FAKE_TARGET_GID="$(id -g "$TEST_USER")" FAKE_TARGET_HOME="$GT" \
    OMARCHY_QUATTRO_REPO="file://$FQ" \
    OMARCHY_QUATTRO_REF="$FQREF" \
    OMARCHY_QUATTRO_PATH="$GT/.local/share/omarchy-quattro" \
    OMARCHY_DEBIAN_LOG_FILE="$h/install.log" \
    ${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"} \
    timeout 120 bash "$ROOT/install.sh" "$@" 2>&1
}

run_phase31() { # <target-user> <theme> -> combined output; rc in PHASE_RC
  env -i PATH="$SHIM:$PATH" HOME="$H" TERM=dumb \
    FAKE_TARGET_USER="$TEST_USER" FAKE_TARGET_UID="$TEST_UID" \
    FAKE_TARGET_GID="$(id -g "$TEST_USER")" FAKE_TARGET_HOME="$GT" \
    OMARCHY_DEBIAN_ROOT="$ROOT" \
    OMARCHY_DEBIAN_PROFILE=quattro \
    OMARCHY_DEBIAN_DRY_RUN=0 \
    OMARCHY_QUATTRO_REPO="file://$FQ" \
    OMARCHY_QUATTRO_REF="$FQREF" \
    OMARCHY_QUATTRO_PATH="$GT/.local/share/omarchy-quattro" \
    OMARCHY_TARGET_USER="$1" \
    OMARCHY_THEME="$2" \
    timeout 120 bash "$ROOT/install/31-quattro-shell.sh" 2>&1
}

run_pty() { # <answers-file> <invoking-home> <args...>  (real pty via script)
  local answers=$1 h=$2 a
  local cmd="timeout 120 env -i PATH='$SHIM:$PATH' HOME='$h' TERM=xterm \
FAKE_TARGET_USER='$TEST_USER' FAKE_TARGET_UID='$TEST_UID' FAKE_TARGET_GID='$(id -g "$TEST_USER")' FAKE_TARGET_HOME='$GT' \
OMARCHY_QUATTRO_REPO='file://$FQ' OMARCHY_QUATTRO_REF='$FQREF' \
OMARCHY_QUATTRO_PATH='$GT/.local/share/omarchy-quattro' \
OMARCHY_DEBIAN_LOG_FILE='$h/install.log' bash '$ROOT/install.sh'"
  shift 2
  for a in "$@"; do
    cmd+=" $(printf '%q' "$a")"
  done
  script -qec "$cmd" /dev/null <"$answers" 2>&1 || true
}

clean_target() { # wipe only the isolated target home under this test's TMP
  [[ $GT == "$TMP/target-home" ]] || { bad "refusing to clean non-temporary target home: $GT"; return 1; }
  rm -rf -- "$GT"
  mkdir -p "$GT"
}

CUR="$GT/.local/state/omarchy/current"
CLONE="$GT/.local/share/omarchy-quattro"
last3() { tail -3 <<<"$1" | tr '\n' ' '; }

# --- resolution --------------------------------------------------------------
# 1. unattended defaults: invoking user + tokyo-night (dry-run states both)
clean_target
out=$(run_install "$H" --dry-run)
grep -q "target user: $TEST_USER" <<<"$out" &&
  pass "unattended default target user is the invoking user ($TEST_USER)" ||
  bad "unattended default user (out: $(last3 "$out"))"
grep -q "initial theme: tokyo-night" <<<"$out" &&
  pass "unattended default theme is tokyo-night" ||
  bad "default theme (out: $(last3 "$out"))"

# 2. environment tier honored
clean_target
EXTRA_ENV=(OMARCHY_TARGET_USER="$TEST_USER" OMARCHY_THEME=gruvbox)
out=$(run_install "$H" --dry-run)
EXTRA_ENV=()
grep -q "target user: $TEST_USER" <<<"$out" &&
  grep -q "initial theme: gruvbox" <<<"$out" &&
  pass "OMARCHY_TARGET_USER/OMARCHY_THEME environment honored" ||
  bad "env tier (out: $(last3 "$out"))"

# 3. CLI beats environment
clean_target
EXTRA_ENV=(OMARCHY_TARGET_USER=nosuchuser OMARCHY_THEME=gruvbox)
out=$(run_install "$H" --dry-run --user "$TEST_USER" --theme tokyo-night)
EXTRA_ENV=()
grep -q "target user: $TEST_USER" <<<"$out" &&
  grep -q "initial theme: tokyo-night" <<<"$out" &&
  pass "CLI --user/--theme beat environment" ||
  bad "CLI precedence (out: $(last3 "$out"))"

# 4. SUDO_USER default tier (unit probes with faked EUID; no root on this host)
su_probe() { # <faked-euid> <SUDO_USER> -> resolved user printed
  env -i PATH="$SHIM:$PATH" HOME="$H" \
    OMARCHY_DEBIAN_FAKE_EUID="$1" SUDO_USER="$2" TEST_USER="$TEST_USER" \
    bash -c '
      source "'"$ROOT"'/lib/target.sh"
      resolve_target_user "" >/dev/null 2>&1
      echo "${OMARCHY_TARGET_USER:-}"' 2>/dev/null
}
[[ $(su_probe 0 "$TEST_USER") == "$TEST_USER" ]] &&
  pass "root installer defaults to valid non-root SUDO_USER" ||
  bad "SUDO_USER default (got: $(su_probe 0 "$TEST_USER"))"
[[ $(su_probe 0 root) == "$TEST_USER" ]] &&
  pass "root SUDO_USER is rejected, falls back to invoking user" ||
  bad "SUDO_USER=root fallback (got: $(su_probe 0 root))"
[[ $(su_probe 0 ghost-user-xyz) == "$TEST_USER" ]] &&
  pass "nonexistent SUDO_USER falls back to invoking user" ||
  bad "SUDO_USER fallback (got: $(su_probe 0 ghost-user-xyz))"
[[ $(su_probe 1000 "$TEST_USER") == "$TEST_USER" ]] &&
  pass "non-root installer ignores SUDO_USER (uses current user)" ||
  bad "non-root SUDO_USER ignore (got: $(su_probe 1000 "$TEST_USER"))"

# --- validation --------------------------------------------------------------
# 5. nonexistent user rejected
clean_target
out=$(run_install "$H" --dry-run --user nosuchuser-omarchy-test)
st=$?
((st != 0)) && grep -qi "does not exist" <<<"$out" &&
  pass "nonexistent user rejected with nonzero exit" ||
  bad "nonexistent user rejection (exit $st, out: $(last3 "$out"))"

# 6. root rejected as target
clean_target
out=$(run_install "$H" --dry-run --user root)
st=$?
((st != 0)) && grep -qi "root" <<<"$out" &&
  pass "root rejected as target user" ||
  bad "root rejection (exit $st, out: $(last3 "$out"))"

# 7. invalid theme rejected against the pinned checkout (phase-level)
clean_target
out=$(run_phase31 "$TEST_USER" invalid-theme-xyz)
st=$?
((st != 0)) && grep -qi "invalid theme" <<<"$out" && [[ ! -e $CUR ]] &&
  pass "invalid theme rejected, no state written" ||
  bad "invalid theme rejection (exit $st, out: $(last3 "$out"))"

# --- theme initialization (genuine, Debian-safe subset) ------------------------
# 8. valid init through the phase: staged subset + name + background symlink
clean_target
out=$(run_phase31 "$TEST_USER" tokyo-night)
[[ -f $CUR/theme/colors.toml ]] &&
  grep -q '#7aa2f7' "$CUR/theme/colors.toml" &&
  pass "current/theme/colors.toml initialized from the pinned checkout" ||
  bad "colors.toml init (out: $(last3 "$out"))"
[[ -f $CUR/theme/shell.toml ]] &&
  pass "current/theme/shell.toml staged when the theme ships one" ||
  bad "shell.toml staging"
[[ $(<"$CUR/theme.name") == "tokyo-night" ]] &&
  pass "current/theme.name records tokyo-night" ||
  bad "theme.name content: $(cat "$CUR/theme.name" 2>/dev/null)"
[[ -L $CUR/background ]] && [[ -f $CUR/background ]] &&
  [[ $(readlink -f "$CUR/background") == "$CUR/theme/backgrounds/"* ]] &&
  pass "current/background symlink resolves inside the staged theme" ||
  bad "background symlink ($(readlink "$CUR/background" 2>/dev/null))"
[[ ! -e $CUR/theme/neovim.lua && ! -e $CUR/theme/vscode.json && ! -e $CUR/theme/icons.theme ]] &&
  pass "Debian-safe subset: only colors/shell/backgrounds staged" ||
  bad "non-subset file staged in current/theme"
[[ ! -e $GT/.config/alacritty && ! -e $GT/.config/foot && ! -e $GT/.config/tmux ]] &&
  pass "no unrelated app configs mutated by theme init" ||
  bad "theme init touched unrelated app configs"

# 9. theme without shell.toml (gruvbox) initializes without one
clean_target
out=$(run_phase31 "$TEST_USER" gruvbox)
[[ -f $CUR/theme/colors.toml && ! -e $CUR/theme/shell.toml ]] &&
  pass "theme without shell.toml initializes without creating one" ||
  bad "gruvbox init (out: $(last3 "$out"))"

# 10. idempotence: second run is a no-op (same tree, same symlink, no backups)
clean_target
run_phase31 "$TEST_USER" tokyo-night >/dev/null
snap1=$( (find "$CUR" -printf '%P:%s\n' | sort; readlink "$CUR/background") )
run_phase31 "$TEST_USER" tokyo-night >/dev/null
snap2=$( (find "$CUR" -printf '%P:%s\n' | sort; readlink "$CUR/background") )
[[ $snap1 == "$snap2" && ! -e $CUR.pre-omarchy ]] &&
  pass "theme initialization is idempotent" ||
  bad "idempotence (snapshots differ or stray backup)"

# --- deployment + ownership ----------------------------------------------------
# 11. deployed under the getent home — not the invoking home, not /home/$USER
clean_target
run_phase31 "$TEST_USER" tokyo-night >/dev/null
[[ -f $GT/.config/omarchy/shell.json && -f $CUR/theme/colors.toml ]] &&
  pass "config+state deployed under the getent-resolved target home" ||
  bad "deployment paths"
if [[ -e $H/.config/omarchy/shell.json || -e $H/.local/state/omarchy/current ]]; then
  bad "deployed into the INVOKING home instead of the target"
else
  pass "nothing deployed into the invoking user's home"
fi

# 12. ownership contract (real same-uid deployment)
own=$(stat -c '%U:%G' "$CUR/theme/colors.toml" 2>/dev/null)
[[ $own == "$TEST_USER:$TEST_GROUP" ]] &&
  pass "deployed state owned by the target user" ||
  bad "state ownership ($own)"
own=$(stat -c '%U:%G' "$GT/.config/omarchy/shell.json" 2>/dev/null)
[[ $own == "$TEST_USER:$TEST_GROUP" ]] &&
  pass "deployed config owned by the target user" ||
  bad "config ownership ($own)"

# 13. ownership helper branches: root passes -o/-g with the target ids;
#     non-root must not (it cannot chown cross-user)
cap=$TMP/omd_args
mkdir -p "$TMP/capturebin"
cat >"$TMP/capturebin/install" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"${CAP:?}"
exit 0
EOF
chmod +x "$TMP/capturebin/install"
omd_probe() { # <faked-euid> -> captured install(1) args on stdout
  cat >"$TMP/omd_probe.sh" <<PROBE
#!/bin/bash
source "$ROOT/lib/target.sh"
OMARCHY_TARGET_UID=$TEST_UID
OMARCHY_TARGET_GID=$(id -g "$TEST_UID")
omd_install 644 /etc/hostname "$TMP/probe/dst"
PROBE
  : >"$cap"
  CAP=$cap OMARCHY_DEBIAN_FAKE_EUID=$1 \
    PATH="$TMP/capturebin:$PATH" bash "$TMP/omd_probe.sh" >/dev/null 2>&1 || true
  cat "$cap" 2>/dev/null
}
args_root=$(omd_probe 0)
grep -q -- "-o $TEST_UID -g $(id -g "$TEST_UID")" <<<"$args_root" &&
  pass "root-path deploy passes -o <uid> -g <gid> for the target" ||
  bad "root-path -o/-g intent (captured: $args_root)"
args_user=$(omd_probe 1000)
grep -vq -- "-o" <<<"$args_user" &&
  pass "non-root deploy omits -o/-g (same-uid default ownership)" ||
  bad "non-root deploy must not pass -o (captured: $args_user)"

# --- backup-first + rollback ----------------------------------------------------
# 14. pre-existing theme state is backed up, and rollback restores it
clean_target
mkdir -p "$CUR/theme"
printf 'mode = "light"\naccent = "#111111"\n' >"$CUR/theme/colors.toml"
printf 'old-theme\n' >"$CUR/theme.name"
ln -s /usr/share/backgrounds/old.jpg "$CUR/background"
run_phase31 "$TEST_USER" tokyo-night >/dev/null
[[ -f $CUR.pre-omarchy/theme/colors.toml ]] &&
  [[ $(<"$CUR.pre-omarchy/theme.name") == "old-theme" ]] &&
  pass "pre-existing theme state backed up before change" ||
  bad "theme backup"
rb=$(env -i PATH="$SHIM:$PATH" HOME="$GT" TERM=dumb \
  timeout 60 bash "$ROOT/overlay/bin/omarchy-quattro-rollback" 2>&1)
[[ -f $CUR/theme/colors.toml && $(<"$CUR/theme.name") == "old-theme" ]] &&
  grep -q '#111111' "$CUR/theme/colors.toml" &&
  pass "rollback restores the previous theme state" ||
  bad "rollback theme restore (out: $(last3 "$rb"))"
[[ $(readlink "$CUR/background" 2>/dev/null) == "/usr/share/backgrounds/old.jpg" ]] &&
  pass "rollback restores the previous background symlink" ||
  bad "rollback background symlink ($(readlink "$CUR/background" 2>/dev/null))"
[[ ! -d $CLONE ]] &&
  pass "rollback removes the quattro clone" ||
  bad "rollback clone removal"

# 15. rollback with NO prior theme state removes what init created
clean_target
run_phase31 "$TEST_USER" tokyo-night >/dev/null
env -i PATH="$SHIM:$PATH" HOME="$GT" TERM=dumb \
  timeout 60 bash "$ROOT/overlay/bin/omarchy-quattro-rollback" >/dev/null 2>&1
[[ ! -e $CUR && ! -d $CLONE ]] &&
  pass "rollback removes theme state when no backup existed" ||
  bad "rollback without prior state"

# --- end-to-end through install.sh ----------------------------------------------
# 16. env-supplied user+theme through the full entry point
clean_target
out=$(run_install "$H" --profile quattro --user "$TEST_USER" --theme tokyo-night \
  --phases 31-quattro-shell.sh)
st=$?
((st == 0)) && [[ -f $CUR/theme/colors.toml && $(<"$CUR/theme.name") == "tokyo-night" &&
  -f $GT/.config/omarchy/shell.json ]] &&
  pass "e2e: install.sh --user/--theme deploys theme+config to the target" ||
  bad "e2e deployment (exit $st, out: $(last3 "$out"))"
own=$(stat -c '%U' "$GT/.config/omarchy/shell.json" 2>/dev/null)
[[ $own == "$TEST_USER" ]] &&
  pass "e2e: deployed files carry target ownership" ||
  bad "e2e ownership ($own)"

# 17. invalid theme aborts the run through install.sh
clean_target
out=$(run_install "$H" --profile quattro --user "$TEST_USER" --theme nope \
  --phases 31-quattro-shell.sh)
st=$?
((st != 0)) && grep -qi "invalid theme" <<<"$out" && [[ ! -e $CUR ]] &&
  pass "e2e: invalid theme aborts install with nonzero exit" ||
  bad "e2e invalid theme (exit $st, out: $(last3 "$out"))"

# --- interactive prompt ------------------------------------------------------------
# 18. interactive with omissions asks for user then theme; answers are used
clean_target
A=$TMP/answers1
printf '%s\ntokyo-night\n' "$TEST_USER" >"$A"
out=$(run_pty "$A" "$H" --profile quattro --user "" --theme "" \
  --phases 31-quattro-shell.sh)
grep -qi "which existing linux user" <<<"$out" &&
  pass "interactive prompt asks for the target user" ||
  bad "user prompt missing (out: $(head -c 300 <<<"$out")…)"
grep -qi "initial quattro theme" <<<"$out" &&
  pass "interactive prompt asks for the initial theme" ||
  bad "theme prompt missing (out: $(head -c 300 <<<"$out")…)"
[[ -f $CUR/theme/colors.toml && $(<"$CUR/theme.name") == "tokyo-night" ]] &&
  pass "interactive answers determine user + theme" ||
  bad "interactive deployment"
own=$(stat -c '%U' "$CUR/theme/colors.toml" 2>/dev/null)
[[ $own == "$TEST_USER" ]] &&
  pass "interactive deployment owned by the chosen user" ||
  bad "interactive ownership ($own)"

# 19. non-interactive with omissions never blocks on a prompt
clean_target
out=$(run_install "$H" --profile quattro --user "" --theme "" \
  --phases 31-quattro-shell.sh </dev/null)
st=$?
if ((st == 0)) && ! grep -qi "which existing linux user" <<<"$out" &&
  [[ $(cat "$CUR/theme.name" 2>/dev/null) == "tokyo-night" ]]; then
  pass "unattended run never prompts, deploys default theme"
else
  bad "unattended run (exit $st, out: $(last3 "$out"))"
fi

# --- docs ---------------------------------------------------------------------------
# 20. exact CLI/env interface documented (ricardo/tokyo-night literals)
d1=$(grep -c -- '--user ricardo' README.md docs/QUATTRO-QUICKSHELL.md 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
d2=$(grep -c -- '--theme tokyo-night' README.md docs/QUATTRO-QUICKSHELL.md 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
d3=$(grep -c 'OMARCHY_TARGET_USER=ricardo' README.md docs/QUATTRO-QUICKSHELL.md 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
d4=$(grep -c 'OMARCHY_THEME=tokyo-night' README.md docs/QUATTRO-QUICKSHELL.md 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
((d1 > 0 && d2 > 0 && d3 > 0 && d4 > 0)) &&
  pass "README + QUATTRO docs document the exact CLI/env interface" ||
  bad "docs missing --user/--theme/OMARCHY_* (counts: $d1/$d2/$d3/$d4)"
grep -q 'tokyo-night' docs/QUATTRO-QUICKSHELL.md &&
  grep -q 'OMARCHY_QUATTRO_REF' docs/QUATTRO-QUICKSHELL.md &&
  pass "default theme + pinned-ref validation documented" ||
  bad "default theme / pinned-ref docs"

clean_target

echo
if ((FAIL)); then
  echo "QUATTRO TESTS: FAILED"
  exit 1
fi
echo "QUATTRO TESTS: OK"
