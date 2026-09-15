#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is required to read package.json version." >&2
  exit 1
fi

VERSION="$(node -p "require('./package.json').version")"
PLIST="$ROOT/resources/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$PLIST"
echo "Synced CFBundleShortVersionString to ${VERSION} in resources/Info.plist"
