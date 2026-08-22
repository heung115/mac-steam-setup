#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/Resources/setup.sh"
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/macsteam-protocol.XXXXXX")"
trap 'rm -rf "$TEST_HOME"' EXIT

export HOME="$TEST_HOME"
export USER="tester"
export MACSTEAM_TEST_NO_OPEN=1

assert_contains() {
  local output="$1"
  local expected="$2"
  [[ "$output" == *"$expected"* ]] || {
    printf 'FAIL: expected %s in:\n%s\n' "$expected" "$output" >&2
    exit 1
  }
}

output="$(bash "$SCRIPT" check)"
assert_contains "$output" '@@STATE|not_installed'

wrapper="$HOME/Applications/Sikarugir/Steam.app"
mkdir -p "$wrapper/Contents/MacOS"
output="$(bash "$SCRIPT" check)"
assert_contains "$output" '@@STATE|partial'

touch "$wrapper/Contents/.macsteamsetup-owner"
cat > "$wrapper/Contents/MacOS/Sikarugir" <<'SH'
#!/bin/bash
if [[ "${1:-}" == "WSS-installer" ]]; then
  printf '%s\n' "${2:-}" > "$HOME/wss-installer-argument"
fi
exit 0
SH
chmod +x "$wrapper/Contents/MacOS/Sikarugir"
mkdir -p "$wrapper/Contents/drive_c/Program Files (x86)/Steam"
touch "$wrapper/Contents/drive_c/Program Files (x86)/Steam/steam.exe"
cat > "$wrapper/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>D3DMETAL</key><integer>1</integer>
  <key>Program Name and Path</key><string>/Program Files (x86)/Steam/Steam.exe</string>
</dict></plist>
PLIST

output="$(bash "$SCRIPT" check)"
assert_contains "$output" '@@STATE|ready'

output="$(bash "$SCRIPT" runtime-status)"
assert_contains "$output" '@@RUNTIME|stopped'

/bin/bash -c 'exec -a "$1" /bin/sleep 30' _ "$wrapper/Contents/MacOS/Sikarugir" &
fake_wrapper_pid=$!
/bin/bash -c 'exec -a "$1" /bin/sleep 30' _ 'C:\Program Files (x86)\Steam\Steam.exe' &
fake_steam_pid=$!
/bin/sleep 0.1
output="$(bash "$SCRIPT" runtime-status)"
assert_contains "$output" '@@RUNTIME|running'
/bin/kill "$fake_wrapper_pid" "$fake_steam_pid"
wait "$fake_wrapper_pid" 2>/dev/null || true
wait "$fake_steam_pid" 2>/dev/null || true

output="$(bash "$SCRIPT" launch)"
assert_contains "$output" '@@PHASE|launching'
assert_contains "$output" '@@STATE|running'

cache="$wrapper/Contents/drive_c/users/tester/AppData/Local/Steam/htmlcache"
mkdir -p "$cache"
touch "$cache/stale"
output="$(bash "$SCRIPT" repair)"
assert_contains "$output" '@@PHASE|repairing'
[[ ! -e "$cache" ]] || { echo 'FAIL: repair did not clear cache' >&2; exit 1; }

output="$(bash "$SCRIPT" stop)"
assert_contains "$output" '@@PHASE|stopping'
assert_contains "$output" '@@STATE|ready'

steamapps="$wrapper/Contents/drive_c/Program Files (x86)/Steam/steamapps"
mkdir -p "$steamapps"
cat > "$steamapps/appmanifest_123.acf" <<'ACF'
"AppState"
{
  "appid" "123"
  "name" "Example Game"
  "installdir" "ExampleGame"
}
ACF
library_icon_dir="$wrapper/Contents/drive_c/Program Files (x86)/Steam/appcache/librarycache/123"
mkdir -p "$library_icon_dir"
game_icon="$library_icon_dir/0123456789abcdef0123456789abcdef01234567.jpg"
/usr/bin/sips -s format jpeg \
  '/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns' \
  --out "$game_icon" >/dev/null
output="$(bash "$SCRIPT" list-games)"
assert_contains "$output" '@@GAME|123|Example Game|ExampleGame'
assert_contains "$output" "$game_icon"
output="$(bash "$SCRIPT" create-shortcut 123)"
assert_contains "$output" '@@SHORTCUT|'
shortcut="$HOME/Applications/Windows Steam Games/Example Game.app"
[[ -x "$shortcut/Contents/MacOS/GameLauncher" ]] || { echo 'FAIL: game launcher missing' >&2; exit 1; }
launch_command="$shortcut/Contents/Resources/LaunchGame.bat"
[[ -f "$launch_command" ]] || { echo 'FAIL: Windows game command missing' >&2; exit 1; }
[[ -f "$shortcut/Contents/Resources/GameIcon.icns" ]] || { echo 'FAIL: game shortcut icon missing' >&2; exit 1; }
[[ "$(/usr/bin/plutil -extract CFBundleIconFile raw "$shortcut/Contents/Info.plist")" == "GameIcon" ]] \
  || { echo 'FAIL: game shortcut icon plist entry' >&2; exit 1; }
assert_contains "$(<"$launch_command")" '-applaunch 123'
if /usr/bin/grep -q 'steam://rungameid' "$shortcut/Contents/MacOS/GameLauncher"; then
  echo 'FAIL: game shortcut must not use the macOS Steam URL handler' >&2
  exit 1
fi
[[ "$(/usr/bin/plutil -extract SteamAppID raw "$shortcut/Contents/Info.plist")" == "123" ]] \
  || { echo 'FAIL: game shortcut App ID' >&2; exit 1; }
/usr/bin/codesign --verify --deep --strict "$shortcut"

/bin/bash -c 'exec -a "$1" /bin/sleep 30' _ "$wrapper/Contents/MacOS/Sikarugir" &
fake_wrapper_pid=$!
/bin/bash -c 'exec -a "$1" /bin/sleep 30' _ 'C:\Program Files (x86)\Steam\Steam.exe' &
fake_steam_pid=$!
/bin/sleep 0.1
"$shortcut/Contents/MacOS/GameLauncher"
assert_contains "$(<"$HOME/wss-installer-argument")" '/Contents/Resources/LaunchGame.bat'
/bin/kill "$fake_wrapper_pid" "$fake_steam_pid"
wait "$fake_wrapper_pid" 2>/dev/null || true
wait "$fake_steam_pid" 2>/dev/null || true

printf 'PASS: setup protocol integration tests\n'
