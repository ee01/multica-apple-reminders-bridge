# Changelog

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
