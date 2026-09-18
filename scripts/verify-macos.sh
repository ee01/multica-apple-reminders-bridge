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
  1. Launch dist/Multica Reminders Bridge.app and grant Reminders access once.
     For repeated local installs, sign with a stable Apple Development cert (see docs/INSTALLATION.md)
     so macOS does not treat each rebuild as a new app.
  2. Connect the `reminders-bridge` Multica CLI profile and choose a real Workspace/default Agent.
  3. Sync once; confirm `Agent Requests` and configured Project Route Lists are automatically created when missing.
  4. Create an Apple request; confirm the original Reminder becomes the Main projection and a Multica Issue/Run is created.
  5. Put the Issue in `in_review` with no active Run; sync; confirm exactly one Review sibling appears in the same List and receives an alarm.
  6. Mark that Review sibling complete in Apple Reminders; confirm Bridge changes the still-current Multica Issue to `done`, then completes Main.
  7. On a separate test Issue, Request Changes directly in Multica; confirm an active rework Run resolves the old Review sibling even if Issue status is briefly stale `in_review`; after re-delivery confirm a new Review generation appears.
  8. Put a test Issue in `blocked` past the grace period; confirm an Action Required sibling appears. Mark it complete and confirm Multica status is NOT changed. Resolve/retrigger the Issue in Multica and confirm the sibling is reconciled.
  9. Produce a terminal failed Run with no newer active retry; confirm a Failed sibling appears with its failure reason. Mark it complete and confirm no Multica retry/status mutation occurs.
 10. Confirm a failed snapshot with a newer queued/running retry does NOT create a Failed sibling.
 11. Confirm completing/deleting Main never closes the Multica Issue.
 12. Confirm iCloud delivery to iPhone plus Run at Login / sleep-wake / network-recovery behavior on the target Mac.
EOT
