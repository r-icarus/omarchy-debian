#!/bin/bash
# No GUI, network, apt, or live HOME writes.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home/.local/bin" "$TMP/upstream/bin"
export HOME="$TMP/home" OMARCHY_PATH="$TMP/upstream"
printf 'upstream logo\n' >"$OMARCHY_PATH/logo.txt"
printf '#!/bin/bash\nprintf "animation invoked\\n"\n' >"$OMARCHY_PATH/bin/omarchy-screensaver"
printf '#!/bin/bash\nexit 0\n' >"$HOME/.local/bin/ttfx"
chmod +x "$HOME/.local/bin/ttfx" "$OMARCHY_PATH/bin/omarchy-screensaver"
output=$("$ROOT/overlay/bin/omarchy-screensaver")
[[ $output == 'animation invoked' ]]
cmp "$OMARCHY_PATH/logo.txt" "$HOME/.config/omarchy/branding/screensaver.txt"
printf 'custom logo\n' >"$HOME/.config/omarchy/branding/screensaver.txt"
"$ROOT/overlay/bin/omarchy-screensaver" >/dev/null
grep -Fxq 'custom logo' "$HOME/.config/omarchy/branding/screensaver.txt"
test -x "$ROOT/overlay/bin/omarchy-install-screensaver"
grep -Fq 'TTFX_REV=112ebb310b848d8f1251a5c2919a9cd5a5c78e18' "$ROOT/overlay/bin/omarchy-install-screensaver"
grep -Fq -- '--locked --root' "$ROOT/overlay/bin/omarchy-install-screensaver"
echo 'screensaver prerequisite tests passed'
