#!/bin/bash
# Offline staging, rollback and patch-failure regression checks.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
source "$ROOT/lib/log.sh"
source "$ROOT/lib/target.sh"
source "$ROOT/lib/quattro.sh"
mkdir "$T/source"
git -C "$T/source" init -q
printf 'native\n' >"$T/source/ui"
printf 'one\n' >"$T/source/version"
git -C "$T/source" add .
git -C "$T/source" -c user.name=test -c user.email=test@test commit -qm one
old=$(git -C "$T/source" rev-parse HEAD)
printf 'compatible\n' >"$T/source/ui"
git -C "$T/source" diff >"$T/compat.patch"
git -C "$T/source" restore ui
printf 'two\n' >"$T/source/version"
git -C "$T/source" add .
git -C "$T/source" -c user.name=test -c user.email=test@test commit -qm two
new=$(git -C "$T/source" rev-parse HEAD)
git clone -q "$T/source" "$T/live"
git -C "$T/live" checkout -q --detach "$old"
printf 'local custom edit\n' >"$T/live/ui"
printf 'custom untracked\n' >"$T/live/custom"
omd_quattro_prepare "file://$T/source" "$new" "$T/live" "$T/compat.patch"
[[ $(git -C "$T/live" rev-parse HEAD) == "$new" ]]
[[ $(<"$T/live/ui") == compatible ]]
backups=("$T/live.pre-upgrade."*)
[[ ${#backups[@]} == 1 ]]
[[ $(<"${backups[0]}/ui") == 'local custom edit' ]]
[[ $(<"${backups[0]}/custom") == 'custom untracked' ]]
# Repeat proves reverse-check idempotence without another backup.
omd_quattro_prepare "file://$T/source" "$new" "$T/live" "$T/compat.patch"
backups=("$T/live.pre-upgrade."*)
[[ ${#backups[@]} == 1 ]]
# An incompatible new revision must not replace the live tree.
printf 'incompatible upstream\n' >"$T/source/ui"
git -C "$T/source" add .
git -C "$T/source" -c user.name=test -c user.email=test@test commit -qm incompatible
bad=$(git -C "$T/source" rev-parse HEAD)
# Run in a separate shell so conditional callers cannot suppress errexit.
export ROOT T bad
if bash -euc 'source "$ROOT/lib/log.sh"; source "$ROOT/lib/target.sh"; source "$ROOT/lib/quattro.sh"; omd_quattro_prepare "file://$T/source" "$bad" "$T/live" "$T/compat.patch"'; then
  echo 'incompatible patch unexpectedly accepted' >&2; exit 1
fi
[[ $(git -C "$T/live" rev-parse HEAD) == "$new" ]]
[[ $(<"$T/live/ui") == compatible ]]
[[ -z $(find "$T" -maxdepth 1 -name 'live.staging.*' -print) ]]
# Same-revision local edits must not masquerade as already patched.
printf 'unknown modification\n' >"$T/live/ui"
if omd_quattro_patch "$T/live" "$T/compat.patch"; then
  echo 'unknown patch state unexpectedly accepted' >&2; exit 1
fi
# Rollback uses the untouched saved directory, not a hard reset.
mv "$T/live" "$T/failed"
mv "${backups[0]}" "$T/live"
[[ $(git -C "$T/live" rev-parse HEAD) == "$old" ]]
[[ $(<"$T/live/ui") == 'local custom edit' ]]
[[ $(<"$T/live/custom") == 'custom untracked' ]]
python3 - "$ROOT" "$T" <<'PY'
import json, pathlib, subprocess, sys
root, temp = map(pathlib.Path, sys.argv[1:])
path = temp / 'shell.json'
config = {'version': 1, 'bar': {'mine': True}, 'plugins': ['custom'], 'future': 7}
path.write_text(json.dumps(config))
def merge():
    return subprocess.check_output(['python3', str(root/'lib/quattro-config.py'), str(path),
                                    str(root/'overlay/quattro/config/omarchy/shell.json')])
merged = json.loads(merge())
assert {k: v for k, v in merged.items() if k != 'dock'} == config
assert merged['dock']['pinned'] == ['org.gnome.Nautilus', 'chromium', 'kitty']
config['dock'] = {'pinned': ['custom.desktop'], 'autohide': True}
path.write_text(json.dumps(config))
assert merge() == path.read_bytes(), 'existing dock config must stay byte-identical'
path.write_text('{invalid')
result = subprocess.run(['python3', str(root/'lib/quattro-config.py'), str(path),
                         str(root/'overlay/quattro/config/omarchy/shell.json')], capture_output=True)
assert result.returncode != 0
assert path.read_text() == '{invalid'
PY
printf 'Quattro upgrade tests passed\n'
