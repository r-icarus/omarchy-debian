# Quattro upgrade: 7e7a5600 → 84cfb939

The `quattro` profile now pins upstream commit
`84cfb93959f4fe0bbb71de71593b36647d2ba78d` (88 commits after the previous pin).
Quickshell's fallback runtime remains `0.3.2ppa1`; the candidate loads on
PikaOS's installed Quickshell 0.3.2. The separate main-upstream pin is unchanged.

## Changes retained and adapted

- Upstream floating-workspace dock/AppGrid, minimizing, wheel workspace switching,
  localization, tray improvements, battery calculations and binding-loop fixes.
- Full upstream bar; APT update detection remains cached-only and polls every
  minute. The tooltip retains upstream translation plus an explicit cached-APT
  suffix. No automatic apt refresh, sudo or Git fetch runs from the widget.
- Debian dock defaults: Nautilus, Chromium and Kitty. Uninstalled pins are hidden
  upstream; existing pins (including an empty list) are never replaced.
- Compatibility patch now changes only actual QML reserved identifiers, the
  background signal-handler syntax, the update widget, Debian locale routing
  and canonical configuration loading before plugin registration.
  Protocol string keys such as the notification `transient` hint remain intact.
- Language selection elevates only `/usr/bin/localedef` with validated glibc
  locale arguments, using sudo in a terminal or polkit otherwise. Install
  `locales` for the system sources. No `/usr/share/omarchy` registry, passwordless
  rule, system-wide LANG change or root execution of a checkout helper is needed.
  `localedef --no-archive` creates individual compiled locales without modifying
  the system locale archive.
  Existing applications retain their language; the next applications/login use
  the selected LANG. Locale generation needs explicit authentication.
- APT package adapters, rootless Podman/Docker DB and tuned compatibility remain.
  The development-removal wrapper delegates non-PHP removal to upstream, including
  its Rust cleanup fix. The Arch orphan-package helper is intentionally replaced
  by the existing APT adapter.

## Installer upgrade behavior

```bash
./install.sh --profile quattro --phases 31-quattro-shell.sh
```

A new revision is fetched into a fresh sibling checkout, patched and verified
before the existing checkout is renamed to `omarchy-quattro.pre-upgrade.*`.
Local modifications and untracked files in the previous checkout survive there.
There is no hard reset or Git checkout over a patched working tree. Repeating
installation at the same pin checks the patch in reverse; an incompatible patch
state is fatal rather than mistaken for "already applied".

Canonical configuration is read synchronously before registering plugins. A live
startup caught Elsewhen seeding default cities over saved zones; the original
cities were restored and subsequent startup checks preserved them. The race was
intermittent in scratch runs, so repeated live checks remain important.

Existing managed theme state and wallpaper are preserved. Existing `shell.json`
is preserved, except that an absent `dock` key receives Debian defaults. That
one-time change first saves `shell.json.pre-quattro-dock`. Custom plugins, clock
zones, layouts, future settings and explicit empty dock pins survive.

This protects checkout replacement from fetch/patch failures, not from every
possible later package-installation failure. Snapshot config/state before a live
upgrade. Do not run upstream migrations or `omarchy-update` to advance this pin.

## Upstream migration review

No upstream migration was executed automatically:

- Kimi preinstall is outside this fork's packaged-desktop AI scope.
- Web-app window-class backfill is optional for existing custom web launchers;
  the Debian default dock does not depend on it.
- Limine timeout/quiet changes must not touch PikaOS's boot configuration.
- Browser MIME routing and default-check suppression change user browser
  preferences/system policies and are deferred rather than silently applied.

## Validation

```bash
bash test/validate.sh
bash test/quattro.sh
OMARCHY_QUATTRO_TEST_TREE=/path/to/pinned/source bash test/quattro-compat.sh
```

