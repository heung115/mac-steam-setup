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
  if /usr/bin/plutil -extract "$key" raw "$plist" >/dev/null 2>&1; then
    /usr/bin/plutil -replace "$key" "-$type" "$value" "$plist"
  else
    /usr/bin/plutil -insert "$key" "-$type" "$value" "$plist"
  fi
}

configure_wrapper_plist() {
  local plist="$1"
  plist_set "$plist" D3DMETAL integer 1
  plist_set "$plist" 'Program Name and Path' string '/Program Files (x86)/Steam/Steam.exe'
  plist_set "$plist" 'Program Flags' string ''
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
  printf '%s|%s|%s\n' "$app_id" "$name" "$install_dir"
}
