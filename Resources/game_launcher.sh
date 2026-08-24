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

steam_client_is_running() {
  local contents_path pid
  contents_path="$(cd "$WRAPPER/Contents" && pwd -P)"
  while IFS= read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    if /usr/sbin/lsof -a -p "$pid" -d cwd -Fn 2>/dev/null \
      | /usr/bin/awk -v root="n$contents_path" '
          $0 == root || index($0, root "/") == 1 { found=1 }
          END { exit(found ? 0 : 1) }
        '; then
      return 0
    fi
  done < <(/bin/ps -axo pid=,command= | /usr/bin/awk '
    {
      pid=$1
      $1=""
      sub(/^[[:space:]]+/, "", $0)
      command=tolower($0)
      if (command ~ /^[a-z]:\\.*\\steam\.exe([[:space:]]|$)/) print pid
    }
  ')
  return 1
}

if ! steam_client_is_running; then
  /usr/bin/open "$WRAPPER"
  for _ in {1..240}; do
    steam_client_is_running && break
    /bin/sleep 0.5
  done
fi

steam_client_is_running || {
  /usr/bin/osascript -e 'display alert "Windows Steam을 시작하지 못했습니다" as critical'
  exit 4
}

if ! "$WRAPPER_LAUNCHER" WSS-installer "$GAME_COMMAND" >/dev/null 2>&1; then
  /usr/bin/osascript -e 'display alert "Windows Steam에서 게임을 시작하지 못했습니다" as critical'
  exit 5
fi
