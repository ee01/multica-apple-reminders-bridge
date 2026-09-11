# Attention Policy

Bridge 的核心原则：**不是 Agent 完成就提醒，而是“现在轮到人行动”才进入 `Agent Attention`。**

v0.2 设计采用“一 Multica Issue -> 一 Apple Reminder 投影”。同一条 Reminder 在 `Agent Work` 与 `Agent Attention` 之间迁移，而不是每轮 Review 新建一条。

## Default state machine

| Issue / Run fact | Human action | Reminder action |
|---|---:|---|
| backlog | no | request-originated: Agent Work / otherwise none |
| todo, no failed run needing intervention | no | Agent Work / none |
| active queued/dispatched/running run | no | Agent Work |
| in_progress | no | Agent Work |
| in_review + no active run | yes | move/create Agent Attention |
| in_review + active rework run | no | move Agent Work |
| blocked, auto-recovery exists | usually no | Agent Work, wait grace |
| blocked, no recovery / asks human input | yes | Agent Attention |
| latest run failed, retry active | no | Agent Work |
| latest run failed, no retry and issue open | yes | Agent Attention |
| done | no | complete projection |
| cancelled | no | complete projection |

## Reconciliation precedence

```text
explicit suppression
    > terminal issue state
    > active agent run
    > in_review category
    > blocked/failure policy
    > semantic fallback
    > Agent Work / no projection
```

`active agent run` 高于 stale `in_review`，用于处理用户已经在 Multica Request Changes / @Agent，但 Issue 状态尚未同步离开 Review 的窗口。

## Direct Multica review

用户不需要从 Apple Reminder 开始 Review。

如果用户直接在 Multica：

- `in_review -> done`：Bridge 完成对应 Reminder；
- `in_review -> in_progress/todo`：Bridge 移到 `Agent Work`；
- comment/@Agent 创建 active run：即使 Issue 暂时仍为 `in_review`，Bridge 也先移到 `Agent Work`。

因此 `Agent Attention` 只包含当前仍需人的事项，不应长期积压已经处理的 Review。

## Overrides

Suggested labels:

```text
no-reminder
reminder-urgent
reminder-always
```

这些不是必须字段，只用于例外。

## No per-task prompt

默认不向 Issue description 注入任何 Apple Reminder 指令。

不推荐：

```text
“任务完成后，如果需要人类 review，请通知 Apple Reminder。”
```

推荐：

```text
Issue/Run structured state -> AttentionPolicy -> Reminder location/state
```

## Optional semantic fallback

只用于 blocked/failure 这类模糊状态：

```text
latest issue state
+ active runs
+ latest agent comment
+ failure reason
-> classify human_required | machine_wait | retryable
```

此层应默认关闭，并且决策必须留下 reason receipt。
