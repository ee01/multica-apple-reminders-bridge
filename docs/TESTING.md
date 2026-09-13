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
- Review / Action Required / Failed；
- Review complete → guarded Multica done；
- Cloud status write failure reopens Review instead of silently losing approval；
- Action Required / Failed complete → acknowledge only；
- stale failed + active retry suppression；
- first-run Reminder List bootstrap；
- active Run overrides stale `in_review`；
- direct Multica rework；
- multiple review generations；
- Multica done/cancelled resolution；
- Main completion/delete = dismiss Apple projection only；
- Review completion = guarded approval / Multica `done`（默认）；Review delete = dismiss；Action Required / Failed completion/delete = acknowledge/dismiss only；
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
2. 首次 sync 自动确保 `Agent Requests` / configured Project Lists 存在并可读取；
3. Apple Request -> real Multica Issue + Agent Run；
4. 原 Reminder 成为 Main；
5. `in_review` -> Review sibling + iPhone notification；
6. 勾选当前 Review sibling -> Multica `done` -> Main 自动完成；
7. 另建测试 Issue：direct Multica rework -> 旧 Review sibling auto-complete；第二次 delivery -> 新 Review sibling；
8. blocked -> Action Required；final failed/no retry -> Failed；两者勾选均不修改 Multica status；
9. Multica done/cancelled -> Main/Human resolve；Apple Main checkbox 不关闭 Multica；
10. Run at Login / wake / network recovery。
