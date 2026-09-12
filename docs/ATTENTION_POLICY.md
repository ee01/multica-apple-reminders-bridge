# Human Attention Policy

Bridge 的核心原则：**Agent 完成一次 Run 不等于现在轮到人；只有结构化状态表明 human action required 才创建 sibling Reminder。**

## Reconciliation precedence

```text
suppression
  > terminal issue state
  > active Agent Run
  > in_review
  > blocked/failure policy
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
| blocked + grace expired | Unblock sibling |
| failed + no visible recovery | Failure sibling |
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

Human Action sibling 默认：

```text
alarm = now + reminderAlarmDelaySeconds
```

默认 60 秒，可关闭/调整。Multica due date 与“现在提醒我 Review”是两个不同概念，本版本不把 Main due date 当作 human-attention alarm。

## Apple acknowledgement

Apple 完成/删除 Human Action：本轮 acknowledgement/dismissal；不改 Multica。

Apple 完成/删除 Main：隐藏 Main Apple projection；不改 Multica。

## No per-task prompt

普通任务不读取 prompt 来决定是否提醒，也不要求 Agent 写“请创建 Apple Reminder”。

Optional LLM semantic classifier 只可能用于未来模糊 blocked/failure reason，不属于 v0.2。
