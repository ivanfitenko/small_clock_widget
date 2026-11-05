#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="SmallClockWidget"
APP_DIR="$APP_NAME.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

swiftc -O ClockWidget/main.swift -o "$APP_DIR/Contents/MacOS/$APP_NAME"
cp ClockWidget/Info.plist "$APP_DIR/Contents/Info.plist"

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Built $APP_DIR"
echo "Launch with: open $APP_DIR"

if [[ "${1:-}" == "--install-login-item" ]]; then
    PLIST_NAME="local.smallclockwidget.plist"
    DEST="$HOME/Library/LaunchAgents/$PLIST_NAME"

    APP_EXECUTABLE="$(pwd)/$APP_DIR/Contents/MacOS/$APP_NAME"

    mkdir -p "$HOME/Library/LaunchAgents"
    sed "s|__APP_EXECUTABLE__|$APP_EXECUTABLE|" "$PLIST_NAME" > "$DEST"

    UID_NUM="$(id -u)"
    launchctl bootout "gui/$UID_NUM/local.smallclockwidget" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$UID_NUM" "$DEST"

    echo "Installed login item: $DEST"
    echo "Widget will now launch automatically at login."
fi
