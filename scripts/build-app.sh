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
  IDENTITY="$("$ROOT/scripts/resolve-sign-identity.sh")"
  if [[ "$IDENTITY" == "skip" ]]; then
    echo "Skipping codesign (SKIP_CODESIGN=1)." >&2
  else
    codesign --force --deep --sign "$IDENTITY" "$APP_DIR"
    if [[ "$IDENTITY" == "-" ]]; then
      cat >&2 <<'EOF'
Signed with ad-hoc identity. macOS ties Reminders access to the app signature,
so you may need to re-authorize after each rebuild. For stable local permissions,
sign in to Xcode once and rebuild, or set SIGN_IDENTITY to your development cert.
EOF
    elif [[ -n "${SIGN_IDENTITY:-}" ]]; then
      echo "Signed with SIGN_IDENTITY: $IDENTITY" >&2
    else
      echo "Signed with detected certificate: $IDENTITY" >&2
      echo "Reminders permission should persist across make install rebuilds." >&2
    fi
  fi
fi

plutil -lint "$CONTENTS/Info.plist"
echo "$APP_DIR"
