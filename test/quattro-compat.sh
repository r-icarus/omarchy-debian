#!/bin/bash
# Optional real-upstream patch test; no downloads or live tree modifications.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tree=${OMARCHY_QUATTRO_TEST_TREE:-}
if [[ -z $tree ]]; then
  echo 'SKIP: set OMARCHY_QUATTRO_TEST_TREE to test the pinned upstream source'
  exit 0
fi
expected=$(grep -oE 'OMARCHY_QUATTRO_REF:=[0-9a-f]{40}' "$ROOT/install/31-quattro-shell.sh")
expected=${expected#OMARCHY_QUATTRO_REF:=}
[[ $(git -C "$tree" rev-parse HEAD) == "$expected" ]] || {
  echo 'Upstream fixture is not at the installer pin' >&2; exit 1;
}
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
mapfile -t files < <(awk '/^diff --git / {sub(/^b\//, "", $4); print $4}' "$ROOT/patches/quattro-qml-compat.patch")
git -C "$tree" archive HEAD -- "${files[@]}" | tar -xf - -C "$t"
git init -q "$t"
git -C "$t" apply --check "$ROOT/patches/quattro-qml-compat.patch"
git -C "$t" apply "$ROOT/patches/quattro-qml-compat.patch"
git -C "$t" apply --reverse --check "$ROOT/patches/quattro-qml-compat.patch"
# Renaming QML identifiers must never rename the freedesktop protocol key.
grep -Fq 'notification.hints["transient"]' "$t/shell/plugins/notifications/Service.qml"
! grep -Fq 'notification.hints["transientSz"]' "$t/shell/plugins/notifications/Service.qml"
echo 'Pinned upstream compatibility patch tests passed'
