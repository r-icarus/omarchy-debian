#!/bin/bash
# Optional profile: native Omarchy Quattro (Quickshell) top bar.
#
# Enabled with:  ./install.sh --profile quattro
#   --user <name> / OMARCHY_TARGET_USER   target Linux account (default: the
#                                         invoking user, or SUDO_USER as root)
#   --theme <name> / OMARCHY_THEME        initial theme (default: tokyo-night)
#
# What this phase does:
#   1. Clones omacom/omarchy branch `quattro` read-only at a pinned commit to
#      $OMARCHY_QUATTRO_PATH (separate from the default/master checkout; the
#      upstream tree is never modified).
#   2. Initializes the Debian-safe subset of the selected theme — colors.toml,
#      shell.toml when the theme ships one, the current theme directory/name,
#      and the current background symlink — under the TARGET user's
#      ~/.local/state/omarchy/current/, mirroring upstream omarchy-theme-set.
#      No upstream hooks run: nothing that assumes Arch, retints unrelated
#      apps, or mutates other apps/packages.
#   3. Installs the Quickshell runtime: the distro package when apt carries
#      one (Debian forky/sid/trixie-backports), else a pinned upstream .deb
#      pair (quickshell + libcpptrace, sha256-verified) from the DankLinux
#      PPA *pool* — no third-party repository is ever added to the system.
#      On PikaOS this means its repositories, kernel, Mesa/NVIDIA stack,
#      bootloader, and updater stay untouched.
#   4. Deploys a curated shell.json (backup-first) to the TARGET user's
#      ~/.config/omarchy/ limiting the bar to widgets whose dependencies are
#      satisfied by the quickshell binary itself (workspaces, active window,
#      clock, tray, indicators via the clock/menu, audio via PipeWire).
#
# All user configuration/state is deployed with target ownership even when
# this phase runs through sudo/root. Existing theme state is backed up first
# to ~/.local/state/omarchy/current.pre-omarchy; omarchy-quattro-rollback
# restores it. Everything is idempotent.
#
# The Hyprland wiring (exec-once launch, bar toggle, menu binding) lives in
# overlay/config/hypr/hyprland.conf + overlay/bin/omarchy-quattro-* and is
# deployed by 50-dotfiles; it degrades to waybar when quickshell is absent.

set -euo pipefail
source "$OMARCHY_DEBIAN_ROOT/lib/log.sh"
source "$OMARCHY_DEBIAN_ROOT/lib/detect.sh"
source "$OMARCHY_DEBIAN_ROOT/lib/apt.sh"
source "$OMARCHY_DEBIAN_ROOT/lib/target.sh"

if [[ ${OMARCHY_DEBIAN_PROFILE:-} != "quattro" ]]; then
  log "profile 'quattro' not selected — skipping native Quickshell bar (use ./install.sh --profile quattro)"
  exit 0
fi

detect_distro

# Pinned upstream ref (omacom/omarchy, branch `quattro`). Bump to track newer.
: "${OMARCHY_QUATTRO_REPO:=https://github.com/omacom/omarchy.git}"
: "${OMARCHY_QUATTRO_REF:=7e7a5600a3c989eb8658dd12409fa7e0479078bb}"
: "${OMARCHY_QUATTRO_PATH:=${OMARCHY_TARGET_HOME:-$HOME}/.local/share/omarchy-quattro}"
export OMARCHY_QUATTRO_PATH

DRY_RUN=${OMARCHY_DEBIAN_DRY_RUN:-0}

# --- 0. target user + theme (resolution normally done by install.sh) -----------
resolve_target_user "${OMARCHY_TARGET_USER:-}"
TARGET_HOME=$OMARCHY_TARGET_HOME
OMARCHY_THEME=${OMARCHY_THEME:-$OMARCHY_DEFAULT_THEME}
export OMARCHY_THEME

