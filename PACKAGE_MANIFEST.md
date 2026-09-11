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
