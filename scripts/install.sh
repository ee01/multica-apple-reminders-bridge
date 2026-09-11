#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build-app.sh"
TARGET_BASE="${INSTALL_DIR:-$HOME/Applications}"
mkdir -p "$TARGET_BASE"
rm -rf "$TARGET_BASE/Multica Reminders Bridge.app"
cp -R "$ROOT/dist/Multica Reminders Bridge.app" "$TARGET_BASE/"
echo "Installed to $TARGET_BASE/Multica Reminders Bridge.app"
open "$TARGET_BASE/Multica Reminders Bridge.app"
