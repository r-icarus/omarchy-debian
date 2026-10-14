# omarchy-debian

A practical Debian/Ubuntu adaptation of **[omacom/omarchy](https://github.com/omacom/omarchy)**
— DHH's opinionated Arch/Hyprland desktop environment.

This repository contains **no upstream code**. It is an install layer that:

1. Detects your Debian/Ubuntu release and support level.
2. Installs Omarchy's dependency set via **apt**, using a maintained
   Arch→Debian package map (`packages/*.map`).
3. Installs AUR-only tools through their official channels (mise apt repo,
   upstream `.deb`/tarball releases, Charm-style binaries) where an automated
   path exists.
4. Clones upstream `omacom/omarchy` **read-only, at a pinned commit**, to
   `~/.local/share/omarchy` and layers Debian-specific fixes over it
   (`overlay/`) — upstream is never modified.
5. Deploys dotfiles, a classic-syntax Hyprland config, session entries, and
   enables the services upstream enables.

Optional profile: `./install.sh --profile quattro` installs the **native
Omarchy Quattro Quickshell top bar** (pinned upstream quattro checkout +
Quickshell runtime) — see [docs/QUATTRO-QUICKSHELL.md](docs/QUATTRO-QUICKSHELL.md).
PikaOS is supported without touching its kernel/driver/updater stack.

Upstream reference commit: `9c5482c` (bump `OMARCHY_UPSTREAM_REF` in
`install/30-upstream.sh` to track newer).

## Supported releases

| Release | Level | Hyprland |
|---|---|---|
| Debian 14+ (forky/sid) | Supported | apt main |
| Debian 13 (trixie) | Supported | `trixie-backports` (auto-enabled by installer) |
| Debian 12 (bookworm) | Partial | not packaged — source build or sway fallback |
| Ubuntu 24.10 / 25.x / 26.x | Supported | apt (universe) |
| Ubuntu 24.04 LTS | Partial | not packaged — source build or sway fallback |
| Debian derivatives (Mint, Pop!_OS…) | Partial | best effort |

`unsupported`/`partial` only blocks the compositor; the package + dotfiles
phases still run.

## Prerequisites

- A working Debian/Ubuntu install with `sudo`, `apt`, `git`, `curl` (the
  preflight phase installs what's missing).
- For the full desktop: a real (non-container) system. Containers get the
  packages + dotfiles only.
- ~2 GB free disk, network access to github.com and the apt mirrors.
- Debian proper: `contrib`, `non-free`, and `non-free-firmware` components
  enabled for firmware/NVIDIA (preflight warns if missing).

## Usage

```bash
git clone https://github.com/CommunityPokeOrg/omarchy-debian.git
cd omarchy-debian
./install.sh            # interactive full install
./install.sh --dry-run  # resolve everything, change nothing
./install.sh --no-desktop   # packages + dotfiles only
./install.sh --compositor sway
./install.sh --phases 10-apt-deps.sh,50-dotfiles.sh   # rerun selected phases
./install.sh --profile quattro --user ricardo --theme tokyo-night
OMARCHY_TARGET_USER=ricardo OMARCHY_THEME=tokyo-night ./install.sh --profile quattro
```

### Target user + initial theme (quattro profile)

- `--user <name>` / `OMARCHY_TARGET_USER` — which existing, non-root Linux
  account receives the configuration. The target home is resolved with
  `getent passwd` (custom home paths work; nothing assumes `/home/<name>`).
  Nonexistent accounts and `root` are rejected.
- `--theme <name>` / `OMARCHY_THEME` — the initial Quattro theme, validated
  against the pinned quattro checkout (`OMARCHY_QUATTRO_REF`). Default:
  `tokyo-night`.
- Precedence: **CLI > environment > interactive prompt > safe unattended
  default**. Interactively, omitted values are asked ("Which existing Linux
  user should receive the Omarchy configuration?", "Which initial Quattro
  theme?"). Unattended, the target defaults to a valid non-root `SUDO_USER`
  when the installer runs as root, else the invoking user; the theme defaults
  to `tokyo-night`.
- All user configuration/state is deployed with target ownership even when
  the installer runs through `sudo`; `omarchy-quattro-rollback` restores
  pre-existing theme state (`~/.local/state/omarchy/current`) and configs.

### Safety / idempotence

- Re-running installs only missing packages; overlay files are only written
  when they differ, and a divergent existing file is preserved as
  `<file>.pre-omarchy` once.
- Every phase logs to `~/.local/state/omarchy-debian/install.log`; a failing
  phase is reported at the end and can be retried alone via `--phases`.
- Pass `--strict` to abort on the first failed phase.
- Nothing touches `/etc/apt/sources.list*` except the mise repo entry;
  `--dry-run` performs zero writes.

## Package mapping

`packages/base.map` covers all 153 upstream `omarchy-base.packages` entries;
`packages/extra.map` covers `omarchy-other.packages`. Strategies: `apt`,
`apt-any` (first available candidate), `apt-hw` (install only when matching
hardware is detected), `external` (official repo/.deb/tarball installer in
`install/20-external.sh`), `manual`, `skip`.

The full rendered table: **[docs/MAPPING.md](docs/MAPPING.md)** (regenerate with
`test/gen-mapping-doc.sh`). Highlights:

| Arch (upstream) | Debian/Ubuntu | How |
|---|---|---|
| hyprland, uwsm, xdg-desktop-portal-hyprland | same names | apt (13+/24.10+) |
| fd, bat, neovim | fd-find→`fdfind`, bat→`batcat`, neovim→`nvim` | apt + `~/.local/bin` symlinks |
| eza, fastfetch, starship | same names | apt where present, else GitHub .deb/install script |
| mise-bin | mise | official mise apt repo |
| gum, lazygit, lazydocker | — | GitHub release .deb/tarball → `~/.local/bin` |
| obsidian | obsidian | official .deb |
| ttf-jetbrains-mono-nerd-basic | — | Nerd Fonts release → `~/.local/share/fonts` |
| yay, pacman-*, expac, kernel-modules-hook | — | skip (Arch-only) |
| quickshell, aether, herdr, omacalc/omacut/omawrite, tensaku… | — | manual/skip, see docs |
| limine, mkinitcpio hooks, linux-omarchy | — | skip (GRUB/systemd-boot + stock kernel) |

## What works / what doesn't

See **[docs/LIMITATIONS.md](docs/LIMITATIONS.md)** — short version: the
upstream Quickshell desktop and Lua Hyprland config don't run on distro
packages, so the overlay provides **Hyprland (classic conf) or Sway + waybar +
fuzzel + mako** as the session stack. Boot-stack items (limine, mkinitcpio,
snapper sync, plymouth theme) are not ported.

Things a human still has to do: **[docs/MANUAL-STEPS.md](docs/MANUAL-STEPS.md)**.

## Package helper and installer menus

The Debian `omarchy-pkg-add` resolves upstream package names through
`packages/*.map`, falls back to exact apt package names, skips installed
packages, and verifies the result. It also accepts local `.deb` files so apt
can resolve their dependencies. It fails clearly for unavailable or
manual-only names instead of passing an AUR name to apt.

The AI menu uses official Linux package paths for ChatGPT, Claude Desktop,
Grok Bot, LM Studio, and T3 Code. Claude uses Anthropic's apt repository;
ChatGPT, Grok Bot, and LM Studio use vendor `.deb` downloads; T3 Code's latest
GitHub `.deb` is checked against its published SHA-256 digest. CLI/script-based
AI entries are hidden for now; Perplexity's separate Portable Computer product
is also hidden because it is not a drop-in for the upstream menu entry. The
Development → PHP → Symfony action adds Symfony's official Cloudsmith APT
source only when selected, then installs the CLI through apt. The PHP removal
path maps legacy package names to Debian packages and skips packages not installed.

## Validation

See **[docs/TESTING.md](docs/TESTING.md)**: `test/validate.sh` (syntax + map
integrity + upstream coverage), `--dry-run`, and a container smoke test.

## Layout

```
install.sh            entry point (phase runner)
lib/                  detect / apt / map / log helpers
packages/*.map        Arch→Debian TSV package maps
install/NN-*.sh       ordered install phases
overlay/bin/          apt-backed omarchy-pkg-*/omarchy-update* commands
overlay/config/       hyprland.conf (classic), sway, waybar
overlay/uwsm|wayland-sessions|environment.d|sddm.conf.d/
docs/                 MAPPING / LIMITATIONS / MANUAL-STEPS / TESTING
test/validate.sh      offline validation
```

## License

MIT — same as upstream. Upstream `omacom/omarchy` © its authors; fetched
read-only at install time under its own MIT license.
