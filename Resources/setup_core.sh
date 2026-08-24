#!/bin/bash

phase_percent() {
  case "$1" in
    checking) printf '5\n' ;;
    rosetta) printf '10\n' ;;
    downloading) printf '15\n' ;;
    wrapper) printf '45\n' ;;
    windows) printf '60\n' ;;
    steam) printf '72\n' ;;
    configuring) printf '92\n' ;;
    repairing) printf '50\n' ;;
    launching) printf '70\n' ;;
    stopping) printf '70\n' ;;
    ready) printf '100\n' ;;
    *) printf '0\n' ;;
  esac
}

installer_decision() {
  local steam_exists="$1"
  local installer_running="$2"
  if [[ "$steam_exists" == "1" && "$installer_running" == "0" ]]; then
    printf 'finish\n'
  else
    printf 'wait\n'
  fi
}

wrapper_launcher_is_running_in() {
  local launcher="$1"
  /usr/bin/awk -v launcher="$launcher" '
    index($0, launcher) == 1 { found=1 }
    END { exit(found ? 0 : 1) }
  '
}

plist_set() {
  local plist="$1"
  local key="$2"
  local type="$3"
  local value="$4"
  local current
  if current="$(/usr/bin/plutil -extract "$key" raw "$plist" 2>/dev/null)"; then
    if [[ "$current" == "$value" ]]; then
      return 0
    fi
    /usr/bin/plutil -replace "$key" "-$type" "$value" "$plist"
  else
    /usr/bin/plutil -insert "$key" "-$type" "$value" "$plist"
  fi
}

configure_wrapper_plist() {
  local plist="$1"
  plist_set "$plist" D3DMETAL integer 1
  plist_set "$plist" 'Program Name and Path' string '/Program Files (x86)/Steam/Steam.exe'
  plist_set "$plist" 'Program Flags' string '-nobootstrapupdate -skipinitialbootstrap'
  plist_set "$plist" 'Skip Gecko' integer 1
  plist_set "$plist" 'Skip Mono' integer 1
  plist_set "$plist" LSUIElement bool true
}

acf_value() {
  local manifest="$1"
  local key="$2"
  /usr/bin/awk -F '"' -v wanted="$key" '$2 == wanted { print $4; exit }' "$manifest"
}

read_appmanifest() {
  local manifest="$1"
  local app_id name install_dir
  app_id="$(acf_value "$manifest" appid)"
  name="$(acf_value "$manifest" name)"
  install_dir="$(acf_value "$manifest" installdir)"
  [[ -n "$app_id" && -n "$name" ]] || return 1
  printf '%s|%s|%s\n' "$app_id" "$(protocol_encode "$name")" "$(protocol_encode "$install_dir")"
}

protocol_encode() {
  printf '%s' "$1" | /usr/bin/base64 | /usr/bin/tr -d '\r\n'
}

protocol_decode() {
  printf '%s' "$1" | /usr/bin/base64 -D
}

path_parent_resolves_within() {
  local root="$1"
  local target="$2"
  local root_path parent_path
  [[ -d "$root" ]] || return 1
  parent_path="${target%/*}"
  [[ -d "$parent_path" ]] || return 1
  root_path="$(cd "$root" && pwd -P)" || return 1
  parent_path="$(cd "$parent_path" && pwd -P)" || return 1
  [[ "$parent_path" == "$root_path" || "$parent_path" == "$root_path/"* ]]
}

install_wrapper_atomically() {
  local template_archive="$1"
  local engine_archive="$2"
  local template_name="$3"
  local wrapper="$4"
  local work_root="$5"
  local stage staged_wrapper

  [[ ! -e "$wrapper" && ! -L "$wrapper" ]] || return 1
  /bin/mkdir -p "$work_root" || return 1
  stage="$(/usr/bin/mktemp -d "$work_root/wrapper.XXXXXX")" || return 1
  staged_wrapper="$stage/${template_name}.app"

  if ! /usr/bin/tar -xf "$template_archive" -C "$stage" \
    || [[ ! -d "$staged_wrapper/Contents/SharedSupport" ]] \
    || ! /usr/bin/tar -xf "$engine_archive" -C "$staged_wrapper/Contents/SharedSupport" \
    || [[ ! -d "$staged_wrapper/Contents/SharedSupport/wswine.bundle" ]] \
    || ! /bin/mv "$staged_wrapper/Contents/SharedSupport/wswine.bundle" \
      "$staged_wrapper/Contents/SharedSupport/wine"; then
    /bin/rm -rf "$stage"
    return 1
  fi

  printf 'MacSteamSetup prototype owner v1\n' > \
    "$staged_wrapper/Contents/.macsteamsetup-owner" || {
      /bin/rm -rf "$stage"
      return 1
    }
  if [[ -e "$wrapper" || -L "$wrapper" ]] || ! /bin/mv "$staged_wrapper" "$wrapper"; then
    /bin/rm -rf "$stage"
    return 1
  fi
  /bin/rmdir "$stage" 2>/dev/null || true
}

find_game_icon() {
  local cache_root="$1"
  local app_id="$2"
  local candidate filename
  [[ "$app_id" =~ ^[0-9]+$ && -d "$cache_root/$app_id" ]] || return 1
  while IFS= read -r candidate; do
    filename="${candidate##*/}"
    if [[ "$filename" =~ ^[[:xdigit:]]{40}\.jpg$ ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(/usr/bin/find "$cache_root/$app_id" -maxdepth 1 -type f -name '*.jpg' -print | /usr/bin/sort)
  return 1
}
