# Security Model

## Multica credentials

```text
Bridge -> official multica CLI --profile reminders-bridge -> Multica Cloud
```

- Bridge 不读取/复制 PAT；
- 不读取 Desktop 的 `desktop-*` 私有 profile；
- `config.json` / SQLite / Reminder Notes / logs 不保存 PAT；
- Direct API adapter 若未来实现，PAT 必须存 macOS Keychain。

## No second daemon

Bridge 只使用 `multica login / issue / project / agent ...` CLI commands，从不执行 `setup` 或 `daemon`。

## Process safety

Issue/comment body 通过 CLI arguments 或随机临时文件传递，不拼接 shell command。stdout/stderr 使用 file-backed capture，规避大输出 pipe deadlock。

## Apple/iCloud data minimization

Reminder 会同步到用户 iCloud，因此只保存：

- Issue title/key；
- Project/Agent display name；
- compact status/summary；
- durable Multica Issue deep link；
- internal `Bridge ref` marker。

不复制完整 transcript、源码、大 Markdown、token。

## Authority boundary

```text
Apple Main completed/deleted
 -> dismiss Main projection only
 -> no Multica mutation

Apple Human Action completed/deleted
 -> acknowledge that action only
 -> no Multica mutation

Multica done/cancelled
 -> resolve Apple projections
```

这避免手机通知上的“Complete”按钮变成高责任审批/关闭 Agent 工作操作。
