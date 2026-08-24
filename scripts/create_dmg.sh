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
cleanup() {
  /bin/rm -rf "$work_dir"
}
trap cleanup EXIT

staging_dir="$work_dir/staging"
/bin/mkdir -p "$staging_dir"
/usr/bin/ditto "$app_path" "$staging_dir/Mac Steam Setup.app"
/bin/ln -s /Applications "$staging_dir/Applications"

hybrid_base="$work_dir/image"
/usr/bin/hdiutil makehybrid \
  -udf \
  -udf-version 1.02 \
  -udf-volume-name "$volume_name" \
  -o "$hybrid_base" \
  -ov \
  "$staging_dir"
/usr/bin/ditto "$hybrid_base.iso" "$output_dmg"
