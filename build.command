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
/bin/chmod +x "$APP/Contents/Resources/setup.sh"
/usr/bin/codesign --force --deep --sign - "$APP"
echo "완료: $APP"