if is_pikaos; then
  log "PikaOS detected — PikaOS repositories, kernel, Mesa/NVIDIA stack,"
  log "bootloader, and updater are never touched by this phase."
fi

# --- 1. pinned quattro checkout (read-only) -----------------------------------
if [[ $DRY_RUN == "1" ]]; then
  log "dry-run: clone $OMARCHY_QUATTRO_REPO (quattro@$OMARCHY_QUATTRO_REF) -> $OMARCHY_QUATTRO_PATH"
else
  if [[ ! -d $OMARCHY_QUATTRO_PATH/.git ]]; then
    log "cloning upstream omarchy (quattro) -> $OMARCHY_QUATTRO_PATH"
    omd_install_dir "$(dirname "$OMARCHY_QUATTRO_PATH")"
    git clone --quiet --branch quattro "$OMARCHY_QUATTRO_REPO" "$OMARCHY_QUATTRO_PATH"
    omd_chown_path "$OMARCHY_QUATTRO_PATH"
  fi
  (
    cd "$OMARCHY_QUATTRO_PATH"
    if [[ $(git rev-parse HEAD) != "$OMARCHY_QUATTRO_REF" ]]; then
      log "checking out pinned quattro ref $OMARCHY_QUATTRO_REF"
      git fetch --quiet --depth 1 origin "$OMARCHY_QUATTRO_REF" || git fetch --quiet origin quattro
      git checkout --quiet "$OMARCHY_QUATTRO_REF"
    fi
    if ! git diff --quiet || ! git diff --cached --quiet; then
      warn "$OMARCHY_QUATTRO_PATH has local modifications — the quattro tree must stay pristine."
    fi
  )
  log "quattro checkout at $(git -C "$OMARCHY_QUATTRO_PATH" rev-parse --short HEAD)"
fi

