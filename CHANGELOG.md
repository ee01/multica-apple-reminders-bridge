# Changelog

## 1.0.0 - 2026-09-18

First stable release.

- Action Required (blocked) reminders always notify immediately, independent of the configurable alarm schedule.
- Fix Settings and onboarding windows not coming to the foreground in menu-bar agent mode.
- Add `AppWindowPresenter` to temporarily promote the app while user windows are open.
- Auto-detect Apple Development signing identity to preserve Reminders permission across local rebuilds.
- Document Reminders TCC behavior and stable local signing in installation/testing guides.
- Save configuration when removing a project route.

## 0.4.0 - 2026-09-15

- Add first-run onboarding wizard with setup checklist for Multica login, workspace, and Reminders permission.
- Streamline Settings with setup guidance, assignee pickers, and improved project route editing.
- Add configurable Human Action alarm schedules (immediate, delayed, next morning at 9:00).
- Add `runAtLoginEnabled` setting and app icon assets.
- Improve Reminder notes/deep links and case-insensitive Apple List name matching.
- Package macOS releases as downloadable `.zip` assets on GitHub Releases.
- Add `npm run deploy` / `make release` for local build-and-publish workflow.

## 0.3.0 - 2026-09-13

- Collapse user-facing Human Action taxonomy to **Review / Action Required / Failed**.
- Map `blocked` to Action Required without Agent prompt or Skill injection.
- Parse Multica Run failure reason codes and create Failed siblings for terminal failed runs with no newer active retry.
- Refresh stale failed/in_review snapshots from `issue runs` before alerting, preventing false Failed/Review reminders during automatic retry/rework.
- Completing the current Review sibling now defaults to explicit approval: guarded `multica issue status <issue> done`, followed by Main reconciliation.
- Re-open Review Reminder when the Multica status write fails, so approval intent is not silently lost.
- Action Required / Failed completion remains acknowledge-only; never auto-unblocks or retries.
- Add configurable `reviewCompletionBehavior` (`close_issue` default, `acknowledge_only` optional).
- Automatically ensure `Agent Requests` and configured Project Route Reminder Lists on first sync.
- Migrate persisted v0.2 `unblock/failure/explicit` action kinds to `action_required/failed`.


## 0.2.0 - 2026-09-12

Implemented bidirectional Apple Reminders <-> Multica Cloud workflow:

- Main + Human Action sibling model; removed moving-Main lifecycle design.
- `apple_origin_only` is the default mirror mode.
- Project Route: Apple List -> Multica Project -> default Agent -> mirror mode.
- Apple Reminder request dispatch to Multica Issue.
- Original Apple Reminder becomes Main projection in-place.
- Multica Issue URL continuation through follow-up comment; unassigned continuations use `assign --no-start` before the comment to prevent duplicate Runs.
- Request marker idempotency and crash recovery, including missing assignment recovery.
- Review / Unblock / Failure sibling reminders in the same Project List.
- Human Action sibling alarms; Main has no Bridge-managed attention alarm.
- Direct Multica review/rework reconciliation; active Run overrides stale `in_review`.
- Multiple review generations.
- Main completion/deletion dismisses only the Apple Main projection.
- Human Action completion/deletion acknowledges only that action cycle.
- Settings UI for project/agent catalog, fallback routing and route CRUD.
- SQLite v2 domain/persistence model with v0.1 best-effort migration.

## 0.1.0 - 2026-09-11

- Multica Cloud CLI source with isolated profile/login.
- Deterministic review/blocked/failure attention policy.
- Review-cycle Apple Reminder projection.
- SQLite persistence/reconciliation.
- EventKit deep link/priority/alarm support.
- Menu Bar app, login item, wake/network sync.
- Build/install/verification scripts and tests.
