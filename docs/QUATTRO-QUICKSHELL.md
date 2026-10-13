# Quattro Quickshell bar (native Omarchy shell) — PikaOS / Debian / Ubuntu

This profile deploys the **real Omarchy Quattro top bar** (the upstream
Quickshell implementation at `omacom/omarchy` branch `quattro`), not a Waybar
imitation. It is opt-in:

```bash
./install.sh --profile quattro            # full install with the native bar
./install.sh --profile quattro --dry-run  # resolve only, change nothing
./install.sh --profile quattro --user ricardo --theme tokyo-night
OMARCHY_TARGET_USER=ricardo OMARCHY_THEME=tokyo-night ./install.sh --profile quattro
./install.sh --phases 31-quattro-shell.sh # just the quattro phase
```

### Target user + initial theme

| Input | CLI | Environment | Default |
|---|---|---|---|
| Target account | `--user ricardo` | `OMARCHY_TARGET_USER=ricardo` | see below |
| Initial theme | `--theme tokyo-night` | `OMARCHY_THEME=tokyo-night` | `tokyo-night` |

- **Precedence: CLI > environment > interactive prompt > safe unattended
  default.** When the installer runs on a TTY and a value is omitted, it asks
  ("Which existing Linux user should receive the Omarchy configuration?",
  "Which initial Quattro theme?"). Unattended, the target user defaults to a
  valid non-root `SUDO_USER` when running as root, else the invoking non-root
  user; the theme defaults to `tokyo-night`.
- The target home is resolved with `getent passwd` — custom home paths work,
  and nothing is ever built as `/home/$USER`. Nonexistent accounts and `root`
  are rejected with a nonzero exit.
- The selected theme is validated against the **pinned quattro checkout**
  (`OMARCHY_QUATTRO_REF`): a theme must exist as a directory with a
  `colors.toml` under `themes/` in that exact commit, or the install aborts
  before writing any state.
- Theme initialization stages the Debian-safe subset of the genuine theme
  into `~/.local/state/omarchy/current/` (target-owned), mirroring upstream
  `omarchy-theme-set`: `theme/colors.toml`, `theme/shell.toml` when the theme
  ships one, `theme/backgrounds/`, `theme.name`, and the relative
  `background` symlink pointing at the theme's first image. Upstream hooks
  that assume Arch or mutate unrelated apps/packages (template retints,
  `omarchy-theme-set-*` app hooks, shell IPC) are **not** run.
- All deployment is backup-first and idempotent: pre-existing
  `~/.local/state/omarchy/current` is preserved once as `current.pre-omarchy`
  before any change, and re-running only refreshes what differs. When the
  installer runs through sudo/root, every deployed file/directory carries the
  target user's ownership.

## What it does

1. **PikaOS-safe by construction.** PikaOS is detected via `is_pikaos()`
   (os-release `ID=pikaos`, `ID_LIKE=…pika`, or `/etc/pika-info`). Nothing in
   this project edits PikaOS repositories, kernel, Mesa/NVIDIA stack,
   bootloader, or its updater. The only system-level change is `apt-get
   install ./pinned.deb` of two leaf packages (quickshell + libcpptrace);
   all other dependencies resolve from the distro's existing repositories.
   No pacman/yay anywhere; no third-party apt *repository* is added — the
   .debs come from direct, sha256-pinned pool file URLs.
2. **Pinned quattro checkout, read-only.** Clones `omacom/omarchy` branch
   `quattro` at a pinned commit to `~/.local/share/omarchy-quattro`
   (separate from the default-branch checkout; never modified).
   * Pin: `7e7a5600a3c989eb8658dd12409fa7e0479078bb` (`install/31-quattro-shell.sh`).
