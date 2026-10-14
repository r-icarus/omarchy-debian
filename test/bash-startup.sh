#!/bin/bash
# Exercise only the shell-hook section: no system files or live HOME changes.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home"
export HOME="$TMP/home" OMARCHY_DEBIAN_ROOT="$ROOT"
export OMARCHY_PATH="$TMP/upstream" OVERLAY="$ROOT/overlay" DRY_RUN=0
printf '# user customization\nexport CUSTOM_SHELL_SETTING=yes\n' >"$HOME/.bashrc"
# Extract the installer's shell hookup only, excluding system/config deployment.
awk '/^# --- 4\. shell hookup/ {copy=1} /^# --- 5\. state dirs/ {copy=0} copy' \
  "$ROOT/install/50-dotfiles.sh" >"$TMP/hook.sh"
log() { :; }
export -f log
bash "$TMP/hook.sh"
grep -Fq 'export CUSTOM_SHELL_SETTING=yes' "$HOME/.bashrc"
grep -Fq 'default/bash/rc' "$HOME/.bashrc"
grep -Fq "$ROOT/overlay/bin:$OMARCHY_PATH/bin" "$HOME/.bashrc"
[[ -f $HOME/.bashrc.pre-omarchy ]]
cp "$HOME/.bashrc" "$TMP/first"
bash "$TMP/hook.sh"
cmp "$TMP/first" "$HOME/.bashrc"
# Upgrades replace a stale managed block instead of silently leaving it behind.
printf '# >>> omarchy-debian >>>\nexport STALE_BLOCK=yes\n# <<< omarchy-debian <<<\n' >>"$HOME/.bashrc"
bash "$TMP/hook.sh"
! grep -q STALE_BLOCK "$HOME/.bashrc"
[[ $(grep -c '^# >>> omarchy-debian >>>$' "$HOME/.bashrc") == 1 ]]
echo 'Bash startup tests passed'
