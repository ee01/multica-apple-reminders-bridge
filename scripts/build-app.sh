#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "build-app.sh must run on macOS because the app links EventKit/AppKit." >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$ROOT/dist/Multica Reminders Bridge.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN_DIR/MulticaRemindersBridge" "$MACOS/MulticaRemindersBridge"
cp "$ROOT/resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
chmod +x "$MACOS/MulticaRemindersBridge"

if command -v codesign >/dev/null 2>&1; then
  IDENTITY="${SIGN_IDENTITY:--}"
  codesign --force --deep --sign "$IDENTITY" "$APP_DIR"
fi

plutil -lint "$CONTENTS/Info.plist"
echo "$APP_DIR"
