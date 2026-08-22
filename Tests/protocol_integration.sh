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

output="$(bash "$SCRIPT" launch)"
assert_contains "$output" '@@PHASE|launching'
assert_contains "$output" '@@STATE|ready'

cache="$wrapper/Contents/drive_c/users/tester/AppData/Local/Steam/htmlcache"
mkdir -p "$cache"
touch "$cache/stale"
output="$(bash "$SCRIPT" repair)"
assert_contains "$output" '@@PHASE|repairing'
[[ ! -e "$cache" ]] || { echo 'FAIL: repair did not clear cache' >&2; exit 1; }

output="$(bash "$SCRIPT" stop)"
assert_contains "$output" '@@PHASE|stopping'
assert_contains "$output" '@@STATE|ready'

printf 'PASS: setup protocol integration tests\n'