# --- 1b. Debian/PikaOS compatibility patches for the pinned quattro tree -----
# The pinned quattro QML targets a newer quickshell than Debian/PikaOS ship
# (0.3.2): its QML grammar treats `native` and `transient` as reserved tokens.
# Rename those identifiers so the shell parses. Idempotent via git apply --check.
if [[ $DRY_RUN != "1" ]]; then
  PATCH="$OMARCHY_DEBIAN_ROOT/patches/quattro-qml-compat.patch"
  if [[ -f $PATCH ]]; then
    if git -C "$OMARCHY_QUATTRO_PATH" apply --check "$PATCH" 2>/dev/null; then
      git -C "$OMARCHY_QUATTRO_PATH" apply "$PATCH"
      log "applied quattro QML compat patch"
    elif ! git -C "$OMARCHY_QUATTRO_PATH" diff --quiet; then
      log "quattro tree already patched (or locally modified)"
    fi
  fi

  # PikaOS's Hyprland segfaults when a cursor shape fails to resolve: the
  # skeletal `omarchy-startup` blank-cursor theme (left_ptr only, no
  # index.theme) returns null cairo surfaces. Complete it from a full system
  # cursor theme when one is available.
  STARTUP_CURSORS="$OMARCHY_QUATTRO_PATH/default/hypr/cursors/omarchy-startup"
  if [[ -d $STARTUP_CURSORS/cursors ]] \
     && [[ ! -f $STARTUP_CURSORS/index.theme ]] \
     && [[ -d /usr/share/icons/Bibata-Modern-Classic/cursors ]]; then
    cp /usr/share/icons/Bibata-Modern-Classic/cursors/* "$STARTUP_CURSORS/cursors/"
    printf '[Icon Theme]\nName=omarchy-startup\nInherits=hicolor\n' >"$STARTUP_CURSORS/index.theme"
    log "completed omarchy-startup cursor theme from Bibata-Modern-Classic"
  fi
fi

# --- 2. initial theme: Debian-safe subset of the genuine theme -----------------
# Mirrors upstream bin/omarchy-theme-set (quattro@pinned ref): stage
# colors.toml, shell.toml (when shipped), the theme directory + theme.name, and
# the current background symlink under ~/.local/state/omarchy/current/.
# Deliberately NOT run: omarchy-theme-set-templates and the app retint hooks
# (Arch-oriented), shell IPC, and any package hooks. Existing state is backed
# up first; the whole step is idempotent.
CURRENT_STATE="$TARGET_HOME/.local/state/omarchy/current"
CURRENT_THEME_DIR="$CURRENT_STATE/theme"
BUNDLED_THEMES_DIR="$OMARCHY_DEBIAN_ROOT/overlay/quattro/themes"
THEME_SRC_DIR="$OMARCHY_QUATTRO_PATH/themes/$OMARCHY_THEME"
if [[ ! -d $THEME_SRC_DIR && -d $BUNDLED_THEMES_DIR/$OMARCHY_THEME ]]; then
  THEME_SRC_DIR="$BUNDLED_THEMES_DIR/$OMARCHY_THEME"
fi

# Make bundled third-party themes available in Omarchy's user theme picker.
# User-owned files are preserved once as .pre-omarchy-debian before refresh.
if [[ $DRY_RUN != "1" && -d $BUNDLED_THEMES_DIR ]]; then
  while IFS= read -r -d '' src; do
    rel="${src#"$BUNDLED_THEMES_DIR/"}"
    dst="$TARGET_HOME/.config/omarchy/themes/$rel"
    omd_install_dir "$(dirname "$dst")"
    if [[ -f $dst ]] && ! cmp -s "$src" "$dst" && [[ ! -e $dst.pre-omarchy-debian ]]; then
      cp -a "$dst" "$dst.pre-omarchy-debian"
      omd_chown_path "$dst.pre-omarchy-debian"
    fi
    omd_install 644 "$src" "$dst"
  done < <(find "$BUNDLED_THEMES_DIR" -type f -print0)
fi

init_theme_state() {
  if [[ ! -d $THEME_SRC_DIR ]]; then
    die "invalid theme '$OMARCHY_THEME': not present in the pinned quattro checkout ($OMARCHY_QUATTRO_PATH/themes)"
  fi
  [[ -f $THEME_SRC_DIR/colors.toml ]] ||
    die "invalid theme '$OMARCHY_THEME': no colors.toml in $THEME_SRC_DIR"

  # Backup-first: preserve any PRE-EXISTING theme state exactly once. State we
  # deployed on an earlier (idempotent) run is not "pre-existing" — otherwise
  # the second run would snapshot our own output and rollback would "restore"
  # it instead of the user's original state.
  if [[ -e $CURRENT_STATE && ! -e ${CURRENT_STATE}.pre-omarchy && ! -f $CURRENT_STATE/.omarchy-debian-theme ]] ; then
    cp -a "$CURRENT_STATE" "${CURRENT_STATE}.pre-omarchy"
    omd_chown_path "${CURRENT_STATE}.pre-omarchy"
    log "backed up $CURRENT_STATE -> ${CURRENT_STATE}.pre-omarchy"
  fi

  # Idempotent re-init: replace the staged theme with the pinned checkout's.
  rm -rf "$CURRENT_THEME_DIR"
  omd_install_dir "$CURRENT_THEME_DIR"
  local f
  for f in colors.toml shell.toml chromium.theme; do
    [[ -f $THEME_SRC_DIR/$f ]] || continue
    omd_install 644 "$THEME_SRC_DIR/$f" "$CURRENT_THEME_DIR/$f"
  done
  if [[ -d $THEME_SRC_DIR/backgrounds ]]; then
    omd_install_dir "$CURRENT_THEME_DIR/backgrounds"
    while IFS= read -r -d '' f; do
      omd_install 644 "$f" "$CURRENT_THEME_DIR/backgrounds/${f##*/}"
    done < <(find "$THEME_SRC_DIR/backgrounds" -maxdepth 1 -type f -print0)
  fi

  printf '%s\n' "$OMARCHY_THEME" >"$TMP_THEME_NAME"
  omd_install 644 "$TMP_THEME_NAME" "$CURRENT_STATE/theme.name"

  # Current background: first image of the staged theme, as a relative symlink
  # inside the current state dir (same shape upstream's theme-set produces).
  local bg=""
  if [[ -d $CURRENT_THEME_DIR/backgrounds ]]; then
    bg=$(find "$CURRENT_THEME_DIR/backgrounds" -maxdepth 1 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' \
         -o -iname '*.bmp' -o -iname '*.webp' \) | sort | head -1)
  fi
  if [[ -n $bg ]]; then
    ln -sfn "theme/${bg#"$CURRENT_THEME_DIR"/}" "$CURRENT_STATE/background"
    omd_chown_path "$CURRENT_STATE/background"
  fi

  # Marker identifying state deployed by THIS phase (idempotence: never treat
  # our own output as user state to back up on a later run).
  printf '%s\n' "$OMARCHY_QUATTRO_REF" >"$TMP_THEME_MARKER"
  omd_install 644 "$TMP_THEME_MARKER" "$CURRENT_STATE/.omarchy-debian-theme"

  log "initialized theme '$OMARCHY_THEME' -> $CURRENT_STATE (colors.toml$( [[ -f $CURRENT_THEME_DIR/shell.toml ]] && printf ' + shell.toml' ), background: ${bg:-none})"
}

