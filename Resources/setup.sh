#!/bin/bash
# PROTOTYPE — CC0-derived orchestration based on:
# https://github.com/mirpo/windows-steam-on-apple-silicon
# Downloads third-party components from their official distribution URLs.

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=setup_core.sh
source "$SCRIPT_DIR/setup_core.sh"

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
LOCK_DIR="$APP_CACHE/setup.lock"
STEAMAPPS="$WRAPPER/Contents/drive_c/Program Files (x86)/Steam/steamapps"
LIBRARY_CACHE="$WRAPPER/Contents/drive_c/Program Files (x86)/Steam/appcache/librarycache"
GAME_SHORTCUTS_DIR="$HOME/Applications/Windows Steam Games"

progress() { printf '@@PROGRESS|%s|%s\n' "$1" "${2:-}"; }
phase() {
  printf '@@PHASE|%s\n' "$1"
  progress "$(phase_percent "$1")" "$1"
}
message() { printf '@@MESSAGE|%s\n' "$1"; }
fail() { printf '@@ERROR|%s\n' "$1" >&2; exit 1; }

open_wrapper() {
  if [[ "${MACSTEAM_TEST_NO_OPEN:-0}" == "1" ]]; then
    return 0
  fi
  /usr/bin/open "$WRAPPER"
}

open_steam_main() {
  open_wrapper
}

steam_is_running() {
  /bin/ps -axo command= | wrapper_launcher_is_running_in "$WRAPPER/Contents/MacOS/Sikarugir"
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

steam_ui_is_running() {
  /bin/ps -axo command= | /usr/bin/awk '
    tolower($0) ~ /steamwebhelper\.exe/ { found=1 }
    END { exit(found ? 0 : 1) }
  '
}

stop_wrapper() {
  "$WRAPPER/Contents/MacOS/Sikarugir" WSS-wineserverkill >/dev/null 2>&1 || true
  for _ in {1..20}; do
    steam_is_running || return 0
    /bin/sleep 0.25
  done
  return 1
}

create_game_icns() {
  local source="$1"
  local output="$2"
  local work iconset result=0
  [[ -f "$source" && ! -L "$source" ]] || return 1
  work="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/macsteam-game-icon.XXXXXX")" || return 1
  iconset="$work/GameIcon.iconset"
  /bin/mkdir -p "$iconset"
  /usr/bin/sips -s format png -z 16 16 "$source" --out "$iconset/icon_16x16.png" >/dev/null || result=1
  /usr/bin/sips -s format png -z 32 32 "$source" --out "$iconset/icon_16x16@2x.png" >/dev/null || result=1
  /usr/bin/sips -s format png -z 32 32 "$source" --out "$iconset/icon_32x32.png" >/dev/null || result=1
  /usr/bin/sips -s format png -z 64 64 "$source" --out "$iconset/icon_32x32@2x.png" >/dev/null || result=1
  /usr/bin/sips -s format png -z 128 128 "$source" --out "$iconset/icon_128x128.png" >/dev/null || result=1
  /usr/bin/sips -s format png -z 256 256 "$source" --out "$iconset/icon_128x128@2x.png" >/dev/null || result=1
  /usr/bin/sips -s format png -z 256 256 "$source" --out "$iconset/icon_256x256.png" >/dev/null || result=1
  /usr/bin/sips -s format png -z 512 512 "$source" --out "$iconset/icon_256x256@2x.png" >/dev/null || result=1
  /usr/bin/sips -s format png -z 512 512 "$source" --out "$iconset/icon_512x512.png" >/dev/null || result=1
  /usr/bin/sips -s format png -z 1024 1024 "$source" --out "$iconset/icon_512x512@2x.png" >/dev/null || result=1
  if (( result == 0 )); then
    /usr/bin/iconutil -c icns "$iconset" -o "$output" || result=1
  fi
  /bin/rm -rf "$work"
  return "$result"
}

steam_installer_is_running() {
  /bin/ps -axo command= | /usr/bin/awk '
    tolower($0) ~ /^[[:space:]]*[a-z]:\\.*steamsetup\.exe/ { found=1 }
    END { exit(found ? 0 : 1) }
  '
}

