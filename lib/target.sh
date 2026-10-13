# shellcheck shell=bash
# Target user + initial theme resolution for omarchy-debian.
# Source this file; do not execute it (after lib/log.sh for warn/die).
#
# Public interface:
#   resolve_target_user <cli-value>     (empty cli-value = "not provided")
#     Precedence: CLI > OMARCHY_TARGET_USER env > interactive prompt (tty)
#     > safe unattended default. The unattended default is a valid non-root
#     SUDO_USER when running as root, otherwise the invoking non-root user.
#     Nonexistent accounts and root are rejected with a clear error.
#     Exports: OMARCHY_TARGET_USER, OMARCHY_TARGET_UID, OMARCHY_TARGET_GID,
#              OMARCHY_TARGET_HOME (resolved with `getent passwd`, never
#              /home/$USER string building).
#   resolve_theme <cli-value>
#     Precedence: CLI > OMARCHY_THEME env > interactive prompt (tty) >
#     OMARCHY_DEFAULT_THEME. Exports OMARCHY_THEME_SELECTED. Existence of the
#     theme directory is validated against the pinned quattro checkout by the
#     quattro phase; this function only rejects malformed names.
#   omd_install / omd_install_dir / omd_chown_path
#     Deploy files/directories into the target home with target ownership,
#     even when the installer runs through sudo/root.
#
# Test seams (never set in production): OMARCHY_DEBIAN_FAKE_EUID overrides the
# effective-uid check (EUID itself is readonly in bash, so the override is
# honored first); OMARCHY_DEBIAN_NO_PROMPT forces the unattended path.

if [[ -n ${OMARCHY_DEBIAN_TARGET_LOADED:-} ]]; then
  return 0
fi
OMARCHY_DEBIAN_TARGET_LOADED=1

# Fallbacks so this library also works sourced standalone (tests).
declare -F warn >/dev/null || warn() { echo "WARN: $*" >&2; }
declare -F die >/dev/null || die() { echo "ERROR: $*" >&2; exit 1; }

OMARCHY_DEFAULT_THEME="tokyo-night"

_omd_euid() { printf '%s' "${OMARCHY_DEBIAN_FAKE_EUID:-$EUID}"; }
_omd_interactive() {
  [[ -z ${OMARCHY_DEBIAN_NO_PROMPT:-} && -t 0 && -t 1 ]]
}

