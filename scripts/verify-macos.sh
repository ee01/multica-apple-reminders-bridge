#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "verify-macos.sh must run on macOS." >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROFILE="${MULTICA_PROFILE:-reminders-bridge}"
CLI="${MULTICA_CLI:-$(command -v multica || true)}"

swift test
"$ROOT/scripts/build-app.sh"

if [[ -z "$CLI" ]]; then
  echo "WARN: multica CLI not found. Install with: brew install multica-ai/tap/multica"
else
  "$CLI" version
  if "$CLI" auth status --profile "$PROFILE"; then
    "$CLI" workspace list --profile "$PROFILE" --output json >/tmp/multica-bridge-workspaces.json
    echo "Multica profile '$PROFILE' is authenticated."
  else
    echo "WARN: profile '$PROFILE' is not authenticated. Launch the app and click Connect Multica."
  fi
fi

cat <<'EOT'
Automated checks passed.

Manual macOS acceptance checks still required because TCC/iCloud cannot be validated on a non-interactive CI runner:
  1. Launch dist/Multica Reminders Bridge.app.
  2. Grant Reminders access.
  3. Click Create Test Reminder; confirm it appears in the "Multica Reviews" list and on iPhone via iCloud.
  4. With attention alarms enabled, confirm the test/new-review Reminder produces an Apple Reminders notification (subject to Focus/notification settings).
  5. Put a Multica test issue into in_review; click Sync now.
  6. Confirm exactly one Reminder is created and its URL opens the Multica issue.
  7. Move issue to in_progress; sync; confirm stale review Reminder is completed.
  8. Move issue back to in_review; sync; confirm a new review-cycle Reminder is created.
  9. Move issue to done; sync; confirm active Reminder is completed.
EOT
