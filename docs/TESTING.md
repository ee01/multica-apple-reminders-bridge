# Testing and Verification

## Automated

```bash
swift test
make verify
```

覆盖：

- deterministic attention policy；
- default `apple_origin_only` + route overrides；
- Apple Request dispatch；
- request marker idempotency/recovery；
- Main projection in-place reuse；
- URL continuation；
- continuation 未分配 Agent 时使用 `--no-start`，避免双 Run；
- attention-only / continuation crash-recovery 不误建 Main；
- Main + Human Action sibling same-list behavior；
- Review/Unblock/Failure；
- active Run overrides stale `in_review`；
- direct Multica rework；
- multiple review generations；
- Multica done/cancelled resolution；
- Main completion/delete = dismiss Apple projection only；
- Human Action completion/delete = acknowledge cycle only；
- SQLite persistence/migration；
- closed Issue recovery；
- CLI login does not start daemon；
- pagination/workspace flags；
- JSON parser；
- subprocess timeout/error/large stdout。

实际最终数量见 `VERIFICATION.md`。

## macOS E2E

```bash
./scripts/verify-macos.sh
```

目标 Mac 还应人工验证：

1. TCC full Reminders access；
2. generic/project Lists 可创建和读取；
3. Apple Request -> real Multica Issue + Agent Run；
4. 原 Reminder 成为 Main；
5. `in_review` -> sibling + iPhone notification；
6. direct Multica rework -> sibling auto-complete；
7. second delivery -> new sibling；
8. Multica done -> Main/Human resolve；
9. Apple Main checkbox 不关闭 Multica；
10. Run at Login / wake / network recovery。
