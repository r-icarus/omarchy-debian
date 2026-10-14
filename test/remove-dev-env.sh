#!/bin/bash
# Isolated tests for Debian's PHP development-environment removal path.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home" "$TMP/upstream/bin"
: >"$TMP/log"

cat >"$TMP/bin/dpkg-query" <<'MOCK'
#!/bin/bash
pkg=${!#}
case " $INSTALLED_PACKAGES " in *" $pkg "*) printf installed; exit 0 ;; esac
exit 1
MOCK
cat >"$TMP/bin/omarchy-pkg-drop" <<'MOCK'
#!/bin/bash
printf 'drop:%s\n' "$*" >>"$TEST_LOG"
MOCK
cat >"$TMP/bin/mise" <<'MOCK'
#!/bin/bash
printf 'mise:%s\n' "$*" >>"$TEST_LOG"
MOCK
cat >"$TMP/upstream/bin/omarchy-remove-dev-env" <<'MOCK'
#!/bin/bash
printf 'upstream:%s\n' "$*" >>"$TEST_LOG"
MOCK
chmod +x "$TMP/bin/"* "$TMP/upstream/bin/omarchy-remove-dev-env"
export TEST_LOG="$TMP/log" HOME="$TMP/home" OMARCHY_PATH="$TMP/upstream"
export PATH="$TMP/bin:/usr/bin:/bin"

INSTALLED_PACKAGES='php-xdebug php-sqlite3' \
  "$ROOT/overlay/bin/omarchy-remove-dev-env" php
grep -Fxq 'drop:php-sqlite3 php-xdebug' "$TMP/log"
: >"$TMP/log"
output=$(INSTALLED_PACKAGES='' "$ROOT/overlay/bin/omarchy-remove-dev-env" php)
[[ $output == *"No apt-managed PHP packages are installed."* ]]

mkdir -p "$HOME/.local/share/mise/installs/php/8.4.0"
: >"$TMP/log"
INSTALLED_PACKAGES='' "$ROOT/overlay/bin/omarchy-remove-dev-env" php
grep -Fxq 'mise:uninstall php --all' "$TMP/log"
grep -Fxq 'mise:rm -g php' "$TMP/log"
grep -Fxq 'mise:tool-alias unset php' "$TMP/log"

: >"$TMP/log"
INSTALLED_PACKAGES='' "$ROOT/overlay/bin/omarchy-remove-dev-env" ruby
grep -Fxq 'upstream:ruby' "$TMP/log"

echo "PHP removal tests passed"