configure_steam_english() {
  local wine="$WRAPPER/Contents/SharedSupport/wine/bin/wine"
  local prefix="$WRAPPER/Contents/SharedSupport/prefix"
  [[ -x "$wine" && -d "$prefix" ]] || fail "Steam 언어 설정에 필요한 Wine 환경을 찾을 수 없습니다"
  (
    export WINEPREFIX="$prefix"
    export DYLD_FALLBACK_LIBRARY_PATH="$WRAPPER/Contents/Frameworks/moltenvkcx:$WRAPPER/Contents/SharedSupport/wine/lib:$WRAPPER/Contents/SharedSupport/wine/lib64:$WRAPPER/Contents/Frameworks:$WRAPPER/Contents/Frameworks/GStreamer.framework/Libraries:/opt/wine/lib:/usr/lib:/usr/libexec:/usr/lib/system"
    "$wine" reg add 'HKCU\Software\Valve\Steam' /v Language /t REG_SZ /d english /f >/dev/null 2>&1
    "$wine" reg add 'HKLM\Software\Wow6432Node\Valve\Steam' /v Language /t REG_SZ /d english /f >/dev/null 2>&1
    "$wine" reg add 'HKLM\Software\Wow6432Node\Valve\Steam\NSIS' /v InstallerLanguage /t REG_SZ /d 1033 /f >/dev/null 2>&1
  ) || fail "Steam 초기 언어를 설정하지 못했습니다"
  "$WRAPPER/Contents/MacOS/Sikarugir" WSS-wineserverkill >/dev/null 2>&1 || true
}

acquire_setup_lock() {
  /bin/mkdir -p "$APP_CACHE"
  [[ ! -L "$LOCK_DIR" ]] || fail "설치 잠금 위치가 안전하지 않습니다"
  if ! /bin/mkdir "$LOCK_DIR" 2>/dev/null; then
    local old_pid=""
    [[ -f "$LOCK_DIR/pid" ]] && old_pid="$(<"$LOCK_DIR/pid")"
    if [[ "$old_pid" =~ ^[0-9]+$ ]] && /bin/kill -0 "$old_pid" 2>/dev/null; then
      fail "이미 설치가 진행 중입니다"
    fi
    /bin/rm -f "$LOCK_DIR/pid"
    /bin/rmdir "$LOCK_DIR" 2>/dev/null || fail "이전 설치 잠금을 정리하지 못했습니다"
    /bin/mkdir "$LOCK_DIR"
  fi
  printf '%s\n' "$$" > "$LOCK_DIR/pid"
  trap 'status=$?; /bin/rm -f "$LOCK_DIR/pid"; /bin/rmdir "$LOCK_DIR" 2>/dev/null || true; exit "$status"' EXIT
}

is_configured() {
  [[ -f "$PLIST" ]] || return 1
  [[ "$(/usr/bin/plutil -extract D3DMETAL raw -o - "$PLIST" 2>/dev/null || true)" == "1" ]] || return 1
  [[ "$(/usr/bin/plutil -extract 'Program Name and Path' raw -o - "$PLIST" 2>/dev/null || true)" == "/Program Files (x86)/Steam/Steam.exe" ]]
}

check_state() {
  if [[ -f "$STEAM_EXE" ]] && is_configured; then
    if steam_runtime_is_running; then
      printf '@@STATE|running\n'
    else
      printf '@@STATE|ready\n'
    fi
  elif [[ -d "$WRAPPER" ]]; then
    printf '@@STATE|partial\n'
  else
    printf '@@STATE|not_installed\n'
  fi
}

if [[ "${1:-setup}" == "runtime-status" ]]; then
  if steam_runtime_is_running; then
    printf '@@RUNTIME|running\n'
  else
    printf '@@RUNTIME|stopped\n'
  fi
  exit 0
fi

if [[ "${1:-setup}" == "check" ]]; then
  check_state
  exit 0
fi

