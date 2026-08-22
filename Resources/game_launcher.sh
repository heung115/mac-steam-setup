#!/bin/bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APP_ID="$(/usr/bin/plutil -extract SteamAppID raw "$APP_DIR/Contents/Info.plist")"
WRAPPER="$HOME/Applications/Sikarugir/Steam.app"
WRAPPER_LAUNCHER="$WRAPPER/Contents/MacOS/Sikarugir"
GAME_COMMAND="$APP_DIR/Contents/Resources/LaunchGame.bat"

[[ "$APP_ID" =~ ^[0-9]+$ ]] || exit 2
[[ -x "$WRAPPER_LAUNCHER" && -f "$GAME_COMMAND" ]] || {
  /usr/bin/osascript -e 'display alert "Windows Steam이 설치되어 있지 않습니다" as critical'
  exit 3
}

steam_is_running() {
  /bin/ps -axo command= | /usr/bin/awk -v launcher="$WRAPPER/Contents/MacOS/Sikarugir" '
    index($0, launcher) == 1 { found=1 }
    END { exit(found ? 0 : 1) }
  '
}

steam_client_is_running() {
  /bin/ps -axo command= | /usr/bin/awk '
    tolower($0) ~ /^[[:space:]]*[a-z]:\\.*\\steam\.exe([[:space:]]|$)/ { found=1 }
    END { exit(found ? 0 : 1) }
  '
}

steam_runtime_is_running() {
  steam_is_running && steam_client_is_running
}

if ! steam_runtime_is_running; then
  /usr/bin/open "$WRAPPER"
  for _ in {1..240}; do
    steam_runtime_is_running && break
    /bin/sleep 0.5
  done
fi

steam_runtime_is_running || {
  /usr/bin/osascript -e 'display alert "Windows Steam을 시작하지 못했습니다" as critical'
  exit 4
}

if ! "$WRAPPER_LAUNCHER" WSS-installer "$GAME_COMMAND" >/dev/null 2>&1; then
  /usr/bin/osascript -e 'display alert "Windows Steam에서 게임을 시작하지 못했습니다" as critical'
  exit 5
fi
