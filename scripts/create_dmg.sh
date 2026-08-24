#!/bin/bash
set -euo pipefail

app_path="${1:?Usage: create_dmg.sh APP_PATH OUTPUT_DMG}"
output_dmg="${2:?Usage: create_dmg.sh APP_PATH OUTPUT_DMG}"
volume_name="${3:-Mac Steam Setup}"

[[ -d "$app_path" ]] || {
  printf 'App bundle not found: %s\n' "$app_path" >&2
  exit 1
}

work_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/macsteam-dmg.XXXXXX")"
mount_dir="$work_dir/mount"
mounted=0
cleanup() {
  if [[ "$mounted" == "1" ]]; then
    /usr/bin/hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
  fi
  /bin/rm -rf "$work_dir"
}
trap cleanup EXIT

app_size_kb="$(/usr/bin/du -sk "$app_path" | /usr/bin/awk '{print $1}')"
image_size_mb="$((app_size_kb / 1024 + 32))"
writable_image="$work_dir/writable.dmg"
/bin/mkdir -p "$mount_dir" "$(/usr/bin/dirname "$output_dmg")"

/usr/bin/hdiutil create \
  -size "${image_size_mb}m" \
  -fs HFS+ \
  -volname "$volume_name" \
  -type UDIF \
  -ov \
  "$writable_image"

/usr/bin/hdiutil attach \
  -readwrite \
  -nobrowse \
  -noautoopen \
  -noverify \
  -mountpoint "$mount_dir" \
  "$writable_image"
mounted=1

/usr/bin/ditto "$app_path" "$mount_dir/Mac Steam Setup.app"
/bin/ln -s /Applications "$mount_dir/Applications"
/bin/sync

/usr/bin/hdiutil detach "$mount_dir"
mounted=0

/usr/bin/hdiutil convert \
  "$writable_image" \
  -format UDZO \
  -o "$output_dmg" \
  -ov
