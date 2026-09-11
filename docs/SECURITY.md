# Security Model

## Multica credentials

v1 Bridge 不读取、不复制 Multica PAT。

```text
Bridge -> multica CLI --profile reminders-bridge -> Multica Cloud
```

认证由官方 CLI profile 持有。Bridge 不读取 Desktop 的 `desktop-*` profile，也不读取 daemon 状态目录。

原则：

- 不把 PAT 写进 `config.json`。
- 不把 PAT 写进 SQLite。
- 不把 PAT 写进 Reminder notes。
- 不把 PAT 写进日志。
- `scripts/check-no-secrets.sh` 扫描常见 `mul_...` PAT 形态。
- 日志层额外对 PAT-like 文本做替换脱敏。

未来若实现 Direct API adapter，PAT 必须进入 macOS Keychain，而不是配置文件。

## Process execution

Bridge 只直接执行配置的 `multica` binary，不把 Issue 文本拼成 shell 命令；参数通过 `Process.arguments` 传入，避免 shell interpolation。

stdout/stderr 使用随机临时文件捕获，命令结束后删除，以避免大 JSON pipe deadlock。

## Apple data

Reminder 会通过用户的 Apple Reminders/iCloud 体系同步，因此 Notes 默认最小化：

- Issue key
- Agent/display name
- Attention reason
- compact summary
- Multica deep link

不复制完整 run transcript、repo、代码或大 Markdown。

敏感 Issue 可以添加 `no-reminder`。

## Authority boundary

Apple Reminder 是 projection，不是审批接口。

```text
Apple Reminder completed/deleted
    -> 本地 acknowledgement/dismissal
    -> 不修改 Multica Issue
```

```text
Multica done/cancelled
    -> Bridge resolves Apple Reminder
```

这样不会把“清掉手机提醒”误解释成“批准代码/结果”。
