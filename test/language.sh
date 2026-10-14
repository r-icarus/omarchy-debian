#!/bin/bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
helper=$ROOT/overlay/bin/omarchy-debian-locale-ensure
for bad in '' en_US en_US.UTF-8/evil '--help' 'en_US.UTF-8;touch /tmp/no'; do
  if "$helper" "$bad" >"$T/out" 2>&1; then
    echo "invalid locale accepted: $bad" >&2; exit 1
  fi
done
if (( EUID == 0 )) || [[ ! -r /usr/share/i18n/locales/fr_FR ]]; then
  echo 'locale validation passed; authentication routing skipped (root or no locale sources)'
  exit 0
fi
mkdir "$T/bin"
printf '#!/bin/bash\nprintf "%%s\\n" "$@" >"$LOCALE_CALL_LOG"\nexit "${LOCALE_CALL_STATUS:-0}"\n' >"$T/bin/pkexec"
chmod +x "$T/bin/pkexec"
export LOCALE_CALL_LOG=$T/args
PATH="$T/bin:$PATH" "$helper" fr_FR.UTF-8 </dev/null
printf '/usr/bin/localedef\n--no-archive\n-i\nfr_FR\n-f\nUTF-8\nfr_FR.UTF-8\n' >"$T/expected"
cmp "$T/expected" "$T/args"
if LOCALE_CALL_STATUS=1 PATH="$T/bin:$PATH" "$helper" fr_FR.UTF-8 </dev/null; then
  echo 'cancelled authentication unexpectedly succeeded' >&2; exit 1
fi
echo 'Debian language helper tests passed'