# 0 when <name> is an existing non-root Linux account.
_omd_valid_target_user() {
  local name=$1 entry
  [[ -n $name && $name != "." && $name != ".." && $name != */* ]] || return 1
  entry=$(getent passwd "$name") || return 1
  [[ $(cut -d: -f3 <<<"$entry") != "0" ]]
}

# Safe unattended default target user (no prompting). Echoes the name.
_omd_default_target_user() {
  local candidate
  if (( $(_omd_euid) == 0 )); then
    # Running as root (e.g. `sudo ./install.sh`): prefer the account that
    # invoked sudo when it is a valid non-root account.
    candidate=${SUDO_USER:-}
    if _omd_valid_target_user "$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
    candidate=$(id -un)
    if _omd_valid_target_user "$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
    return 1 # root shell without a usable SUDO_USER: refuse to guess
  fi
  printf '%s' "$(id -un)"
}

resolve_target_user() {
  local cli=${1:-} chosen origin default answer attempts=0 entry
  if [[ -n $cli ]]; then
    chosen=$cli origin="cli"
  elif [[ -n ${OMARCHY_TARGET_USER:-} ]]; then
    chosen=$OMARCHY_TARGET_USER origin="environment"
  elif _omd_interactive; then
    default=$(_omd_default_target_user || true)
    while :; do
      if [[ -n $default ]]; then
        printf 'Which existing Linux user should receive the Omarchy configuration? [%s] ' "$default"
      else
        printf 'Which existing Linux user should receive the Omarchy configuration? '
      fi
      IFS= read -r answer || answer=""
      [[ -z $answer && -n $default ]] && answer=$default
      if _omd_valid_target_user "$answer"; then
        chosen=$answer origin="prompt"
        break
      fi
      warn "user '${answer:-}' is not an existing non-root Linux account"
      ((++attempts >= 5)) && die "no valid target user selected"
    done
  else
    chosen=$(_omd_default_target_user) ||
      die "cannot determine a target user: run through sudo from a user account, or pass --user <name>"
    origin="unattended default"
  fi

  _omd_valid_target_user "$chosen" ||
    die "target user '$chosen' does not exist or is root — refusing to continue"

  entry=$(getent passwd "$chosen") || die "target user '$chosen' disappeared"
  OMARCHY_TARGET_USER=$chosen
  OMARCHY_TARGET_UID=$(cut -d: -f3 <<<"$entry")
  OMARCHY_TARGET_GID=$(cut -d: -f4 <<<"$entry")
  OMARCHY_TARGET_HOME=$(cut -d: -f6 <<<"$entry")
  export OMARCHY_TARGET_USER OMARCHY_TARGET_UID OMARCHY_TARGET_GID OMARCHY_TARGET_HOME
  [[ -n ${OMARCHY_TARGET_ANNOUNCED:-} ]] ||
    log "target user: $OMARCHY_TARGET_USER (uid $OMARCHY_TARGET_UID, home $OMARCHY_TARGET_HOME, via $origin)"
  OMARCHY_TARGET_ANNOUNCED=1
  export OMARCHY_TARGET_ANNOUNCED
}

_omd_valid_theme_name() {
  local name=$1
  [[ -n $name && $name != "." && $name != ".." && $name != .* && $name != */* ]]
}

resolve_theme() {
  local cli=${1:-} chosen answer attempts=0
  if [[ -n $cli ]]; then
    chosen=$cli
  elif [[ -n ${OMARCHY_THEME:-} ]]; then
    chosen=$OMARCHY_THEME
  elif _omd_interactive; then
    while :; do
      printf 'Which initial Quattro theme? [%s] ' "$OMARCHY_DEFAULT_THEME"
      IFS= read -r answer || answer=""
      [[ -z $answer ]] && answer=$OMARCHY_DEFAULT_THEME
      if _omd_valid_theme_name "$answer"; then
        chosen=$answer
        break
      fi
      warn "invalid theme name '$answer'"
      ((++attempts >= 5)) && die "no valid theme selected"
    done
  else
    chosen=$OMARCHY_DEFAULT_THEME
  fi

  _omd_valid_theme_name "$chosen" ||
    die "invalid theme '$chosen': theme names are plain directory names"

  OMARCHY_THEME_SELECTED=$chosen
  export OMARCHY_THEME_SELECTED
}

# --- deploy helpers (target ownership under sudo/root) ------------------------

omd_as_root() { (( $(_omd_euid) == 0 )); }

# omd_install <mode> <src> <dst> — file, created with target ownership.
omd_install() {
  local mode=$1
  shift
  if omd_as_root; then
    install -Dm"$mode" -o "$OMARCHY_TARGET_UID" -g "$OMARCHY_TARGET_GID" "$@"
  else
    install -Dm"$mode" "$@"
  fi
}

# omd_install_dir <dir>... — directories, created with target ownership.
omd_install_dir() {
  if omd_as_root; then
    install -d -o "$OMARCHY_TARGET_UID" -g "$OMARCHY_TARGET_GID" "$@"
  else
    install -d "$@"
  fi
}

# omd_chown_path <path>... — recursively take target ownership (root only;
# a no-op otherwise, where files already belong to the invoking user).
omd_chown_path() {
  omd_as_root || return 0
  local p
  for p in "$@"; do
    [[ -e $p || -L $p ]] || continue
    chown -R "$OMARCHY_TARGET_UID:$OMARCHY_TARGET_GID" "$p"
  done
}
