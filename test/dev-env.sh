#!/bin/bash
# Isolated tests for the Symfony-on-demand repository wrapper.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/upstream/bin"
: >"$TMP/log"

cat >"$TMP/bin/omarchy-install-symfony-cli-repo" <<'MOCK'
#!/bin/bash
printf 'repo\n' >>"$DEV_LOG"
MOCK
cat >"$TMP/upstream/bin/omarchy-install-dev-env" <<'MOCK'
#!/bin/bash
printf 'upstream:%s\n' "$*" >>"$DEV_LOG"
MOCK
chmod +x "$TMP/bin/omarchy-install-symfony-cli-repo" "$TMP/upstream/bin/omarchy-install-dev-env"
export DEV_LOG="$TMP/log" OMARCHY_PATH="$TMP/upstream" PATH="$TMP/bin:/usr/bin:/bin"

"$ROOT/overlay/bin/omarchy-install-dev-env" ruby
[[ $(cat "$TMP/log") == 'upstream:ruby' ]]
: >"$TMP/log"
"$ROOT/overlay/bin/omarchy-install-dev-env" symfony
[[ $(cat "$TMP/log") == $'repo\nupstream:symfony' ]]

# Mock the official setup download and privileged commands; do not touch apt
# sources or execute any downloaded vendor code during the test.
cat >"$TMP/bin/curl" <<'MOCK'
#!/bin/bash
out=
while (($#)); do
  if [[ $1 == -o ]]; then out=$2; shift 2; else shift; fi
done
printf 'printf "setup-ran\\n" >>"$DEV_LOG"\n' >"$out"
MOCK
cat >"$TMP/bin/sudo" <<'MOCK'
#!/bin/bash
[[ ${1:-} == -E ]] && shift
exec "$@"
MOCK
cat >"$TMP/bin/apt-get" <<'MOCK'
#!/bin/bash
printf 'apt-get %s\n' "$*" >>"$DEV_LOG"
MOCK
chmod +x "$TMP/bin/curl" "$TMP/bin/sudo" "$TMP/bin/apt-get"
: >"$TMP/log"
"$ROOT/overlay/bin/omarchy-install-symfony-cli-repo"
grep -Fxq setup-ran "$TMP/log"
grep -Fxq 'apt-get update' "$TMP/log"

echo "development menu tests passed"