TMP_THEME_NAME=$(mktemp)
TMP_THEME_MARKER=$(mktemp)
trap 'rm -f "$TMP_THEME_NAME" "$TMP_THEME_MARKER"' EXIT
if [[ $DRY_RUN == "1" ]]; then
  log "dry-run: initialize theme '$OMARCHY_THEME' state -> $CURRENT_STATE"
else
  omd_install_dir "$TARGET_HOME/.local/state/omarchy" "$TARGET_HOME/.config/omarchy"
  init_theme_state
fi

# --- 3. Quickshell runtime ------------------------------------------------------
# Pinned upstream .debs (DankLinux PPA pool, direct file URLs — adding the PPA
# repository itself is deliberately NOT done). sha256 pins per architecture.
QS_VERSION="0.3.2ppa1"
CPPTRACE_VERSION="1.0.4ppa8"
QS_POOL="https://ppa.launchpadcontent.net/avengemedia/danklinux/ubuntu/pool/main"
# sha256 pins per architecture (verified against the published pool files).
declare -A QS_SHA256=(
  [amd64]="7d2d7ba66749e7a119db94507f8fef97d563e3bd118006e929a7f24a58878394"
  [arm64]="72cf5a9a0557a38e34c640aa40340e93a741a5053acfb62a1f82d61dbce08f6e"
)
declare -A CPPTRACE_SHA256=(
  [amd64]="bfff5e0fa7e930d373887d24314700a34689313bc01bf7e923ed9539c1e5086b"
  [arm64]="7dc85122649b198cef34d9e88d6c09d21890ec3b027640f3959390a6faa2b83a"
)

