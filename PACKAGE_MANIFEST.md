# Package Manifest

完整源码包包含可运行 v0.2 源码、测试、文档以及完整 `.git/` 历史；不是预编译签名发行版。

## Runtime

- `Package.swift`
- `Sources/BridgeCore/`
- `Sources/MulticaRemindersBridge/`
- `Sources/CSQLite/`
- `resources/Info.plist`
- `config.example.json`

## Tests / CI

- `Tests/BridgeCoreTests/`
- `Fixtures/`
- `.github/workflows/ci.yml`

## Build / install

- `Makefile`
- `scripts/build-app.sh`
- `scripts/install.sh`
- `scripts/verify-macos.sh`
- `scripts/check-no-secrets.sh`

## Docs

- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/PLAN.md`
- `docs/APPLE_TO_MULTICA_DISPATCH.md`
- `docs/ATTENTION_POLICY.md`
- `docs/INSTALLATION.md`
- `docs/TESTING.md`
- `docs/VERIFICATION.md`
- `docs/SECURITY.md`
- `docs/PERSONAL_AI_MULTICA_INTEGRATION_PLAN_V3.md`

## Git

最终 ZIP 包含完整 `.git/`。`.build/` / `dist/` 等可重建产物在打包前删除。
