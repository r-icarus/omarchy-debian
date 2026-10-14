#!/bin/bash
# Read-only adapter tests: never change the host power profile or APT metadata.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/bin"
cat >"$TMP/bin/apt" <<'MOCK'
#!/bin/bash
printf '%s\n' 'Listing...' 'demo/stable 2 amd64 [upgradable from: 1]'
MOCK
chmod +x "$TMP/bin/apt"
output=$(PATH="$TMP/bin:$PATH" "$ROOT/overlay/bin/omarchy-update-available")
[[ $output == 'demo/stable 2 amd64 [upgradable from: 1]' ]]
cat >"$TMP/bin/apt" <<'MOCK'
#!/bin/bash
printf 'Listing...\n'
MOCK
if PATH="$TMP/bin:$PATH" "$ROOT/overlay/bin/omarchy-update-available" >/dev/null; then
  echo 'Expected no-updates exit status 1' >&2; exit 1
else
  [[ $? == 1 ]]
fi
# A native CLI is deliberately preferred if installed; test the D-Bus fallback
# on systems like PikaOS which lack that executable.
if [[ ! -x /usr/bin/powerprofilesctl ]]; then
  cat >"$TMP/bin/busctl" <<'MOCK'
#!/bin/bash
case ${!#} in
  ActiveProfile) echo '{"data":"balanced"}' ;;
  Profiles) echo '{"data":[{"Profile":{"data":"balanced"}},{"Profile":{"data":"power-saver"}}]}' ;;
  *) exit 2 ;;
esac
MOCK
  chmod +x "$TMP/bin/busctl"
  output=$(PATH="$TMP/bin:$PATH" "$ROOT/overlay/bin/powerprofilesctl" list)
  [[ $output == $'* balanced:\n  power-saver:' ]]
fi
# Cached package checks should converge promptly after external apt upgrades.
grep -Fq '+    interval: 60000' "$ROOT/patches/quattro-qml-compat.patch"
grep -Fq '+    tooltipText: "Pending system updates (cached APT metadata)"' "$ROOT/patches/quattro-qml-compat.patch"
echo 'bar helper tests passed'
