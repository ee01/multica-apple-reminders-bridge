
## Unreleased

### Changed

- Revised v0.2 Apple -> Multica lifecycle from separate Request/Attention reminders to a single Issue-bound Reminder projection that moves between `Agent Work` and `Agent Attention`.
- Added reconciliation for reviews completed directly in Multica and active rework runs.
- Made project-specific Request Lists optional routing presets rather than a required list-per-project mirror.
- Replaced manual `Continue: MUL-*` as primary UX with Multica Issue URL continuation.
- Added artifact review strategy for Markdown/PDF/PPT/attachments.
# Changelog

## Unreleased

### Designed

- Apple Reminders → Multica request intake (`Agent Requests`).
- Per-list routing to Multica Project + default Agent.
- Generic request metadata overrides and `Continue: MUL-xxx` follow-up routing.
- Separate `Agent Attention` human-action queue instead of Reminder subtasks.
- Explicitly deferred arbitrary private Chat continuation until a stable API contract is verified.


## 0.1.0 - 2026-09-11

Initial implemented release candidate:

- Multica Cloud CLI source with isolated profile/login.
- Deterministic attention policy for review/blocked/failure states.
- Review-cycle-aware Apple Reminder projection.
- SQLite persistence and reconciliation.
- EventKit reminder list, deep link, priority, due date and mobile attention alarm.
- EventKit identifier recovery marker.
- Menu Bar and Settings UI.
- Run-at-login, wake and network recovery sync.
- Build/install/macOS verification scripts.
- Linux/macOS CI definition and core test suite.
