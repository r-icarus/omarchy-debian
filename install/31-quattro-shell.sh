#!/bin/bash
# Optional profile: native Omarchy Quattro (Quickshell) top bar.
#
# Enabled with:  ./install.sh --profile quattro
#
# What this phase does:
#   1. Clones omacom/omarchy branch `quattro` read-only at a pinned commit to
#      $OMARCHY_QUATTRO_PATH (separate from the default/master checkout; the
#      upstream tree is never modified).
#   2. Installs the Quickshell runtime: the distro package when apt carries
#      one (Debian forky/sid/trixie-backports), else a pinned upstream .deb
#      pair (quickshell + libcpptrace, sha256-verified) from the DankLinux
#      PPA *pool* — no third-party repository is ever added to the system.
#      On PikaOS this means its repositories, kernel, Mesa/NVIDIA stack,
#      bootloader, and updater stay untouched.
#   3. Deploys a curated ~/.config/omarchy/shell.json (backup-first) that
#      limits the bar to widgets whose dependencies are satisfied by the
#      quickshell binary itself (workspaces, active window, clock, tray,
#      indicators via the clock/menu, audio via PipeWire).
#
# The Hyprland wiring (exec-once launch, bar toggle, menu binding) lives in
# overlay/config/hypr/hyprland.conf + overlay/bin/omarchy-quattro-* and is
# deployed by 50-dotfiles; it degrades to waybar when quickshell is absent.
# Rollback: overlay/bin/omarchy-quattro-rollback (see docs/QUATTRO-QUICKSHELL.md).

set -euo pipefail
source "$OMARCHY_DEBIAN_ROOT/lib/log.sh"
source "$OMARCHY_DEBIAN_ROOT/lib/detect.sh"
source "$OMARCHY_DEBIAN_ROOT/lib/apt.sh"

if [[ ${OMARCHY_DEBIAN_PROFILE:-} != "quattro" ]]; then
  log "profile 'quattro' not selected — skipping native Quickshell bar (use ./install.sh --profile quattro)"
  exit 0
fi

detect_distro

# Pinned upstream ref (omacom/omarchy, branch `quattro`). Bump to track newer.
: "${OMARCHY_QUATTRO_REPO:=https://github.com/omacom/omarchy.git}"
: "${OMARCHY_QUATTRO_REF:=7e7a5600a3c989eb8658dd12409fa7e0479078bb}"
: "${OMARCHY_QUATTRO_PATH:=$HOME/.local/share/omarchy-quattro}"
export OMARCHY_QUATTRO_PATH

DRY_RUN=${OMARCHY_DEBIAN_DRY_RUN:-0}

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
    mkdir -p "$(dirname "$OMARCHY_QUATTRO_PATH")"
    git clone --quiet --branch quattro "$OMARCHY_QUATTRO_REPO" "$OMARCHY_QUATTRO_PATH"
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

# --- 2. Quickshell runtime ------------------------------------------------------
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

# --- 3. curated bar config (backup-first, idempotent) --------------------------
SHELL_JSON_SRC="$OMARCHY_DEBIAN_ROOT/overlay/quattro/config/omarchy/shell.json"
SHELL_JSON_DST="$HOME/.config/omarchy/shell.json"
if [[ $DRY_RUN == "1" ]]; then
  log "dry-run: deploy $SHELL_JSON_SRC -> $SHELL_JSON_DST"
else
  mkdir -p "$HOME/.config/omarchy" "$HOME/.local/state/omarchy/toggles"
  if [[ -f $SHELL_JSON_DST ]] && cmp -s "$SHELL_JSON_SRC" "$SHELL_JSON_DST"; then
    : # already ours — idempotent no-op
  else
    if [[ -f $SHELL_JSON_DST && ! -f $SHELL_JSON_DST.pre-omarchy ]]; then
      cp -a "$SHELL_JSON_DST" "$SHELL_JSON_DST.pre-omarchy"
      log "backed up $SHELL_JSON_DST -> $SHELL_JSON_DST.pre-omarchy"
    fi
    install -Dm644 "$SHELL_JSON_SRC" "$SHELL_JSON_DST"
    log "deployed quattro bar layout -> $SHELL_JSON_DST"
  fi
fi

log "quattro profile complete — log into the Hyprland session to verify the bar"
log "(static checks pass; graphical rendering needs a real Wayland session)"