3. **Initial theme (Debian-safe subset).** The selected theme (default
   `tokyo-night`, see "Target user + initial theme" above) is validated
   against the pinned checkout and staged into the target user's
   `~/.local/state/omarchy/current/` — `theme/colors.toml`, `shell.toml`
   when shipped, `theme/backgrounds/`, `theme.name`, and the `background`
   symlink — mirroring upstream `omarchy-theme-set` without its Arch/app
   hooks. Backup-first, idempotent, target-owned.
4. **Quickshell runtime** (`install/31-quattro-shell.sh`):
   - distro `quickshell` package when apt carries one (Debian forky/sid,
     trixie-backports), else
   - pinned upstream .debs `quickshell 0.3.2ppa1` + `libcpptrace 1.0.4ppa8`
     (DankLinux PPA *pool direct URLs*, sha256-verified per arch, amd64+arm64),
     installed through `apt-get install ./file.deb` so Qt/Wayland deps resolve
     from the system's own repos. If the base Qt is older than the build
     needs, apt refuses and the phase reports it honestly and keeps waybar.
   - plus the QML runtime modules the bar imports (workerscript, layouts,
     controls, window, templates) from the distro repo.
5. **Curated bar config** deployed to `~/.config/omarchy/shell.json`
   (existing file backed up to `.pre-omarchy` first): workspaces, active
   window, clock, tray — the widgets whose dependencies are satisfied by the
   quickshell binary itself. Audio included (Quickshell.Services.Pipewire is
   built in). Network/battery/bluetooth widgets are NOT enabled by default:
   they need NetworkManager/UPower/BlueZ present and are left for explicit
   enabling (see below).
6. **Session wiring** (`overlay/config/hypr/hyprland.conf`):
   `exec-once` runs `omarchy-quattro-launch` when present, else waybar.
   The launcher mirrors upstream `omarchy-launch-shell` (journal logging via
   systemd-cat, `QS_DISABLE_FILE_WATCHER=1`, supervised relaunch with a
   compositor-alive check).
7. **Hyprland bindings** (already in the classic-syntax config): terminal,
   launcher (fuzzel / omarchy-menu), browser, close, fullscreen, float,
   workspaces 1-10 + move, screenshots, lock, audio, brightness, plus
   `SUPER+SHIFT+SPACE` bar toggle (upstream `bar-off` flag protocol).

## What is verified where

| Check | Where | Status |
|---|---|---|
| Phase logic, gating, idempotence, pins | `test/quattro.sh` (hermetic) | passing (CI) |
| Bar config contract (only known widget ids) | `test/quattro.sh` | passing (CI) |
| PikaOS detection (ID, marker, negative) | `test/quattro.sh` | passing (CI) |
| Binding presence in hyprland.conf | `test/quattro.sh` | passing (CI) |
| Rollback + toggle helper behavior (fake HOME) | `test/quattro.sh` | passing (CI) |
| Pinned .deb URLs + sha256 | captured 2026-10-13; phase verifies at install time | verified reachable |
| quattro checkout pinned ref exists | fetched 2026-10-13 | verified |
| **Bar actually rendering on PikaOS** | needs a real PikaOS graphical session | **not verified here** |

This host is not PikaOS and has no Wayland session for the shell: everything
above the "rendering" line is static/unit validation only. First graphical
check on target: log into the Omarchy (Debian) Hyprland session and confirm
the bar renders (workspaces, active window, clock, tray), then
`journalctl --user -t omarchy-quattro` if it does not.

## Rollback

```bash
omarchy-quattro-rollback   # restores theme state (current.pre-omarchy backup,
                           # or removes it when none existed), restores
                           # shell.json, removes the quattro clone, restores
                           # the pre-omarchy hyprland.conf backup if present
sudo apt-get remove quickshell libcpptrace   # optional: drop the runtime
```

## Unsupported / not yet done

- **Lua Hyprland config**: upstream quattro configures Hyprland through its
  Lua API; this repo ships the classic-syntax config (works on every packaged
  Hyprland). Bindings listed above are ported, not the full upstream set.