if [[ "${1:-setup}" == "launch" ]]; then
  [[ -f "$OWNER_MARKER" && -x "$WRAPPER/Contents/MacOS/Sikarugir" && -f "$STEAM_EXE" && -f "$PLIST" ]] \
    || fail "설치된 Windows Steam을 찾을 수 없습니다"
  configure_wrapper_plist "$PLIST"
  if steam_is_running; then
    if steam_ui_is_running; then
      open_steam_main || fail "Steam 창을 다시 열지 못했습니다"
      printf '@@STATE|running\n'
      message "Windows Steam 창을 앞으로 가져왔습니다"
      exit 0
    fi
    message "멈춘 Steam 시작을 정리하고 다시 여는 중입니다"
    stop_wrapper || fail "멈춘 Windows Steam을 정리하지 못했습니다"
  fi
  phase "launching"
  message "Windows Steam을 시작하고 있습니다"
  open_wrapper
  printf '@@STATE|running\n'
  message "Windows Steam 시작을 요청했습니다"
  exit 0
fi

if [[ "${1:-setup}" == "stop" ]]; then
  phase "stopping"
  message "Windows Steam과 실행 중인 Windows 게임을 종료하고 있습니다"
  [[ -x "$WRAPPER/Contents/MacOS/Sikarugir" ]] || fail "Windows Steam 실행기를 찾을 수 없습니다"
  stop_wrapper || fail "Windows Steam을 완전히 종료하지 못했습니다"
  printf '@@STATE|ready\n'
  message "Windows Steam을 완전히 종료했습니다"
  exit 0
fi

if [[ "${1:-setup}" == "list-games" ]]; then
  found=0
  if [[ -d "$STEAMAPPS" ]]; then
    while IFS= read -r manifest; do
      game="$(read_appmanifest "$manifest" 2>/dev/null || true)"
      [[ -n "$game" ]] || continue
      IFS='|' read -r app_id game_name install_dir <<< "$game"
      icon_path="$(find_game_icon "$LIBRARY_CACHE" "$app_id" 2>/dev/null || true)"
      printf '@@GAME|%s|%s|%s|%s\n' "$app_id" "$game_name" "$install_dir" "$icon_path"
      found=1
    done < <(/usr/bin/find "$STEAMAPPS" -maxdepth 1 -type f -name 'appmanifest_*.acf' -print | /usr/bin/sort)
  fi
  (( found == 1 )) || message "설치된 Windows Steam 게임이 없습니다"
  exit 0
fi

if [[ "${1:-setup}" == "create-shortcut" ]]; then
  app_id="${2:-}"
  [[ "$app_id" =~ ^[0-9]+$ ]] || fail "올바른 Steam 게임 ID가 아닙니다"
  manifest="$STEAMAPPS/appmanifest_${app_id}.acf"
  [[ -f "$manifest" ]] || fail "설치된 게임 정보를 찾을 수 없습니다"
  game="$(read_appmanifest "$manifest")" || fail "게임 정보를 읽지 못했습니다"
  IFS='|' read -r parsed_id game_name install_dir <<< "$game"
  [[ "$parsed_id" == "$app_id" ]] || fail "게임 ID가 설치 정보와 일치하지 않습니다"
  safe_name="$(printf '%s' "$game_name" | /usr/bin/tr '/:' '--')"
  shortcut="$GAME_SHORTCUTS_DIR/${safe_name}.app"
  [[ ! -L "$shortcut" ]] || fail "게임 바로가기 위치가 안전하지 않습니다"
  /bin/mkdir -p "$shortcut/Contents/MacOS" "$shortcut/Contents/Resources"
  /usr/bin/ditto "$SCRIPT_DIR/game_launcher.sh" "$shortcut/Contents/MacOS/GameLauncher"
  /bin/chmod +x "$shortcut/Contents/MacOS/GameLauncher"
  /usr/bin/sed "s/__STEAM_APP_ID__/$app_id/g" \
    "$SCRIPT_DIR/game_launch.bat.template" > "$shortcut/Contents/Resources/LaunchGame.bat"
  icon_path="$(find_game_icon "$LIBRARY_CACHE" "$app_id" 2>/dev/null || true)"
  has_game_icon=0
  if [[ -n "$icon_path" ]] && create_game_icns "$icon_path" "$shortcut/Contents/Resources/GameIcon.icns"; then
    has_game_icon=1
  fi
  plist="$shortcut/Contents/Info.plist"
  /usr/bin/plutil -create xml1 "$plist"
  /usr/bin/plutil -insert CFBundleExecutable -string GameLauncher "$plist"
  /usr/bin/plutil -insert CFBundleIdentifier -string "local.macsteam.game.${app_id}" "$plist"
  /usr/bin/plutil -insert CFBundleName -string "$game_name" "$plist"
  /usr/bin/plutil -insert CFBundlePackageType -string APPL "$plist"
  /usr/bin/plutil -insert CFBundleShortVersionString -string 1.1 "$plist"
  /usr/bin/plutil -insert CFBundleVersion -string 2 "$plist"
  /usr/bin/plutil -insert LSUIElement -bool true "$plist"
  /usr/bin/plutil -insert SteamAppID -string "$app_id" "$plist"
  if (( has_game_icon == 1 )); then
    /usr/bin/plutil -insert CFBundleIconFile -string GameIcon "$plist"
  fi
  /usr/bin/codesign --force --deep --sign - "$shortcut" >/dev/null
  printf '@@SHORTCUT|%s\n' "$shortcut"
  message "${game_name} 바로가기를 만들었습니다"
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
  open_wrapper
  progress 100 repairing
  printf '@@STATE|ready\n'
  message "로그인 화면을 복구했습니다. Steam이 다시 열렸습니다"
  exit 0
