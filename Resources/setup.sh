#!/bin/bash
# PROTOTYPE — CC0-derived orchestration based on:
# https://github.com/mirpo/windows-steam-on-apple-silicon
# Downloads third-party components from their official distribution URLs.

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ENGINE="WS12WineSikarugir10.0_6"
TEMPLATE="Template-1.0.11"
WRAPPER="$HOME/Applications/Sikarugir/Steam.app"
CACHE="$HOME/Library/Application Support/Sikarugir"
APP_CACHE="$HOME/Library/Caches/MacSteamSetup"
ENGINE_ARCHIVE="$CACHE/Engines/${ENGINE}.tar.xz"
TEMPLATE_ARCHIVE="$CACHE/Template/${TEMPLATE}.tar.xz"
ENGINE_SHA256="9da7ee0cbf386522f3a9906943726d9c3c125dbbd9ab120e3cde80e88d6091b2"
TEMPLATE_SHA256="9fa15479e7ff6abd99c1d07be285fb95f41fc6991586502427152b1f7d6ccb8a"
ENGINE_URL="https://github.com/Sikarugir-App/Engines/releases/download/v1.0/${ENGINE}.tar.xz"
TEMPLATE_URL="https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0/${TEMPLATE}.tar.xz"
STEAM_SETUP="$HOME/Applications/Sikarugir/SteamSetup.exe"
STEAM_URL="https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"
STEAM_EXE="$WRAPPER/Contents/drive_c/Program Files (x86)/Steam/steam.exe"
PLIST="$WRAPPER/Contents/Info.plist"
OWNER_MARKER="$WRAPPER/Contents/.macsteamsetup-owner"
HTML_CACHE="$WRAPPER/Contents/drive_c/users/$USER/AppData/Local/Steam/htmlcache"

phase() { printf '@@PHASE|%s\n' "$1"; }
message() { printf '@@MESSAGE|%s\n' "$1"; }
fail() { printf '@@ERROR|%s\n' "$1" >&2; exit 1; }

is_configured() {
  [[ -f "$PLIST" ]] || return 1
  [[ "$(/usr/bin/plutil -extract D3DMETAL raw -o - "$PLIST" 2>/dev/null || true)" == "1" ]] || return 1
  [[ "$(/usr/bin/plutil -extract 'Program Name and Path' raw -o - "$PLIST" 2>/dev/null || true)" == "/Program Files (x86)/Steam/Steam.exe" ]]
}

check_state() {
  if [[ -f "$STEAM_EXE" ]] && is_configured; then
    printf '@@STATE|ready\n'
  elif [[ -d "$WRAPPER" ]]; then
    printf '@@STATE|partial\n'
  else
    printf '@@STATE|not_installed\n'
  fi
}

if [[ "${1:-setup}" == "check" ]]; then
  check_state
  exit 0
fi

if [[ "${1:-setup}" == "repair" ]]; then
  phase "repairing"
  message "Steam 로그인 화면용 임시 데이터를 초기화하고 있습니다"
  [[ -f "$OWNER_MARKER" && -x "$WRAPPER/Contents/MacOS/Sikarugir" ]] \
    || fail "이 설치 앱이 만든 Windows Steam을 찾을 수 없습니다"
  [[ ! -L "$HTML_CACHE" ]] || fail "Steam 임시 데이터 위치가 안전하지 않습니다"
  "$WRAPPER/Contents/MacOS/Sikarugir" WSS-wineserverkill >/dev/null 2>&1 || true
  /bin/rm -rf "$HTML_CACHE"
  /usr/bin/open "$WRAPPER"
  printf '@@STATE|ready\n'
  message "로그인 화면을 복구했습니다. Steam이 다시 열렸습니다"
  exit 0
fi

phase "checking"
message "이 Mac이 실행 조건을 만족하는지 확인하고 있습니다"
[[ "$(uname -m)" == "arm64" ]] || fail "Apple Silicon Mac에서만 사용할 수 있습니다"
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
(( MACOS_MAJOR >= 14 )) || fail "macOS Sonoma 14 이상이 필요합니다"
if ! /usr/sbin/pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
  phase "rosetta"
  message "Windows 앱 실행에 필요한 Apple Rosetta 2를 설치하고 있습니다"
  /usr/sbin/softwareupdate --install-rosetta --agree-to-license \
    || fail "Rosetta 2를 자동으로 설치하지 못했습니다"
fi
/usr/sbin/pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1 \
  || fail "Rosetta 2 설치를 확인하지 못했습니다"
FREE_GB="$(df -g "$HOME" | awk 'NR==2 {print $4}')"
(( FREE_GB >= 5 )) || fail "설치 공간이 부족합니다. 최소 5GB를 확보해 주세요"

phase "downloading"
message "Sikarugir 공식 실행 엔진과 앱 틀을 내려받고 있습니다"
mkdir -p "$CACHE/Engines" "$CACHE/Template" "$APP_CACHE/template" "$HOME/Applications/Sikarugir"

