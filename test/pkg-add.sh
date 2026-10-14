#!/bin/bash
# Isolated tests for the Debian omarchy-pkg-add resolver.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/debian/packages" "$TMP/demo/DEBIAN"
: >"$TMP/installed"
printf 'hardware-deb\n' >"$TMP/installed"
cat >"$TMP/debian/packages/base.map" <<'MAP'
upstream-one	apt	debian-one
upstream-any	apt-any	missing-one|debian-two
hardware-only	apt-hw	hardware-deb
external-only	external	tool
MAP
: >"$TMP/debian/packages/extra.map"

cat >"$TMP/bin/apt-cache" <<'MOCK'
#!/bin/bash
case ${2:-} in
  debian-one | debian-two | direct-name) printf '  Candidate: 1.0\n' ;;
  *) printf '  Candidate: (none)\n' ;;
esac
MOCK
cat >"$TMP/bin/dpkg-query" <<'MOCK'
#!/bin/bash
pkg=${!#}
grep -Fxq "$pkg" "$MOCK_INSTALLED" && { printf installed; exit 0; }
exit 1
MOCK
cat >"$TMP/bin/sudo" <<'MOCK'
#!/bin/bash
exec "$@"
MOCK
cat >"$TMP/bin/apt-get" <<'MOCK'
#!/bin/bash
mark=0
for arg in "$@"; do
  if [[ $arg == -- ]]; then mark=1; continue; fi
  ((mark)) && printf '%s\n' "$arg" >>"$MOCK_INSTALLED"
done
MOCK
cat >"$TMP/bin/apt" <<'MOCK'
#!/bin/bash
for arg in "$@"; do
  if [[ $arg == *.deb && -f $arg ]]; then
    dpkg-deb -f "$arg" Package >>"$MOCK_INSTALLED"
  fi
done
MOCK
chmod +x "$TMP/bin/"*

cat >"$TMP/demo/DEBIAN/control" <<'CONTROL'
Package: local-demo
Version: 1.0
Section: misc
Priority: optional
Architecture: all
Maintainer: Test <test@example.invalid>
Description: local test package
CONTROL
dpkg-deb --build "$TMP/demo" "$TMP/local-demo.deb" >/dev/null 2>&1

export OMARCHY_DEBIAN_PATH="$TMP/debian"
export MOCK_INSTALLED="$TMP/installed"
export PATH="$TMP/bin:/usr/bin:/bin"

"$ROOT/overlay/bin/omarchy-pkg-add" upstream-one
 grep -Fxq debian-one "$MOCK_INSTALLED"
"$ROOT/overlay/bin/omarchy-pkg-add" upstream-one
"$ROOT/overlay/bin/omarchy-pkg-add" upstream-any
 grep -Fxq debian-two "$MOCK_INSTALLED"
"$ROOT/overlay/bin/omarchy-pkg-add" hardware-only
"$ROOT/overlay/bin/omarchy-pkg-add" direct-name
 grep -Fxq direct-name "$MOCK_INSTALLED"
"$ROOT/overlay/bin/omarchy-pkg-add" "$TMP/local-demo.deb"
 grep -Fxq local-demo "$MOCK_INSTALLED"

before=$(sort -u "$MOCK_INSTALLED" | tr '\n' ' ')
if "$ROOT/overlay/bin/omarchy-pkg-add" unsupported-name >/dev/null 2>&1; then
  echo "Expected an unknown package to fail." >&2
  exit 1
fi
if "$ROOT/overlay/bin/omarchy-pkg-add" external-only >/dev/null 2>&1; then
  echo "Expected an external mapping to fail with guidance." >&2
  exit 1
fi
after=$(sort -u "$MOCK_INSTALLED" | tr '\n' ' ')
[[ $before == "$after" ]] || { echo "Unsupported requests partially installed packages." >&2; exit 1; }

echo "package-add tests passed"
