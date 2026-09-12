# Verification Receipt

> Generated: 2026-09-12
> Version: 0.2.0
> Delivery environment: Linux / Swift 6.2.1

## Automated delivery-environment checks

| Check | Result |
|---|---|
| `swift test` | **PASS — 54 tests, 0 failures** |
| `make verify` | **PASS** |
| `swift build` | **PASS** |
| `swift build -c release` | **PASS** |
| Swift source syntax parse | **PASS** |
| Shell scripts `bash -n` | **PASS** |
| `resources/Info.plist` XML parse | **PASS** |
| `config.example.json` parse | **PASS** |
| Multica PAT-like secret scan | **PASS** |
| `git diff --check` | **PASS** |

The automated suite covers the Phase A-F v0.2 behavior, including:

- `apple_origin_only` as the default mirror mode, plus `all_active` and `attention_only` overrides;
- Apple Request -> Multica Issue dispatch and original Reminder -> Main projection reuse;
- request-marker crash idempotency and recovery of a Cloud Issue created before the local SQLite commit;
- recovery under `attention_only` without accidentally creating a Main Reminder;
- Multica Issue URL continuation without creating a duplicate Issue;
- unassigned continuation using `issue assign --no-start` before the follow-up comment, avoiding assignment/comment double-Run behavior;
- continuation preserving Multica-origin semantics under default `apple_origin_only`;
- Main + Review/Unblock/Failure sibling Reminders in the same project List;
- Human Action alarms while Main has no Bridge-managed attention alarm;
- direct Multica rework: active Run resolves the old Review sibling even if Issue status remains stale `in_review`;
- next delivery creating a new review generation;
- Multica `done/cancelled` resolving Main + active Human Actions;
- Apple Main completion/deletion dismissing only the Apple Main projection, never closing the Multica Issue;
- Apple Human Action completion/deletion acknowledging only that action generation;
- SQLite persistence and closed-Issue refresh when terminal Issues disappear from list output;
- CLI login isolation (`multica login --profile reminders-bridge`) and no daemon startup;
- CLI pagination/workspace flags, JSON parsing, subprocess timeout/error behavior, and large stdout without pipe deadlock.

## Authority and safety checks

Verified by code/tests:

- Bridge never treats Apple Main checkbox completion as Multica `done`.
- Bridge never treats Human Action checkbox completion as approval of Agent output.
- Bridge does not read Multica Desktop daemon credentials or start a second daemon.
- Bridge-managed reminders are excluded from Apple Request scanning via Bridge markers.
- PAT-like secrets are not present in committed source/docs/config examples.

## Platform-dependent acceptance still required

This delivery environment is not macOS and does not have access to the user's Multica Cloud account or iCloud account. Therefore the following are intentionally **not claimed as executed here**:

- AppKit/SwiftUI build and type-check against the target macOS SDK;
- EventKit/TCC full Reminders authorization;
- real Apple Reminder creation/update/completion through EventKit;
- iCloud propagation to iPhone/iPad;
- actual iPhone alarm notification;
- live Multica Cloud create/assign/comment/run lifecycle using the user's workspace;
- real Multica project/agent catalog loading;
- `SMAppService.mainApp` login-item behavior;
- sleep/wake and network-recovery behavior on the target Mac.

Run on the target Mac before relying on the bridge for daily work:

```bash
./scripts/verify-macos.sh
```

Then complete the interactive checklist printed by that script: connect the `reminders-bridge` CLI profile, select a real workspace/project/agent, create an Apple request, observe the Multica Run, move it to review, confirm the sibling Reminder/alarm on iPhone, perform rework directly in Multica, and confirm automatic sibling reconciliation.
