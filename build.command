#!/bin/zsh
set -e

SCRIPT_DIR="${0:A:h}"
APP="$SCRIPT_DIR/build/Mac Steam Setup.app"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
/usr/bin/swiftc -swift-version 5 -parse-as-library \
  -framework SwiftUI -framework AppKit -framework Combine \
  "$SCRIPT_DIR/MacSteamSetupApp.swift" \
  -o "$APP/Contents/MacOS/MacSteamSetup"
/usr/bin/ditto "$SCRIPT_DIR/Info.plist" "$APP/Contents/Info.plist"
/usr/bin/ditto "$SCRIPT_DIR/Resources/setup.sh" "$APP/Contents/Resources/setup.sh"
/usr/bin/ditto "$SCRIPT_DIR/Resources/setup_core.sh" "$APP/Contents/Resources/setup_core.sh"
/usr/bin/ditto "$SCRIPT_DIR/Resources/game_launcher.sh" "$APP/Contents/Resources/game_launcher.sh"
/usr/bin/ditto "$SCRIPT_DIR/Resources/game_launch.bat.template" "$APP/Contents/Resources/game_launch.bat.template"
/usr/bin/ditto "$SCRIPT_DIR/LICENSE" "$APP/Contents/Resources/LICENSE"
/usr/bin/ditto "$SCRIPT_DIR/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
/bin/chmod +x "$APP/Contents/Resources/setup.sh"
/usr/bin/codesign --force --deep --sign - "$APP"
echo "완료: $APP"