fi

acquire_setup_lock

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
  local label="$4"
  local base_percent="$5"
  local span_percent="$6"
  [[ ! -L "$destination" ]] || fail "다운로드 위치가 안전하지 않습니다: $(basename "$destination")"
  if [[ ! -s "$destination" ]]; then
    local partial total_bytes=0 curl_pid current_bytes=0 current_percent
    partial="$(/usr/bin/mktemp "${destination}.part.XXXXXX")"
    total_bytes="$(/usr/bin/curl --fail --silent --show-error --location --head "$url" 2>/dev/null \
      | /usr/bin/awk 'tolower($1) == "content-length:" { value=$2 } END { gsub("\\r", "", value); print value+0 }' || true)"
    /usr/bin/curl --fail --location --retry 3 --silent --show-error --output "$partial" "$url" &
    curl_pid=$!
    while /bin/kill -0 "$curl_pid" 2>/dev/null; do
      current_bytes="$(/usr/bin/stat -f %z "$partial" 2>/dev/null || printf '0')"
      if (( total_bytes > 0 )); then
        current_percent=$(( base_percent + (current_bytes * span_percent / total_bytes) ))
        (( current_percent > base_percent + span_percent )) && current_percent=$(( base_percent + span_percent ))
      else
        current_percent="$base_percent"
      fi
      progress "$current_percent" "$label"
      printf '@@DOWNLOAD|%s|%s|%s\n' "$label" "$current_bytes" "$total_bytes"
      /bin/sleep 0.25
    done
    if ! wait "$curl_pid"; then
      fail "다운로드에 실패했습니다: $label"
    fi
    /usr/bin/tar -tf "$partial" >/dev/null 2>&1 || fail "다운로드 파일 검증에 실패했습니다: $(basename "$destination")"
    [[ "$(/usr/bin/shasum -a 256 "$partial" | /usr/bin/awk '{print $1}')" == "$expected_sha" ]] \
      || fail "다운로드 파일의 고정 버전 검증에 실패했습니다: $(basename "$destination")"
    /bin/mv -n "$partial" "$destination"
  fi
  /usr/bin/tar -tf "$destination" >/dev/null 2>&1 || fail "다운로드 파일 검증에 실패했습니다: $(basename "$destination")"
  [[ "$(/usr/bin/shasum -a 256 "$destination" | /usr/bin/awk '{print $1}')" == "$expected_sha" ]] \
    || fail "캐시 파일이 검증된 고정 버전과 다릅니다: $(basename "$destination")"
  progress "$((base_percent + span_percent))" "$label"
  printf '@@DOWNLOAD|%s|%s|%s\n' "$label" "$(/usr/bin/stat -f %z "$destination")" "$(/usr/bin/stat -f %z "$destination")"
}

