#!/bin/bash
# PROTOTYPE — CC0-derived orchestration based on:
# https://github.com/mirpo/windows-steam-on-apple-silicon
# Downloads third-party components from their official distribution URLs.

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=setup_core.sh
source "$SCRIPT_DIR/setup_core.sh"
# shellcheck source=localization.sh
source "$SCRIPT_DIR/localization.sh"

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
STEAM_CLIENT_DLL="$WRAPPER/Contents/drive_c/Program Files (x86)/Steam/steamclient.dll"
PLIST="$WRAPPER/Contents/Info.plist"
OWNER_MARKER="$WRAPPER/Contents/.macsteamsetup-owner"
HTML_CACHE="$WRAPPER/Contents/drive_c/users/$USER/AppData/Local/Steam/htmlcache"
PREFIX_ROOT="$WRAPPER/Contents/SharedSupport/prefix"
LOCK_DIR="$APP_CACHE/setup.lock"
STEAMAPPS="$WRAPPER/Contents/drive_c/Program Files (x86)/Steam/steamapps"
LIBRARY_CACHE="$WRAPPER/Contents/drive_c/Program Files (x86)/Steam/appcache/librarycache"
GAME_SHORTCUTS_DIR="$HOME/Applications/Windows Steam Games"
SHORTCUT_OWNER_TEXT="MacSteamSetup game shortcut owner v1"

progress() { printf '@@PROGRESS|%s|%s\n' "$1" "${2:-}"; }
phase() {
  printf '@@PHASE|%s\n' "$1"
  progress "$(phase_percent "$1")" "$1"
}
message() { printf '@@MESSAGE|%s\n' "$1"; }
fail() { printf '@@ERROR|%s\n' "$1" >&2; exit 1; }
message_key() {
  local key="$1"
  shift
  message "$(ui_text "$key" "$@")"
}
fail_key() {
  local key="$1"
  shift
  fail "$(ui_text "$key" "$@")"
}

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

steam_process_candidates() {
  /bin/ps -axo pid=,command= | /usr/bin/awk '
    {
      pid=$1
      $1=""
      sub(/^[[:space:]]+/, "", $0)
      command=tolower($0)
      if (command ~ /^[a-z]:\\/) print pid
    }
  '
}

process_belongs_to_wrapper() {
  local pid="$1"
  local contents_path
  contents_path="$(cd "$WRAPPER/Contents" && pwd -P)/"
  /usr/sbin/lsof -a -p "$pid" -d cwd,txt -Fn 2>/dev/null \
    | /usr/bin/grep -Fq "n$contents_path"
}

steam_process_pids() {
  local pid
  while IFS= read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    process_belongs_to_wrapper "$pid" && printf '%s\n' "$pid"
  done < <(steam_process_candidates)
}

wrapper_has_named_process() {
  local process_name
  local contents_path
  local lsof_args=(-a -d cwd -Fn)
  contents_path="$(cd "$WRAPPER/Contents" && pwd -P)/"
  for process_name in "$@"; do
    lsof_args+=(-c "$process_name")
  done
  /usr/sbin/lsof "${lsof_args[@]}" 2>/dev/null \
    | /usr/bin/grep -Fq "n$contents_path"
}

steam_client_is_running() {
  wrapper_has_named_process Steam.exe steamwebhelper steamservice \
    || [[ -n "$(steam_process_pids)" ]]
}

steam_runtime_is_running() {
  steam_is_running || steam_client_is_running
}

steam_ui_is_running() {
  wrapper_has_named_process steamwebhelper
}

shortcut_is_owned() {
  local shortcut="$1"
  local app_id="$2"
  local marker="$shortcut/Contents/.macsteamsetup-shortcut-owner"
  local plist="$shortcut/Contents/Info.plist"
  [[ -f "$marker" && "$(<"$marker")" == "$SHORTCUT_OWNER_TEXT" ]] && return 0
  [[ -f "$plist" && -x "$shortcut/Contents/MacOS/GameLauncher" ]] || return 1
  [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$plist" 2>/dev/null || true)" \
      == "local.macsteam.game.${app_id}" ]] || return 1
  [[ "$(/usr/bin/plutil -extract SteamAppID raw "$plist" 2>/dev/null || true)" == "$app_id" ]]
}

terminate_orphaned_steam_processes() {
  local pids pid
  pids="$(steam_process_pids)"
  [[ -n "$pids" ]] || return 0

  while IFS= read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] && /bin/kill -TERM "$pid" 2>/dev/null || true
  done <<< "$pids"
  for _ in {1..20}; do
    pids="$(steam_process_pids)"
    [[ -z "$pids" ]] && return 0
    /bin/sleep 0.25
  done

  while IFS= read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] && /bin/kill -KILL "$pid" 2>/dev/null || true
  done <<< "$pids"
  for _ in {1..20}; do
    [[ -z "$(steam_process_pids)" ]] && return 0
    /bin/sleep 0.25
  done
  return 1
}

