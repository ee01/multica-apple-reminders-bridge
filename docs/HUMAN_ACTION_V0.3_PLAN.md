# v0.3 Human Action Model — Decision & Implementation Plan

> Date: 2026-09-13
> Status: implemented in source; final verification recorded in `VERIFICATION.md`
> Multica deployment: Cloud + Web/Desktop; no self-host requirement
> Agent prompt integration: **not required**

## 1. Why this revision exists

v0.2 established the stable Apple projection model:

```text
1 Multica Issue
├─ 0..1 Main Reminder
└─ 0..N Human Action sibling Reminders
```

The discussions after v0.2 clarified two additional requirements:

1. Human Attention should not require invasive Agent System Prompt / Skill injection.
2. Human Action should have a small, predictable taxonomy rather than trying to infer every reason semantically.

The v0.3 model therefore has exactly three user-facing Human Action types:

```text
Review
Action Required
Failed
```

## 2. Three Human Action types

### Review

Trigger:

```text
Issue category = in_review
AND no active Run
```

Meaning: the Agent delivered the Issue and Multica is waiting for human review.

Default Apple completion behavior:

```text
complete Review sibling
→ strict approval guards
→ multica issue status <issue> done
→ resolve Main + Review projection
```

Approval guards all have to pass:

- this is the current Review generation;
- the projection kind is `review`;
- Issue is still `in_review`;
- no queued/dispatched/starting/waiting-local-directory/running Run exists;
- no other active non-Review human gate exists.

If the Multica status write fails, Bridge reopens the Review Reminder instead of silently losing the approval intent.

A setting can change Review completion to `acknowledge_only`.

### Action Required

Trigger:

```text
Issue category = blocked
AND no active Run
AND blocked grace elapsed
```

Meaning: Multica says the Issue cannot currently continue and will not resume on its own.

Apple completion behavior:

```text
complete Action Required sibling
→ acknowledge this reminder only
→ DO NOT change Issue status
→ DO NOT trigger/retry Agent
```

To actually continue a generic blocked Issue, the blocker must be resolved and a new explicit Multica action must occur, such as a member comment / agent trigger / status change as appropriate. Bridge deliberately does not guess that checking an Apple Reminder proves the blocker is fixed.

### Failed

Trigger:

```text
latest effective Run = failed
AND no newer active retry Run exists
AND Issue is still non-terminal
```

This catches failures that do not necessarily become `blocked`, including examples documented by Multica such as:

- `runtime_offline` after retry is exhausted;
- `queued_expired`;
- `environment_prepare_failed`;
- auth/access errors;
- quota exhaustion;
- missing configuration;
- unavailable model/tool runtime;
- other terminal run failures.

No System Prompt is required. Bridge reads Run status and failure reason from Multica.

Apple completion behavior:

```text
complete Failed sibling
→ acknowledge this reminder only
→ DO NOT retry automatically
→ DO NOT change Issue status
```

The underlying reason should be fixed first, followed by a Multica retry when needed.

## 3. Retry-aware failure detection

A stale Issue list response can show the previous Run as failed while Multica has already queued an automatic retry.

Bridge therefore refreshes Runs before generating Failed when a relevant snapshot is nil/failed. If a newer Run is active:

```text
failed old Run
+ queued/running retry
→ no Failed Reminder
```

The same protection is used for Review: a stale `in_review` Issue plus a newer active rework Run does not create a Review Reminder.

## 4. No Agent Prompt or Skill dependency

Bridge v0.3 does not:

- edit Agent Instructions;
- install a mandatory Workspace Skill;
- require a `waiting_on=human` metadata convention;
- use an LLM to infer human attention from comments.

Its authority is structural Multica state:

```text
Issue status/category
+ Run status
+ Run failure reason
```

An optional future Agent Skill could improve how Agents explain blockers, but it is not required for Bridge correctness.

## 5. Apple list bootstrap

On first sync with Apple request dispatch enabled, Bridge ensures these Reminder Lists exist:

```text
Agent Requests
+ every configured Project Route Apple list
```

Users do not need to create `Agent Requests` manually.

## 6. Authority boundary

| Apple action | Multica effect |
|---|---|
| Complete Main | hide/dismiss Apple Main projection only |
| Complete Review | approve current delivered Issue and set `done`, when strict guards pass |
| Delete Review | dismiss Apple reminder only; deletion is not approval |
| Complete Action Required | acknowledge only |
| Complete Failed | acknowledge only |
| Multica Request Changes / new active Run | resolve old Review sibling |
| Multica done/cancelled | resolve Main + active Human Actions |

The asymmetric Review behavior is intentional: Review has a precise meaning (`in_review`, no active Run), while blocked/failure remediation cannot be inferred from a checkbox.

## 7. Default settings

```text
defaultMirrorMode = apple_origin_only
reviewCompletionBehavior = close_issue
failureRemindersEnabled = true
blockedGraceSeconds = 600
reminderAlarmEnabled = true
```

Settings UI exposes `Review completion` so a user can opt back into acknowledgement-only behavior.

## 8. Explicit non-goals

v0.3 still does not use:

- Apple Assigned to Me automation (no stable EventKit assignee write API);
- Apple Reminder subtask automation (no public EventKit parent/subtask API);
- UI automation/private Reminders DB;
- Agent System Prompt injection;
- automatic retry from a Failed checkbox;
- automatic unblock from an Action Required checkbox;
- direct Multica REST adapter as a requirement.