The real-source test extracts only patch targets from the pinned commit into a
scratch directory and tests clean application and reversal. The upgrade tests
cover dirty/untracked-file preservation, patch mismatch refusal, idempotence,
config preservation and restoration of the saved previous checkout. Language
helper tests mock authentication; they do not generate a system locale.

Focused upstream tests passed locally for dock, localization, bar/widget
contracts, audio/source availability, power/profiles and notifications. Upstream's
runtime smoke test passed in a separate nested Hyprland compositor on PikaOS:
loading, IPC, default bar geometry, panel opens/closes, plugin reloads, persistent
services and plugin API boundaries. These tests do not prove a fresh install,
locale-generation authentication, physical power/network changes, or lock/unlock.

PikaOS's standalone `Hyprland --verify-config` segfaults on both the old and new
full Lua configurations, so it is not counted as a passing validation check.
The first invocation without a session signature also reported a startup-cursor
Lua environment error. Nested runtime testing is used instead.

## Live acceptance on PikaOS 4 (2026-10-14)

- Running the new pin with Quickshell 0.3.2; shell IPC responds.
- Lua defaults reloaded without a compositor restart; `hyprctl configerrors`
  returned no errors. User Hyprland files and theme files retained their original
  checksums, wallpaper symlink stayed unchanged, and display geometry/2× scaling
  matched the pre-upgrade snapshot.
- Eight panel open/close calls passed (clock, elsewhen, weather, Bluetooth,
  network, audio, monitor, power). Root menu and dock AppGrid IPC calls passed.
- Original custom clock cities survived the startup fix and a second live shell
  restart. All other existing shell settings were retained; only dock defaults
  were added.
- `libxkbcommon-tools` installed from PikaOS; `xkbcli list --load-exotic` succeeds.
  Hyprland's device IPC lists no keyboards on this session both before and after
  the upgrade, so actual physical layout switching is not counted as verified.
  The keyboard bar widget has no independent panel IPC target. Upstream's
  keyboard-layout, lazy-panel and input-device tests pass; additional
  input-indicator and Hyprland-keyboard tests are blocked by test-only
  `/usr/bin/python` and `lua` prerequisites absent on this host. Runtime input
  helpers already use Python 3; no system Python alias was installed.
- `ttfx 0.5.0` and `socat` are installed. A bounded PTY animation emitted frames,
  and the regular idle screensaver also launched. Optional `chafa` is absent.
- Existing NetworkManager profile-access and PikaOS update-tray D-Bus/icon
  warnings remain. Quickshell 0.3.2 reports the upstream load-patch pragma as
  unrecognized, and initial translation bindings can briefly warn before catalog
  loading. These are not reported as clean startup logs.
- No lock/unlock test, physical power/network mutation, locale-generation
  authentication or fresh-machine install was performed.

An explicit nested-session startup-preservation check is available as
`test/quattro-runtime.sh`. It requires `OMARCHY_QUATTRO_RUNTIME_TEST=1` and
`OMARCHY_QUATTRO_TEST_TREE`; do not run it on the primary desktop. Upstream's
runtime smoke test also passed with the final configuration-loading patch.

## Live upgrade rollback

Before stopping the live shell, save the checkout (including `.git` and local
changes), `~/.config/omarchy`, `~/.config/hypr` and
`~/.local/state/omarchy/current`. Do not stop the shell while its lock reports
locked, requested, pending or sessionLocked, or when its lock status is unknown.

Stop the supervising launcher before stopping its shell, so it cannot race a
checkout replacement. Restore the saved checkout and, if needed, the saved
Omarchy config/theme state, then launch `omarchy-quattro-launch` from Hyprland.
Keep the replaced new checkout rather than deleting it. No compositor restart
or runtime-package downgrade is necessary. If Lua defaults were reloaded,
reload them again after restoring the old checkout.

`omarchy-quattro-rollback` is the **profile uninstall** helper, not an upgrade
rollback: it removes the checkout and may restore pre-profile configuration.
Do not use it to switch between these two upstream revisions.
