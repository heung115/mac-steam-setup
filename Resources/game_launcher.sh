#!/bin/bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APP_ID="$(/usr/bin/plutil -extract SteamAppID raw "$APP_DIR/Contents/Info.plist")"
WRAPPER="$HOME/Applications/Sikarugir/Steam.app"
WINE="$WRAPPER/Contents/SharedSupport/wine/bin/wine"
PREFIX="$WRAPPER/Contents/SharedSupport/prefix"

[[ "$APP_ID" =~ ^[0-9]+$ ]] || exit 2
[[ -x "$WINE" && -d "$PREFIX" ]] || {
  /usr/bin/osascript -e 'display alert "Windows Steam이 설치되어 있지 않습니다" as critical'
  exit 3
}

steam_is_running() {
  /bin/ps -axo command= | /usr/bin/awk -v wrapper="$WRAPPER" '
    index($0, wrapper "/Contents/SharedSupport/wine") &&
    tolower($0) ~ /(steam\.exe|steamwebhelper\.exe)/ { found=1 }
    END { exit(found ? 0 : 1) }
  '
}

if ! steam_is_running; then
  /usr/bin/open "$WRAPPER"
  for _ in {1..240}; do
    steam_is_running && break
    /bin/sleep 0.5
  done
fi

steam_is_running || {
  /usr/bin/osascript -e 'display alert "Windows Steam을 시작하지 못했습니다" as critical'
  exit 4
}

export WINEPREFIX="$PREFIX"
export DYLD_FALLBACK_LIBRARY_PATH="$WRAPPER/Contents/Frameworks/moltenvkcx:$WRAPPER/Contents/SharedSupport/wine/lib:$WRAPPER/Contents/SharedSupport/wine/lib64:$WRAPPER/Contents/Frameworks:$WRAPPER/Contents/Frameworks/GStreamer.framework/Libraries:/opt/wine/lib:/usr/lib:/usr/libexec:/usr/lib/system"
"$WINE" start "steam://rungameid/$APP_ID" >/dev/null 2>&1