stop_wrapper() {
  "$WRAPPER/Contents/MacOS/Sikarugir" WSS-wineserverkill >/dev/null 2>&1 || true
  terminate_orphaned_steam_processes || return 1
  for _ in {1..20}; do
    if ! steam_is_running && ! steam_client_is_running; then
      return 0
    fi
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

steam_install_is_complete() {
  [[ -f "$STEAM_EXE" && -f "$STEAM_CLIENT_DLL" ]]
}

steam_setup_is_valid() {
  local installer="$1"
  local size
  [[ -f "$installer" && ! -L "$installer" ]] || return 1
  size="$(/usr/bin/stat -f %z "$installer" 2>/dev/null || printf '0')"
  (( size >= 1048576 )) || return 1
  /usr/bin/file "$installer" | /usr/bin/grep -Eq 'PE32(\+)? executable'
}

configure_steam_english() {
  local wine="$WRAPPER/Contents/SharedSupport/wine/bin/wine"
  local prefix="$WRAPPER/Contents/SharedSupport/prefix"
  [[ -x "$wine" && -d "$prefix" ]] || fail_key steam_language_environment_missing
  (
    export WINEPREFIX="$prefix"
    export DYLD_FALLBACK_LIBRARY_PATH="$WRAPPER/Contents/Frameworks/moltenvkcx:$WRAPPER/Contents/SharedSupport/wine/lib:$WRAPPER/Contents/SharedSupport/wine/lib64:$WRAPPER/Contents/Frameworks:$WRAPPER/Contents/Frameworks/GStreamer.framework/Libraries:/opt/wine/lib:/usr/lib:/usr/libexec:/usr/lib/system"
    "$wine" reg add 'HKCU\Software\Valve\Steam' /v Language /t REG_SZ /d english /f >/dev/null 2>&1
    "$wine" reg add 'HKLM\Software\Wow6432Node\Valve\Steam' /v Language /t REG_SZ /d english /f >/dev/null 2>&1
    "$wine" reg add 'HKLM\Software\Wow6432Node\Valve\Steam\NSIS' /v InstallerLanguage /t REG_SZ /d 1033 /f >/dev/null 2>&1
  ) || fail_key steam_language_config_failed
  "$WRAPPER/Contents/MacOS/Sikarugir" WSS-wineserverkill >/dev/null 2>&1 || true
}

acquire_setup_lock() {
  /bin/mkdir -p "$APP_CACHE"
  [[ ! -L "$LOCK_DIR" ]] || fail_key unsafe_lock_path
  if ! /bin/mkdir "$LOCK_DIR" 2>/dev/null; then
    local old_pid=""
    [[ -f "$LOCK_DIR/pid" ]] && old_pid="$(<"$LOCK_DIR/pid")"
    if [[ "$old_pid" =~ ^[0-9]+$ ]] && /bin/kill -0 "$old_pid" 2>/dev/null; then
      fail_key installation_already_running
    fi
    /bin/rm -f "$LOCK_DIR/pid"
    /bin/rmdir "$LOCK_DIR" 2>/dev/null || fail_key stale_lock_cleanup_failed
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
  if steam_install_is_complete && is_configured; then
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
  [[ -f "$OWNER_MARKER" && -x "$WRAPPER/Contents/MacOS/Sikarugir" \
      && -f "$STEAM_EXE" && -f "$STEAM_CLIENT_DLL" && -f "$PLIST" ]] \
    || fail_key installed_steam_not_found
  configure_wrapper_plist "$PLIST"
  if steam_runtime_is_running; then
    if steam_ui_is_running; then
      open_steam_main || fail_key steam_window_reopen_failed
      printf '@@STATE|running\n'
      message_key steam_window_foregrounded
      exit 0
    fi
    message_key steam_stalled_restarting
    stop_wrapper || fail_key steam_stalled_cleanup_failed
  fi
  phase "launching"
  message_key steam_starting
  open_wrapper
  printf '@@STATE|running\n'
  message_key steam_start_requested
  exit 0
fi

if [[ "${1:-setup}" == "stop" ]]; then
  phase "stopping"
  message_key steam_stopping
  [[ -x "$WRAPPER/Contents/MacOS/Sikarugir" ]] || fail_key steam_launcher_not_found
  stop_wrapper || fail_key steam_stop_failed
  printf '@@STATE|ready\n'
  message_key steam_stopped
  exit 0
fi

if [[ "${1:-setup}" == "list-games" ]]; then
  found=0
  if [[ -d "$STEAMAPPS" ]]; then
    while IFS= read -r manifest; do
      game="$(read_appmanifest "$manifest" 2>/dev/null || true)"
      [[ -n "$game" ]] || continue
      IFS='|' read -r app_id encoded_name encoded_install_dir <<< "$game"
      [[ "$app_id" =~ ^[0-9]+$ ]] || continue
      icon_path="$(find_game_icon "$LIBRARY_CACHE" "$app_id" 2>/dev/null || true)"
      printf '@@GAME64|%s|%s|%s|%s\n' \
        "$app_id" "$encoded_name" "$encoded_install_dir" "$(protocol_encode "$icon_path")"
      found=1
    done < <(/usr/bin/find "$STEAMAPPS" -maxdepth 1 -type f -name 'appmanifest_*.acf' -print | /usr/bin/sort)
  fi
  (( found == 1 )) || message_key no_installed_games
  exit 0
fi

if [[ "${1:-setup}" == "create-shortcut" ]]; then
  app_id="${2:-}"
  [[ "$app_id" =~ ^[0-9]+$ ]] || fail_key invalid_game_id
  manifest="$STEAMAPPS/appmanifest_${app_id}.acf"
  [[ -f "$manifest" ]] || fail_key game_info_not_found
  game="$(read_appmanifest "$manifest")" || fail_key game_info_read_failed
  IFS='|' read -r parsed_id encoded_name encoded_install_dir <<< "$game"
  [[ "$parsed_id" == "$app_id" ]] || fail_key game_id_mismatch
  game_name="$(protocol_decode "$encoded_name")" || fail_key game_name_read_failed
  install_dir="$(protocol_decode "$encoded_install_dir")" || fail_key game_install_read_failed
  safe_name="$(printf '%s' "$game_name" | /usr/bin/tr '/:\r\n\t' '-----')"
  shortcut="$GAME_SHORTCUTS_DIR/${safe_name}.app"
  [[ ! -L "$shortcut" ]] || fail_key unsafe_shortcut_path
  if [[ -e "$shortcut" ]] && ! shortcut_is_owned "$shortcut" "$app_id"; then
    fail_key shortcut_conflict "${safe_name}.app"
  fi
  /bin/mkdir -p "$shortcut/Contents/MacOS" "$shortcut/Contents/Resources"
  printf '%s\n' "$SHORTCUT_OWNER_TEXT" > "$shortcut/Contents/.macsteamsetup-shortcut-owner"
  /usr/bin/ditto "$SCRIPT_DIR/game_launcher.sh" "$shortcut/Contents/MacOS/GameLauncher"
  /usr/bin/ditto "$SCRIPT_DIR/localization.sh" "$shortcut/Contents/Resources/localization.sh"
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
  message_key shortcut_created "$game_name"
  exit 0
fi

if [[ "${1:-setup}" == "repair" ]]; then
  phase "repairing"
  message_key repairing_login
  [[ -f "$OWNER_MARKER" && -x "$WRAPPER/Contents/MacOS/Sikarugir" ]] \
    || fail_key owned_wrapper_not_found
  if [[ -e "$HTML_CACHE" || -L "$HTML_CACHE" ]]; then
    [[ ! -L "$HTML_CACHE" ]] \
      && path_parent_resolves_within "$PREFIX_ROOT" "$HTML_CACHE" \
      || fail_key unsafe_html_cache
  fi
  "$WRAPPER/Contents/MacOS/Sikarugir" WSS-wineserverkill >/dev/null 2>&1 || true
  if [[ -e "$HTML_CACHE" ]]; then
    /bin/rm -rf "$HTML_CACHE"
  fi
  open_wrapper
  progress 100 repairing
  printf '@@STATE|ready\n'
  message_key login_repaired
  exit 0
fi

acquire_setup_lock

phase "checking"
message_key checking_requirements
[[ "$(uname -m)" == "arm64" ]] || fail_key apple_silicon_required
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
(( MACOS_MAJOR >= 14 )) || fail_key macos_14_required
if ! /usr/sbin/pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
  phase "rosetta"
  message_key installing_rosetta
  /usr/sbin/softwareupdate --install-rosetta --agree-to-license \
    || fail_key rosetta_install_failed
fi
/usr/sbin/pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1 \
  || fail_key rosetta_verify_failed
FREE_GB="$(df -g "$HOME" | awk 'NR==2 {print $4}')"
(( FREE_GB >= 5 )) || fail_key disk_space_required

phase "downloading"
message_key downloading_components
mkdir -p "$CACHE/Engines" "$CACHE/Template" "$APP_CACHE" "$HOME/Applications/Sikarugir"

fetch() {
  local url="$1"
  local destination="$2"
  local expected_sha="$3"
  local label="$4"
  local base_percent="$5"
  local span_percent="$6"
  [[ ! -L "$destination" ]] || fail_key unsafe_download_path "$(basename "$destination")"
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
      fail_key download_failed "$label"
    fi
    /usr/bin/tar -tf "$partial" >/dev/null 2>&1 \
      || fail_key download_validation_failed "$(basename "$destination")"
    [[ "$(/usr/bin/shasum -a 256 "$partial" | /usr/bin/awk '{print $1}')" == "$expected_sha" ]] \
      || fail_key pinned_download_mismatch "$(basename "$destination")"
    /bin/mv -n "$partial" "$destination"
  fi
  /usr/bin/tar -tf "$destination" >/dev/null 2>&1 \
    || fail_key download_validation_failed "$(basename "$destination")"
  [[ "$(/usr/bin/shasum -a 256 "$destination" | /usr/bin/awk '{print $1}')" == "$expected_sha" ]] \
    || fail_key cached_download_mismatch "$(basename "$destination")"
  progress "$((base_percent + span_percent))" "$label"
  printf '@@DOWNLOAD|%s|%s|%s\n' "$label" "$(/usr/bin/stat -f %z "$destination")" "$(/usr/bin/stat -f %z "$destination")"
}

fetch "$ENGINE_URL" "$ENGINE_ARCHIVE" "$ENGINE_SHA256" "$(ui_text runtime_engine)" 15 20
fetch "$TEMPLATE_URL" "$TEMPLATE_ARCHIVE" "$TEMPLATE_SHA256" "$(ui_text app_template)" 35 10

phase "wrapper"
message_key creating_wrapper
[[ ! -L "$WRAPPER" ]] || fail_key unsafe_wrapper_path
if [[ -d "$WRAPPER" && ! -f "$OWNER_MARKER" ]]; then
  fail_key unowned_wrapper
fi
if [[ ! -d "$WRAPPER" ]]; then
  install_wrapper_atomically \
    "$TEMPLATE_ARCHIVE" "$ENGINE_ARCHIVE" "$TEMPLATE" "$WRAPPER" "$APP_CACHE" \
    || fail_key wrapper_create_failed
fi
progress 55 wrapper

LAUNCHER="$WRAPPER/Contents/MacOS/Sikarugir"
[[ -x "$LAUNCHER" ]] || fail_key generated_launcher_missing

phase "windows"
message_key preparing_windows
if [[ ! -d "$WRAPPER/Contents/drive_c/windows" ]]; then
  "$LAUNCHER" WSS-wineprefixcreate
fi
[[ -d "$WRAPPER/Contents/drive_c/Program Files (x86)" ]] || fail_key windows_environment_failed

progress 70 windows

phase "steam"
message_key steam_installer_instruction
if ! steam_install_is_complete; then
  [[ ! -L "$STEAM_SETUP" ]] || fail_key unsafe_steam_setup_symlink
  [[ ! -d "$STEAM_SETUP" ]] || fail_key unsafe_steam_setup_directory
  if ! steam_setup_is_valid "$STEAM_SETUP"; then
    partial_setup="$(/usr/bin/mktemp "${STEAM_SETUP}.part.XXXXXX")"
    /usr/bin/curl --fail --location --retry 3 --silent --show-error --output "$partial_setup" "$STEAM_URL"
    steam_setup_is_valid "$partial_setup" || fail_key steam_setup_validation_failed
    /bin/mv "$partial_setup" "$STEAM_SETUP"
  fi
  printf '@@ACTION|steam_installer\n'
  "$LAUNCHER" WSS-installer "$STEAM_SETUP" &
  installer_launcher_pid=$!
  installer_deadline=$((SECONDS + 1800))
  while /bin/kill -0 "$installer_launcher_pid" 2>/dev/null; do
    steam_exists=0
    installer_running=0
    steam_install_is_complete && steam_exists=1
    steam_installer_is_running && installer_running=1
    if [[ "$(installer_decision "$steam_exists" "$installer_running")" == "finish" ]]; then
      progress 88 steam
      message_key steam_install_confirmed
      "$LAUNCHER" WSS-wineserverkill >/dev/null 2>&1 || true
      break
    fi
    (( SECONDS < installer_deadline )) || fail_key steam_install_timeout
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
  steam_install_is_complete \
    || fail_key steam_install_failed
fi

phase "configuring"
message_key applying_configuration
[[ -f "$PLIST" ]] || fail_key steam_plist_missing
if [[ ! -f "$PLIST.original" ]]; then
  /usr/bin/ditto "$PLIST" "$PLIST.original"
fi
configure_wrapper_plist "$PLIST"
configure_steam_english

is_configured || fail_key d3dmetal_verify_failed

phase "ready"
message_key ready_to_launch
open_wrapper
printf '@@STATE|running\n'
