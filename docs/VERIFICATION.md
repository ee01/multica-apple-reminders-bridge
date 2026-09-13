# Verification Receipt

> Generated: 2026-09-13
> Version: 0.3.0
> Delivery environment: Linux / Swift 6.2.1

## Automated delivery-environment checks

| Check | Result |
|---|---|
| `swift test` | **PASS — 64 tests, 0 failures** |
| `make verify` | **PASS** |
| `swift build` | **PASS** |
| `swift build -c release` | **PASS** |
| Swift source syntax parse | **PASS** |
| Shell scripts `bash -n` | **PASS** |
| `resources/Info.plist` XML parse | **PASS** |
| `config.example.json` parse | **PASS** |
| Multica PAT-like secret scan | **PASS** |
| `git diff --check` | **PASS** |

The automated suite covers the v0.3 behavior, including:

- `apple_origin_only` as the default mirror mode, plus `all_active` and `attention_only` overrides;
- Apple Request -> Multica Issue dispatch and original Reminder -> Main projection reuse;
- first-sync bootstrap of `Agent Requests` and configured Project Route Lists;
- request-marker crash idempotency and Cloud-created-Issue recovery;
- Multica Issue URL continuation without creating a duplicate Issue;
- unassigned continuation using `issue assign --no-start` before the follow-up comment, avoiding assignment/comment double-Run behavior;
- Main + Human Action siblings in the same project List;
- exactly three user-facing Human Action kinds: **Review / Action Required / Failed**;
- `blocked` -> Action Required without Agent System Prompt or Skill injection;
- terminal failed Run -> Failed, including persisted Multica failure reason code in the Reminder payload;
- stale failed snapshot + newer queued/running retry suppression, preventing false Failed reminders;
- stale `in_review` + active rework Run suppression, preventing false Review reminders;
- Human Action alarms while Main has no Bridge-managed attention alarm;
- Review completion defaulting to guarded approval: current generation + still `in_review` + no active Run -> `multica issue status <issue> done` -> Main/Human reconciliation;
- `reviewCompletionBehavior=acknowledge_only` compatibility mode;
- failed Multica status write re-opening the Review Reminder instead of silently losing approval intent;
- Action Required / Failed completion remaining acknowledgement-only with no Multica status mutation or automatic retry;
- Review deletion remaining dismiss-only rather than approval;
- direct Multica rework resolving the old Review sibling even when Issue status is temporarily stale;
- next delivery creating a new review generation;
- Multica `done/cancelled` resolving Main + active Human Actions;
- Apple Main completion/deletion dismissing only the Apple Main projection, never closing the Multica Issue;
- SQLite persistence and closed-Issue refresh when terminal Issues disappear from list output;
- CLI login isolation (`multica login --profile reminders-bridge`) and no daemon startup;
- official CLI status mutation command used for guarded Review approval;
- CLI pagination/workspace flags, JSON parsing, subprocess timeout/error behavior, and large stdout without pipe deadlock.

## Authority and safety checks

Verified by code/tests:

- Apple Main checkbox completion never maps to Multica `done`.
- Review is intentionally the sole high-responsibility checkbox: it represents final delivery acceptance and can close the Issue only behind strict guards.
- A workflow that needs human input/authorization and then continues must be represented as Action Required / subsequent Run, not as final Review.
- Action Required and Failed checkbox completion never claims the underlying blocker/failure is fixed and never starts a retry.
- A failed Run with a newer active retry does not alert the user as Failed.
- Bridge does not depend on injected Agent Instructions, System Prompts, or Multica Skills to identify Review/Blocked/Failed states.
- Bridge does not read Multica Desktop daemon credentials or start a second daemon.
- Bridge-managed reminders are excluded from Apple Request scanning via Bridge markers.
- PAT-like secrets are not present in committed source/docs/config examples.

## Platform-dependent acceptance still required

This delivery environment is not macOS and does not have access to the user's Multica Cloud account or iCloud account. Therefore the following are intentionally **not claimed as executed here**:

- AppKit/SwiftUI build and type-check against the target macOS SDK;
- EventKit/TCC full Reminders authorization;
- automatic creation of real Apple Reminder Lists through EventKit;
- real Apple Reminder creation/update/completion through EventKit;
- iCloud propagation to iPhone/iPad and actual iPhone alarm notification;
- live Multica Cloud create/assign/comment/status/run lifecycle using the user's workspace;
- real Multica project/agent catalog loading;
- `SMAppService.mainApp` login-item behavior;
- sleep/wake and network-recovery behavior on the target Mac.

Run on the target Mac before relying on the bridge for daily work:

```bash
./scripts/verify-macos.sh
```

The script prints the current v0.3 interactive checklist, including list bootstrap, Apple request dispatch, Review approval -> Multica `done`, direct Multica rework, Action Required acknowledgement, Failed acknowledgement, retry suppression, Main dismissal semantics, iCloud alarms, and background recovery.
