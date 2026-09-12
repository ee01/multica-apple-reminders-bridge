# Architecture

## 1. Control plane / execution plane / human projection

```text
                           Multica Cloud
                     Issue / Run / Comment
                      /                \
                     /                  \
          Multica Desktop             Bridge CLI client
               |                           |
         Desktop daemon                    |
               |                           v
         Codex / Claude              SyncEngine + SQLite
                                           |
                         +-----------------+----------------+
                         |                                  |
                    Main projection                  Human Action sibling
                         |                                  |
                         +------------ EventKit ------------+
                                           |
                                     Apple Reminders
                                           |
                                         iCloud
```

Desktop daemon 与 Bridge 无直接依赖。Bridge 的独立 CLI profile 只访问 Cloud，不启动 runtime daemon。

## 2. Domain model

```text
IssueBinding
  issueID / issueKey
  origin: apple | multica
  Project Route
  appleListName
  mainProjectionDismissed

ReminderProjection
  kind: main_issue | human_action
  generation
  receipt
  state
```

一个 Issue：

```text
0..1 Main
0..N Human Actions
```

## 3. Source of truth

Multica authoritative：

- Issue status；
- Agent assignee；
- Runs；
- comments；
- done/cancelled；
- project work context。

Apple authoritative only for：

- 用户是否完成/删除某个 Apple projection；
- 用户创建的新 Agent Request 内容。

Apple checkbox 不直接 mutate Multica lifecycle。

## 4. Request scanner

EventKit 只扫描配置 allowlist：

```text
Agent Requests
+ Project Route list names
```

Bridge-managed reminders 由 `Bridge ref:` marker 排除，避免 Main/Human sibling 被重新当 Request。

## 5. Idempotent dispatch

创建 Cloud Issue 前先按 request marker search：

```text
Apple Bridge request: <request-id>
```

这样 Cloud create 成功但本机 SQLite commit 前崩溃，也不会重复工作。恢复到已创建但尚未 assign 的 Issue 时，会继续完成 assignment。

## 6. Project projection

`ProjectProjectionPolicy` 决定 Main 是否存在：

```text
apple_origin_only (default)
all_active
attention_only
```

Human Action 与 Main 使用同一个 `appleListName`。

## 7. EventKit recovery

不只依赖 `calendarItemIdentifier`。恢复顺序：

1. local identifier；
2. external identifier；
3. `Bridge ref: <issue>#main|human-N` marker across writable lists。

用于承受 iCloud full sync 后 identifier 变化。

## 8. Polling

默认周期 180 秒，并在：

- Mac wake；
- network recovery；
- manual Sync Now

触发额外 reconcile。

## 9. Security

- Multica PAT 由 CLI profile 管理；
- Bridge config/SQLite/log 不存 PAT；
- 不读取 Desktop `desktop-*` 私有 profile；
- Issue 文本作为 Process arguments 或 temp files，不 shell interpolate；
- Reminder Notes 最小化，只保留 compact context + durable Issue deep link。
