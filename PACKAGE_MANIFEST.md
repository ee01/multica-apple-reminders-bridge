# Package Manifest

这是 **完整源码 + Git 历史 + 文档** 的项目仓库清单；不是预编译签名发行版。

## Runtime code

- `Package.swift`
- `Sources/BridgeCore/`
- `Sources/MulticaRemindersBridge/`
- `Sources/CSQLite/`
- `resources/Info.plist`

## Tests

- `Tests/BridgeCoreTests/`
- `Fixtures/`
- `.github/workflows/ci.yml`

## Build / install / verification

- `Makefile`
- `scripts/build-app.sh`
- `scripts/install.sh`
- `scripts/verify-macos.sh`
- `scripts/check-no-secrets.sh`
- `config.example.json`

## Documentation

- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/ATTENTION_POLICY.md`
- `docs/PLAN.md`
- `docs/INSTALLATION.md`
- `docs/TESTING.md`
- `docs/VERIFICATION.md`
- `docs/SECURITY.md`
- `docs/PERSONAL_AI_MULTICA_INTEGRATION_PLAN_V3.md`

## Repository metadata

最终 ZIP 还包含完整 `.git/` 目录和本地提交历史，解压后可直接执行：

```bash
git status
git log --oneline
```

`.build/` 和 `dist/` 属于可重建产物，不放入最终 ZIP。

## v0.2 design addition

- `docs/APPLE_TO_MULTICA_DISPATCH.md` — Apple Reminders → Multica 主动任务发起、项目路由、继续已有 Issue 与未来 Chat continuation 设计。
- `docs/PLAN.md` — 已加入 v0.2 implementation phases。

当前可运行代码仍为 v0.1.0；v0.2 inbound dispatch 仅完成设计，尚未实现。


## v0.2 Design Revision 2

`docs/APPLE_TO_MULTICA_DISPATCH.md` now defines a single Issue-bound Reminder projection (`Requests -> Agent Work -> Agent Attention -> Agent Work -> completed`), direct-Multica review reconciliation, URL-based continuation, optional project route lists, and artifact review UX. Runtime implementation remains v0.1 until these changes are coded and macOS-verified.