- **Upstream `omarchy-*` CLI surface** (omarchy-menu, omarchy bar …): those
  helpers exist only inside the quattro checkout's `bin/`; they are on PATH
  in the session (via the uwsm env) but untested on Debian/PikaOS. The bar
  toggle uses the same flag protocol via `omarchy-quattro-bar-toggle`.
- **Network/battery/bluetooth/weather widgets**: disabled pending dependency
  proof on target (NetworkManager, UPower, BlueZ). Enable by editing
  `~/.config/omarchy/shell.json` (ids: `omarchy.network`, `omarchy.power`,
  `omarchy.bluetooth`, `omarchy.weather`).
- **quickshell on Debian 13/12 or Ubuntu 24.04**: the pinned 0.3.2 build
  needs Qt ≥ 6.10.2; older bases must build from source.

## Build from source (fallback)

```bash
sudo apt-get install -y git cmake ninja-build pkg-config \
  qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-declarative-private-dev \
  qt6-tools-dev qt6-svg-dev qt6-wayland qt6-multimedia-dev \
  libpipewire-0.3-dev libpolkit-agent-1-dev libpolkit-gobject-1-dev \
  libpam0g-dev libjemalloc-dev wayland-protocols libxcb1-dev
git clone https://github.com/outfoxxed/quickshell && cd quickshell
cmake -B build -GNinja -DCRASH_REPORTER=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build build && sudo cmake --install build
```

## PikaOS field notes (2026-10-13, first graphical bring-up)

Verified end-to-end on PikaOS 4 (nest, Hyprland 0.56.2 pika build, quickshell
0.3.2): session start via uwsm, quattro bar with full default widget set,
wallpaper, 2x HiDPI scale, natural scrolling. Issues hit and their fixes
(all now encoded in the installer/overlay):

1. **PikaOS deletes the system hyprland.desktop** (`hyprland` postinst removes
   `/usr/share/wayland-sessions/hyprland.desktop` when `pika-hyprland` exists),
   so `uwsm start -e -D Hyprland hyprland.desktop` fails and the session
   bounces back to the greeter. 50-dotfiles now deploys a user-level
   `~/.local/share/wayland-sessions/hyprland.desktop`.
2. **quickshell 0.3.2's QML grammar reserves `native` and `transient`**,
   which the pinned quattro QML uses as identifiers — several shell services
   (background, notifications) failed to load. `patches/quattro-qml-compat.patch`
   renames them; 31-quattro-shell.sh applies it after the pinned checkout.
3. **`QtQuick.Effects` QML module is not a hard dependency** — needed for
   tray/background/lock/image-picker: `qml6-module-qtquick-effects`.
4. **PikaOS Hyprland segfaults (SEGV in CCursorBuffer)** when a cursor shape
   resolves to a null surface: the skeletal `omarchy-startup` blank-cursor
   theme plus PikaOS's self-inheriting `default` theme alias trigger it.
   31-quattro-shell.sh completes the startup theme from Bibata and the uwsm
   env pins a complete cursor theme.
5. **Hyprland 0.56 config syntax**: the overlay's classic-syntax
   `hyprland.conf` needed updates (shadow block, `windowrule` field=value
   selectors; `dwindle:pseudotile`/`misc:vfr` removed). On Hyprland >= 0.50
   the upstream quattro **Lua** config is preferred (copy the checkout's
   `config/hypr/*.lua` to `~/.config/hypr/`; it silences the legacy-conf
   deprecation advisory). Runtime `hyprctl keyword monitor`/`output scale`
   is a no-op on the pika build — set scale in `monitors.lua` and restart.
6. **The quattro shell reads `~/.config/omarchy/shell.json`** — the curated
   layout omits network/power/bluetooth. For the full default widget set,
   copy the checkout's `config/omarchy/shell.json` instead.
7. **Packages needed on PikaOS that the phases don't install**: kitty +
   xdg-terminal-exec (TERMINAL target), grim/slurp/nautilus (keybinds),
   inotify-tools (plugin hot-reload watcher).