install_quickshell_runtime() {
  if command -v quickshell >/dev/null; then
    log "quickshell already installed: $(quickshell --version 2>/dev/null || echo present)"
    return 0
  fi

  # Preferred: the distro's own package (Debian forky/sid/trixie-backports).
  if apt_available quickshell; then
    apt_install quickshell
    return 0
  fi

  local arch
  arch=$(dpkg --print-architecture 2>/dev/null || echo unknown)
  if [[ -z ${QS_SHA256[$arch]:-} ]]; then
    warn "no pinned quickshell build for '$arch' — build from source (docs/QUATTRO-QUICKSHELL.md)"
    return 1
  fi
  local qs_sha=${QS_SHA256[$arch]} cpp_sha=${CPPTRACE_SHA256[$arch]}

  local qs_deb="quickshell_${QS_VERSION}_${arch}.deb"
  local cpp_deb="libcpptrace_${CPPTRACE_VERSION}_${arch}.deb"
  if [[ $DRY_RUN == "1" ]]; then
    log "dry-run: download+verify+install $qs_deb and $cpp_deb (pinned pool URLs)"
    return 0
  fi

  local tmp
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  log "downloading pinned quickshell ${QS_VERSION} (${arch})"
  curl -fsSL -o "$tmp/$qs_deb" "$QS_POOL/q/quickshell/$qs_deb"
  curl -fsSL -o "$tmp/$cpp_deb" "$QS_POOL/c/cpptrace/$cpp_deb"

  printf '%s  %s\n' "$qs_sha" "$tmp/$qs_deb" | sha256sum -c --quiet ||
    die "sha256 mismatch for $qs_deb — refusing to install"
  printf '%s  %s\n' "$cpp_sha" "$tmp/$cpp_deb" | sha256sum -c --quiet ||
    die "sha256 mismatch for $cpp_deb — refusing to install"

  # apt (not dpkg) so the remaining Qt/Wayland dependencies resolve from the
  # system's EXISTING repositories. If the base's Qt is older than the pinned
  # build needs, apt refuses here and we report honestly instead of forcing.
  if ! $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    --no-install-recommends "$tmp/$qs_deb" "$tmp/$cpp_deb"; then
    warn "apt could not resolve the pinned quickshell .deb dependencies"
    warn "(the base release's Qt is likely too old). Build from source instead:"
    warn "  docs/QUATTRO-QUICKSHELL.md#build-from-source"
    return 1
  fi
  log "quickshell $(quickshell --version 2>/dev/null || echo "$QS_VERSION") installed from pinned upstream .debs"
}

install_quickshell_runtime || {
  warn "Quickshell runtime unavailable — the bar stays on the waybar fallback."
  warn "Re-run this phase after a manual quickshell install to switch to the native bar."
  exit 0
}

# QML runtime modules the bar imports that are not hard Depends of the .deb.
for mod in \
  qml6-module-qtqml-workerscript \
  qml6-module-qtquick-layouts \
  qml6-module-qtquick-controls \
  qml6-module-qtquick-window \
  qml6-module-qtquick-templates; do
  if apt_available "$mod"; then
    apt_install "$mod" || warn "could not install $mod (widget may fail to load)"
  else
    warn "QML module not packaged on this release: $mod"
  fi
done

# --- 4. curated bar config (backup-first, idempotent, target-owned) ------------
SHELL_JSON_SRC="$OMARCHY_DEBIAN_ROOT/overlay/quattro/config/omarchy/shell.json"
SHELL_JSON_DST="$TARGET_HOME/.config/omarchy/shell.json"
if [[ $DRY_RUN == "1" ]]; then
  log "dry-run: deploy $SHELL_JSON_SRC -> $SHELL_JSON_DST"
else
  omd_install_dir "$TARGET_HOME/.local/state/omarchy/toggles"
  if [[ -f $SHELL_JSON_DST ]] && cmp -s "$SHELL_JSON_SRC" "$SHELL_JSON_DST"; then
    : # already ours — idempotent no-op
  else
    if [[ -f $SHELL_JSON_DST && ! -f $SHELL_JSON_DST.pre-omarchy ]]; then
      cp -a "$SHELL_JSON_DST" "$SHELL_JSON_DST.pre-omarchy"
      omd_chown_path "$SHELL_JSON_DST.pre-omarchy"
      log "backed up $SHELL_JSON_DST -> $SHELL_JSON_DST.pre-omarchy"
    fi
    omd_install 644 "$SHELL_JSON_SRC" "$SHELL_JSON_DST"
    log "deployed quattro bar layout -> $SHELL_JSON_DST"
  fi
fi

log "quattro profile complete — log into the Hyprland session to verify the bar"
log "(static checks pass; graphical rendering needs a real Wayland session)"