fetch() {
  local url="$1"
  local destination="$2"
  local expected_sha="$3"
  [[ ! -L "$destination" ]] || fail "다운로드 위치가 안전하지 않습니다: $(basename "$destination")"
  if [[ ! -s "$destination" ]]; then
    local partial
    partial="$(/usr/bin/mktemp "${destination}.part.XXXXXX")"
    /usr/bin/curl --fail --location --retry 3 --progress-bar --output "$partial" "$url"
    /usr/bin/tar -tf "$partial" >/dev/null 2>&1 || fail "다운로드 파일 검증에 실패했습니다: $(basename "$destination")"
    [[ "$(/usr/bin/shasum -a 256 "$partial" | /usr/bin/awk '{print $1}')" == "$expected_sha" ]] \
      || fail "다운로드 파일의 고정 버전 검증에 실패했습니다: $(basename "$destination")"
    /bin/mv -n "$partial" "$destination"
  fi
  /usr/bin/tar -tf "$destination" >/dev/null 2>&1 || fail "다운로드 파일 검증에 실패했습니다: $(basename "$destination")"
  [[ "$(/usr/bin/shasum -a 256 "$destination" | /usr/bin/awk '{print $1}')" == "$expected_sha" ]] \
    || fail "캐시 파일이 검증된 고정 버전과 다릅니다: $(basename "$destination")"
}

fetch "$ENGINE_URL" "$ENGINE_ARCHIVE" "$ENGINE_SHA256"
fetch "$TEMPLATE_URL" "$TEMPLATE_ARCHIVE" "$TEMPLATE_SHA256"

phase "wrapper"
message "Windows Steam 전용 Mac 앱을 만들고 있습니다"
[[ ! -L "$WRAPPER" ]] || fail "Steam.app 위치가 심볼릭 링크라 안전하게 진행할 수 없습니다"
if [[ -d "$WRAPPER" && ! -f "$OWNER_MARKER" ]]; then
  fail "기존 Steam.app은 이 설치 앱이 만든 것으로 확인되지 않아 변경하지 않았습니다"
fi
if [[ ! -d "$WRAPPER" ]]; then
  if [[ ! -d "$APP_CACHE/template/${TEMPLATE}.app" ]]; then
    /usr/bin/tar -xf "$TEMPLATE_ARCHIVE" -C "$APP_CACHE/template"
  fi
  /usr/bin/ditto "$APP_CACHE/template/${TEMPLATE}.app" "$WRAPPER"
  /usr/bin/tar -xf "$ENGINE_ARCHIVE" -C "$WRAPPER/Contents/SharedSupport"
  [[ -d "$WRAPPER/Contents/SharedSupport/wswine.bundle" ]] || fail "Wine 엔진 구조를 확인할 수 없습니다"
  /bin/mv "$WRAPPER/Contents/SharedSupport/wswine.bundle" "$WRAPPER/Contents/SharedSupport/wine"
  printf 'MacSteamSetup prototype owner v1\n' > "$OWNER_MARKER"
fi

LAUNCHER="$WRAPPER/Contents/MacOS/Sikarugir"
[[ -x "$LAUNCHER" ]] || fail "생성된 Sikarugir 실행 파일을 찾을 수 없습니다"

phase "windows"
message "Windows 실행 공간을 처음 한 번 준비하고 있습니다"
if [[ ! -d "$WRAPPER/Contents/drive_c/windows" ]]; then
  "$LAUNCHER" WSS-wineprefixcreate
fi
[[ -d "$WRAPPER/Contents/drive_c/Program Files (x86)" ]] || fail "Windows 실행 공간 생성에 실패했습니다"

phase "steam"
message "Windows Steam 설치 창이 열리면 기본 설정으로 설치해 주세요"
if [[ ! -f "$STEAM_EXE" ]]; then
  if [[ ! -s "$STEAM_SETUP" ]]; then
    /usr/bin/curl --fail --location --retry 3 --progress-bar --output "$STEAM_SETUP" "$STEAM_URL"
  fi
  /usr/bin/file "$STEAM_SETUP" | /usr/bin/grep -q 'PE32 executable' || fail "Steam 설치 파일 검증에 실패했습니다"
  printf '@@ACTION|steam_installer\n'
  "$LAUNCHER" WSS-installer "$STEAM_SETUP"
  [[ -f "$STEAM_EXE" ]] || fail "Steam 설치를 완료하지 못했습니다. 설치 경로는 기본값을 사용해 주세요"
fi

phase "configuring"
message "D3DMetal과 실행 설정을 자동으로 적용하고 있습니다"
[[ -f "$PLIST" ]] || fail "Steam 앱 설정 파일을 찾을 수 없습니다"
if [[ ! -f "$PLIST.original" ]]; then
  /usr/bin/ditto "$PLIST" "$PLIST.original"
fi
/usr/bin/plutil -replace D3DMETAL -integer 1 "$PLIST"
/usr/bin/plutil -replace 'Program Name and Path' -string '/Program Files (x86)/Steam/Steam.exe' "$PLIST"
/usr/bin/plutil -replace 'Program Flags' -string '' "$PLIST"
/usr/bin/plutil -replace 'Skip Gecko' -integer 1 "$PLIST"
/usr/bin/plutil -replace 'Skip Mono' -integer 1 "$PLIST"

is_configured || fail "D3DMetal 설정 확인에 실패했습니다"

phase "ready"
message "준비가 끝났습니다. Windows Steam을 실행합니다"
printf '@@STATE|ready\n'
/usr/bin/open "$WRAPPER"
