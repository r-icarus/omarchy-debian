#!/bin/bash
# Isolated tests for the Podman-first development database menu action.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test -x "$ROOT/overlay/bin/omarchy-launch-floating-terminal-with-presentation" || {
  echo "Presentation launcher must be executable." >&2
  exit 1
}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/debian/overlay/bin"
: >"$TMP/log"

cat >"$TMP/bin/podman" <<'MOCK'
#!/bin/bash
printf 'podman:%s\n' "$*" >>"$TEST_LOG"
case "${1:-}" in
  info) printf true; exit 0 ;;
  container)
    [[ ${2:-} == inspect && ${3:-} == "${EXISTING_CONTAINER:-}" ]]
    exit
    ;;
  inspect)
    printf '%s\n' "${CONTAINER_STATE:-running}"
    ;;
  run) printf 'fake-container-id\n' ;;
  start) ;;
esac
MOCK
cat >"$TMP/debian/overlay/bin/omarchy-pkg-add" <<'MOCK'
#!/bin/bash
printf 'pkg-add:%s\n' "$*" >>"$TEST_LOG"
[[ $* == passt ]] || exit 1
printf '#!/bin/sh\nexit 0\n' >"$TEST_BIN/pasta"
chmod +x "$TEST_BIN/pasta"
MOCK
cat >"$TMP/bin/systemctl" <<'MOCK'
#!/bin/bash
printf 'systemctl:%s\n' "$*" >>"$TEST_LOG"
case " $* " in
  *' show-environment '*) exit 0 ;;
  *' is-enabled '*) exit 1 ;;
esac
exit 0
MOCK
cat >"$TMP/bin/gum" <<'MOCK'
#!/bin/bash
exit 130
MOCK
chmod +x "$TMP/bin/"* "$TMP/debian/overlay/bin/omarchy-pkg-add"
export TEST_LOG="$TMP/log" TEST_BIN="$TMP/bin" OMARCHY_DEBIAN_PATH="$TMP/debian"
export PATH="$TMP/bin:/usr/bin:/bin"

output=$("$ROOT/overlay/bin/omarchy-install-docker-dbs" PostgreSQL)
[[ $output == *"PostgreSQL is running on localhost."* ]]
grep -Fxq 'podman:run -d --restart=unless-stopped --publish 127.0.0.1:5432:5432 --name postgres18 -e POSTGRES_HOST_AUTH_METHOD=trust docker.io/library/postgres:18' "$TMP/log"
grep -Fxq 'systemctl:--user enable podman-restart.service' "$TMP/log"
# Hosts that already provide pasta need no package install; otherwise the
# mocked installer above creates it without touching the host.
if grep -q '^pkg-add:' "$TMP/log"; then
  grep -Fxq 'pkg-add:passt' "$TMP/log"
fi
! grep -q '^sudo:' "$TMP/log"

for spec in \
  'MySQL docker.io/library/mysql:8.4' \
  'MongoDB docker.io/library/mongo:noble' \
  'MariaDB docker.io/library/mariadb:11.8' \
  'MSSQL mcr.microsoft.com/mssql/server:2022-CU12-ubuntu-22.04'; do
  read -r db image <<<"$spec"
  : >"$TMP/log"
  "$ROOT/overlay/bin/omarchy-install-docker-dbs" "$db" >/dev/null
  grep -Fq " $image" "$TMP/log"
done

grep -Fq '"icon":""' "$ROOT/overlay/config/omarchy/extensions/omarchy-menu.jsonc"
grep -Fq '"label":"Docker DB"' "$ROOT/overlay/config/omarchy/extensions/omarchy-menu.jsonc"

: >"$TMP/log"
output=$(EXISTING_CONTAINER=redis CONTAINER_STATE=running \
  "$ROOT/overlay/bin/omarchy-install-docker-dbs" Redis)
[[ $output == *"already running in container redis"* ]]
! grep -q 'podman:run ' "$TMP/log"

: >"$TMP/log"
EXISTING_CONTAINER=mysql8 CONTAINER_STATE=exited \
  "$ROOT/overlay/bin/omarchy-install-docker-dbs" MySQL >/dev/null
grep -Fxq 'podman:start mysql8' "$TMP/log"

if "$ROOT/overlay/bin/omarchy-install-docker-dbs" Unknown >/dev/null 2>&1; then
  echo "Expected an unknown database to fail." >&2
  exit 1
fi

output=$("$ROOT/overlay/bin/omarchy-install-docker-dbs" 2>&1 || true)
[[ $output == *"Database selection cancelled."* ]]

echo "container DB tests passed"
