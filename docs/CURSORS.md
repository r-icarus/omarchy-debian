# Upstream-style Quattro cursor

Quattro does not bundle a custom normal pointer. Its default/system family is
**Adwaita**, size **24**. Arch packages the cursor component separately as
[`adwaita-cursors`](https://archlinux.org/packages/extra/any/adwaita-cursors/);
Debian/PikaOS include the assets in `adwaita-icon-theme`.

The fork maps `adwaita-cursors` to that APT package. Session defaults explicitly
prefer Adwaita when `left_ptr`, `pointer`, `text` and `wait` are present and
nonempty. Otherwise the existing Bibata-Modern-Classic fallback remains.
Explicit user XCursor/Hyprcursor choices and sizes are preserved.

## PikaOS safety

The earlier Bibata default was a workaround for null cursor surfaces during
startup. Do not revert to an unpinned `default` alias or undo the complete
`omarchy-startup` cursor repair. The installer still completes the startup
cursor theme from a full system theme, now preferring Adwaita before Bibata.

Adwaita is an XCursor theme; its lack of a native Hyprcursor manifest is normal.
Hyprland supports the XCursor path. Upstream also has reports of startup cursor
rendering regressions; see [Omarchy issue #14932](https://github.com/omacom/omarchy/issues/14932).
A live cursor switch does not prove a cold-login graphics fix on every GPU.

## Explicit user preference

For persistence before the compositor starts, use a user override such as
`~/.config/uwsm/env.d/20-omarchy-cursor`:

```sh
export XCURSOR_THEME=Adwaita
export HYPRCURSOR_THEME=Adwaita
export XCURSOR_SIZE=24
export HYPRCURSOR_SIZE=24
```

For the current session:

```sh
gsettings set org.gnome.desktop.interface cursor-theme Adwaita
gsettings set org.gnome.desktop.interface cursor-size 24
hyprctl setcursor Adwaita 24
```

Update the systemd/D-Bus activation environment too when changing an existing
session, so newly launched applications use the same cursor. Applications that
cache cursor settings may need reopening. No root icon aliases need replacing.

## Verification on PikaOS 4

`adwaita-icon-theme 51.0-1` was already installed. All 63 supplied cursor names
resolved to valid XCursor files, including the standard pointer, resize, text
and wait shapes. The pointer includes a native size 24 frame. GTK and session
settings were switched to Adwaita/24; Hyprland accepted `setcursor` and reported
no config errors. The complete startup-cursor workaround was left intact.

Run `bash test/cursor.sh` (also included in `test/quattro.sh`) for isolated
selection/fallback/user-preference tests. These tests do not change GTK or the
compositor.
