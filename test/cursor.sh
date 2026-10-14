#!/bin/bash
# Hermetic cursor-family selection tests; no GTK/compositor changes.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export ROOT
python3 - <<'PY'
import os, pathlib, subprocess, tempfile
root=pathlib.Path(os.environ['ROOT'])
with tempfile.TemporaryDirectory() as temp:
    t=pathlib.Path(temp); icons=t/'icons'; home=t/'home'; home.mkdir()
    theme=icons/'Adwaita/cursors'; theme.mkdir(parents=True)
    for name in ('left_ptr','pointer','text','wait'): (theme/name).write_bytes(b'Xcur')
    source=t/'env'
    source.write_text((root/'overlay/uwsm/env.d/10-omarchy').read_text().replace('/usr/share/icons',str(icons)))
    def selected(**values):
        env={'HOME':str(home),'PATH':'/usr/bin:/bin',**values}
        result=subprocess.check_output(['bash','-uc',
          'source "$1"; printf "%s|%s|%s|%s" "$XCURSOR_THEME" "$HYPRCURSOR_THEME" "$XCURSOR_SIZE" "$HYPRCURSOR_SIZE"',
          'cursor-test',str(source)],env=env,text=True)
        return result
    assert selected()=='Adwaita|Adwaita|24|24'
    (theme/'pointer').unlink()
    assert selected()=='Bibata-Modern-Classic|Bibata-Modern-Classic|24|24', 'incomplete Adwaita must not be chosen'
    assert selected(XCURSOR_THEME='Custom',XCURSOR_SIZE='32')=='Custom|Custom|32|32'
    assert selected(XCURSOR_THEME='Custom',HYPRCURSOR_THEME='Native',HYPRCURSOR_SIZE='48')=='Custom|Native|24|48'
phase=(root/'install/31-quattro-shell.sh').read_text()
assert 'for cursor_theme in Adwaita Bibata-Modern-Classic' in phase
assert 'omd_chown_path "$STARTUP_CURSORS"' in phase
assert 'adwaita-cursors\tapt\tadwaita-icon-theme\t' in (root/'packages/base.map').read_text()
print('Cursor-family selection tests passed')
PY
