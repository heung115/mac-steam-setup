#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHELL_LOCALIZATION="$ROOT/Resources/localization.sh"
EN_STRINGS="$ROOT/Resources/en.lproj/Localizable.strings"
KO_STRINGS="$ROOT/Resources/ko.lproj/Localizable.strings"

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

/usr/bin/plutil -lint "$EN_STRINGS" "$KO_STRINGS" >/dev/null

english_message="$(MACSTEAM_UI_LANGUAGE=en /bin/bash -c \
  'source "$1"; ui_text checking_requirements' _ "$SHELL_LOCALIZATION")"
korean_message="$(MACSTEAM_UI_LANGUAGE=ko /bin/bash -c \
  'source "$1"; ui_text checking_requirements' _ "$SHELL_LOCALIZATION")"
english_dynamic="$(MACSTEAM_UI_LANGUAGE=en /bin/bash -c \
  'source "$1"; ui_text shortcut_conflict "Example.app"' _ "$SHELL_LOCALIZATION")"

assert_equal "Checking whether this Mac meets the requirements" "$english_message" \
  "English setup message"
assert_equal "이 Mac이 실행 조건을 만족하는지 확인하고 있습니다" "$korean_message" \
  "Korean setup message"
assert_equal "An existing file has the same name and was not overwritten: Example.app" \
  "$english_dynamic" "English dynamic setup message"

swift_keys="$(/usr/bin/grep -Eo 'L10n\.(string|format)\("[^"]+' "$ROOT/MacSteamSetupApp.swift" \
  | /usr/bin/sed -E 's/.*\("//' | /usr/bin/sort -u)"
while IFS= read -r key; do
  [[ -n "$key" ]] || continue
  /usr/bin/grep -Fq "\"$key\" =" "$EN_STRINGS" || fail "missing English Swift key: $key"
  /usr/bin/grep -Fq "\"$key\" =" "$KO_STRINGS" || fail "missing Korean Swift key: $key"
done <<< "$swift_keys"

shell_keys="$(/usr/bin/grep -Eho '(message_key|fail_key|ui_text) [a-z_][a-z0-9_]*' \
  "$ROOT/Resources/setup.sh" "$ROOT/Resources/game_launcher.sh" \
  | /usr/bin/awk '{print $2}' | /usr/bin/sort -u)"
while IFS= read -r key; do
  [[ -n "$key" ]] || continue
  /usr/bin/grep -Fq "ko:$key)" "$SHELL_LOCALIZATION" || fail "missing Korean shell key: $key"
  /usr/bin/grep -Fq "en:$key)" "$SHELL_LOCALIZATION" || fail "missing English shell key: $key"
done <<< "$shell_keys"

printf 'PASS: localization resources and keys\n'
