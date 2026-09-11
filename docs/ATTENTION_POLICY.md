# Attention Policy

Bridge 的核心原则：**不是 Agent 完成就提醒，而是“轮到人行动”才提醒。**

## Default state machine

| Issue / Run fact | Human action | Reminder action |
|---|---:|---|
| backlog | no | none |
| todo, no failed run needing intervention | no | none |
| in_progress | no | none |
| in_review | yes | create/update |
| blocked, auto-recovery exists | usually no | wait grace period |
| blocked, no recovery / asks human input | yes | create/update |
| latest run failed, retry active | no | none |
| latest run failed, no retry and issue open | yes | create/update |
| done | no | resolve |
| cancelled | no | resolve |

## Precedence

```text
explicit suppression
    > terminal issue state
    > in_review category
    > blocked/failure policy
    > semantic fallback
    > no reminder
```

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
Issue status category → AttentionPolicy → Reminder
```

## Optional semantic fallback

只用于 blocked/failure 这类模糊状态：

```text
latest issue state
+ latest agent comment
+ latest run failure reason
→ classify human_required | machine_wait | retryable
```

此层应默认关闭，并且决策必须留下 reason receipt。
