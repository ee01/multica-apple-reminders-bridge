#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "deploy.sh must run on macOS to build and package the app." >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is required to read package.json version." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required. Install: https://cli.github.com/" >&2
  exit 1
fi

VERSION="$(node -p "require('./package.json').version")"
TAG="v${VERSION}"
APP_NAME="Multica Reminders Bridge"
APP_DIR="$ROOT/dist/${APP_NAME}.app"
ZIP_NAME="Multica-Reminders-Bridge-v${VERSION}-macos.zip"
ZIP_PATH="$ROOT/dist/${ZIP_NAME}"
PLIST="$ROOT/resources/Info.plist"

sync_version() {
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$PLIST"
}

extract_release_notes() {
  awk -v ver="$VERSION" '
    $0 ~ "^## " ver " " { found = 1; next }
    found && /^## / { exit }
    found { print }
  ' "$ROOT/CHANGELOG.md" | sed '/./,$!d'
}

echo "==> Syncing app version to ${VERSION}"
sync_version

can_run_tests() {
  xcode-select -p 2>/dev/null | grep -q "Xcode.app" || return 1
  swift test --list-tests >/dev/null 2>&1
}

if [[ "${SKIP_TESTS:-}" == "1" ]]; then
  echo "==> Skipping tests (SKIP_TESTS=1)"
elif can_run_tests; then
  echo "==> Running tests"
  swift test
else
  echo "==> Skipping tests (full Xcode required for XCTest)"
fi

echo "==> Building macOS app"
./scripts/build-app.sh

echo "==> Packaging ${ZIP_NAME}"
mkdir -p "$ROOT/dist"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
echo "Created ${ZIP_PATH}"

NOTES="$(extract_release_notes)"
if [[ -z "$NOTES" ]]; then
  echo "No CHANGELOG section found for ${VERSION}. Add an entry under '## ${VERSION} - ...'." >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree has uncommitted changes. Commit before publishing ${TAG}." >&2
  git status --short
  exit 1
fi

CURRENT_BRANCH="$(git branch --show-current)"
if [[ "$CURRENT_BRANCH" != "main" ]]; then
  echo "Expected branch 'main', got '${CURRENT_BRANCH}'." >&2
  exit 1
fi

echo "==> Pushing commits"
git push origin HEAD

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "==> Tag ${TAG} already exists locally"
else
  echo "==> Creating tag ${TAG}"
  git tag -a "$TAG" -m "Release ${TAG}"
fi

echo "==> Pushing tag ${TAG}"
git push origin "$TAG"

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "==> Updating existing GitHub release ${TAG}"
  gh release upload "$TAG" "$ZIP_PATH" --clobber
else
  echo "==> Creating GitHub release ${TAG}"
  gh release create "$TAG" "$ZIP_PATH" \
    --title "$TAG" \
    --notes "$NOTES"
fi

echo "==> Published ${TAG}"
gh release view "$TAG" --web 2>/dev/null || gh release view "$TAG"