fetch "$ENGINE_URL" "$ENGINE_ARCHIVE" "$ENGINE_SHA256" "실행 엔진" 15 20
fetch "$TEMPLATE_URL" "$TEMPLATE_ARCHIVE" "$TEMPLATE_SHA256" "앱 틀" 35 10

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
progress 55 wrapper

LAUNCHER="$WRAPPER/Contents/MacOS/Sikarugir"
[[ -x "$LAUNCHER" ]] || fail "생성된 Sikarugir 실행 파일을 찾을 수 없습니다"

phase "windows"
message "Windows 실행 공간을 처음 한 번 준비하고 있습니다"
if [[ ! -d "$WRAPPER/Contents/drive_c/windows" ]]; then
  "$LAUNCHER" WSS-wineprefixcreate
fi
[[ -d "$WRAPPER/Contents/drive_c/Program Files (x86)" ]] || fail "Windows 실행 공간 생성에 실패했습니다"

progress 70 windows

phase "steam"
message "Windows Steam 설치 창이 열리면 기본 설정으로 설치해 주세요"
if [[ ! -f "$STEAM_EXE" ]]; then
  if [[ ! -s "$STEAM_SETUP" ]]; then
    partial_setup="$(/usr/bin/mktemp "${STEAM_SETUP}.part.XXXXXX")"
    /usr/bin/curl --fail --location --retry 3 --silent --show-error --output "$partial_setup" "$STEAM_URL"
    /bin/mv "$partial_setup" "$STEAM_SETUP"
  fi
  /usr/bin/file "$STEAM_SETUP" | /usr/bin/grep -q 'PE32 executable' || fail "Steam 설치 파일 검증에 실패했습니다"
  printf '@@ACTION|steam_installer\n'
  "$LAUNCHER" WSS-installer "$STEAM_SETUP" &
  installer_launcher_pid=$!
  installer_deadline=$((SECONDS + 1800))
  while /bin/kill -0 "$installer_launcher_pid" 2>/dev/null; do
    steam_exists=0
    installer_running=0
    [[ -f "$STEAM_EXE" ]] && steam_exists=1
    steam_installer_is_running && installer_running=1
    if [[ "$(installer_decision "$steam_exists" "$installer_running")" == "finish" ]]; then
      progress 88 steam
      message "Steam 설치를 확인했습니다. 첫 실행을 정리하고 최종 설정을 적용합니다"
      "$LAUNCHER" WSS-wineserverkill >/dev/null 2>&1 || true
      break
    fi
    (( SECONDS < installer_deadline )) || fail "Steam 설치 대기 시간이 초과됐습니다"
    /bin/sleep 1
  done
  for _ in {1..40}; do
    /bin/kill -0 "$installer_launcher_pid" 2>/dev/null || break
    /bin/sleep 0.25
  done
  if /bin/kill -0 "$installer_launcher_pid" 2>/dev/null; then
    /bin/kill -TERM "$installer_launcher_pid" 2>/dev/null || true
  fi
  wait "$installer_launcher_pid" 2>/dev/null || true
  [[ -f "$STEAM_EXE" ]] || fail "Steam 설치를 완료하지 못했습니다. 설치 경로는 기본값을 사용해 주세요"
fi

phase "configuring"
message "D3DMetal과 실행 설정을 자동으로 적용하고 있습니다"
[[ -f "$PLIST" ]] || fail "Steam 앱 설정 파일을 찾을 수 없습니다"
if [[ ! -f "$PLIST.original" ]]; then
  /usr/bin/ditto "$PLIST" "$PLIST.original"
fi
configure_wrapper_plist "$PLIST"
configure_steam_english

is_configured || fail "D3DMetal 설정 확인에 실패했습니다"

phase "ready"
message "준비가 끝났습니다. Windows Steam을 실행합니다"
open_wrapper
printf '@@STATE|running\n'
