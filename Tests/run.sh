#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/Resources/setup_core.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  [[ "$actual" == "$expected" ]] || fail "$label (expected=$expected actual=$actual)"
}

[[ -f "$CORE" ]] || fail "setup_core.sh is missing"
# shellcheck source=../Resources/setup_core.sh
source "$CORE"

previous=-1
for phase in checking rosetta downloading wrapper windows steam configuring ready; do
  current="$(phase_percent "$phase")"
  (( current > previous )) || fail "progress must increase at $phase"
  previous="$current"
done
assert_equal "100" "$(phase_percent ready)" "ready progress"

assert_equal "wait" "$(installer_decision 0 0)" "missing Steam executable"
assert_equal "wait" "$(installer_decision 1 1)" "installer still visible"
assert_equal "finish" "$(installer_decision 1 0)" "installed Steam with closed installer"

launcher_path="/Users/test/Applications/Sikarugir/Steam.app/Contents/MacOS/Sikarugir"
printf '%s\n' "$launcher_path" | wrapper_launcher_is_running_in "$launcher_path" \
  || fail "wrapper launcher should be detected"
if printf '%s\n' '/another/prefix/Sikarugir' | wrapper_launcher_is_running_in "$launcher_path"; then
  fail "unrelated wrapper must not be detected"
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/macsteam-tests.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
plist="$tmp_dir/Info.plist"
cat > "$plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>D3DMETAL</key><integer>0</integer>
  <key>Program Name and Path</key><string>/nothing.exe</string>
  <key>Program Flags</key><string></string>
  <key>Skip Gecko</key><integer>0</integer>
  <key>Skip Mono</key><integer>0</integer>
</dict></plist>
PLIST

configure_wrapper_plist "$plist"
assert_equal "1" "$(/usr/bin/plutil -extract D3DMETAL raw "$plist")" "D3DMetal enabled"
assert_equal "/Program Files (x86)/Steam/Steam.exe" "$(/usr/bin/plutil -extract 'Program Name and Path' raw "$plist")" "Steam target"
assert_equal "-nobootstrapupdate -skipinitialbootstrap" "$(/usr/bin/plutil -extract 'Program Flags' raw "$plist")" "repeat launch skips blocking bootstrap update"
assert_equal "true" "$(/usr/bin/plutil -extract LSUIElement raw "$plist")" "launcher hidden from Dock"

manifest="$tmp_dir/appmanifest_123.acf"
cat > "$manifest" <<'ACF'
"AppState"
{
  "appid" "123"
  "name" "Example Game"
  "installdir" "ExampleGame"
}
ACF
assert_equal "123|Example Game|ExampleGame" "$(read_appmanifest "$manifest")" "manifest parser"

printf 'PASS: setup core regression tests\n'
bash "$ROOT/Tests/protocol_integration.sh"
