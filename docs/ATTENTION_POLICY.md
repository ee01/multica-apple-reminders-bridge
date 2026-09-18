# Human Attention Policy

Bridge 的核心原则：**Agent 完成一次 Run 不等于现在轮到人；只有结构化状态表明 human action required 才创建 sibling Reminder。**

## Reconciliation precedence

```text
suppression
  > terminal issue state
  > active Agent Run
  > in_review
  > blocked
  > final failed Run
  > no human action
```

特别是：`active Run` 高于 stale `in_review`。这样用户在 Multica Request Changes 后，旧 Review sibling 会被收尾，而不是因为 Issue 暂时还显示 `in_review` 继续提醒。

## Rules

| Issue / Run | Human Action |
|---|---|
| backlog / todo | none |
| active queued/dispatched/running Run | none |
| in_progress | none |
| in_review + no active Run | Review sibling |
| blocked + active/recovery | wait |
| blocked + grace expired | Action Required sibling |
| failed + no newer active retry | Failed sibling |
| done / cancelled | resolve active projections |

## Labels

```text
no-reminder       suppress Human Action
reminder-urgent   high priority
reminder-always   explicit Human Action
```

## Review generations

```text
in_review -> Review #1
active rework -> resolve #1
rework completes while in_review -> Review #2
...
```

Identity：

```text
(issue_id, human_action, generation)
```

同一 generation 幂等，不重复创建。

## Alarm

Main Reminder 不设置 Bridge-managed attention alarm。

Human Action sibling:

```text
Review / Failed: alarm = reminderAlarmSchedule (Notify me)
Action Required (blocked / reminder-always): alarm = now
```

Main Reminder 不设置 Bridge-managed attention alarm。默认 Review delay 是 60 秒，可关闭/调整；blocked 不受这个设置影响。Multica due date 与“现在提醒我 Review”是两个不同概念，本版本不把 Main due date 当作 human-attention alarm。

## Apple completion semantics

- Main 完成/删除：隐藏 Main Apple projection；不改 Multica。
- Review **完成**：默认视为 approve；仅在 current review + `in_review` + no active Run 等严格门禁通过后，Bridge 执行 `multica issue status <issue> done`，再完成 Main。
- Review **删除**：只 dismiss，不是 approve。
- Action Required / Failed 完成或删除：本轮 acknowledgement/dismissal；不改 Multica、不自动 retry/unblock。

`reviewCompletionBehavior=acknowledge_only` 可以恢复旧的 Review acknowledgement-only 行为。

## Failed without prompt injection

Bridge 解析 Multica Run failure reason（如 `runtime_offline`、`queued_expired`、`environment_prepare_failed`、provider auth/quota/config errors）。当旧失败已有更新的 queued/running retry 时，不生成 Failed Reminder。

## No per-task prompt

普通任务不读取 prompt 来决定是否提醒，也不要求 Agent 写“请创建 Apple Reminder”。

Agent System Prompt / Skill 不是 Bridge 正确性的依赖。未来若需要更漂亮的 blocker 文案，可选 Skill 只能作为展示增强。
