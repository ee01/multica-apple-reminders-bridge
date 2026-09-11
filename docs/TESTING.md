# Testing and Verification

## 自动化测试

```bash
swift test
```

当前测试覆盖：

1. `in_review` 创建 Reminder。
2. `no-reminder` suppression。
3. urgent/high priority。
4. blocked active run 不提醒。
5. blocked grace 后提醒。
6. open Issue + failed Run 提醒。
7. done/cancelled resolve。
8. 同一 review cycle 幂等。
9. `in_review -> in_progress -> in_review` 新 generation。
10. 用户手工完成 Reminder：同一 cycle 不重建。
11. 用户手工删除 Reminder：同一 cycle 不重建。
12. Multica list 不再返回 closed Issue 时，主动 `issue get` 并正确收尾 projection。
13. SQLite 关闭/重开后 observation / projection / meta 持久。
14. Multica CLI JSON array/wrapper/custom status/labels 兼容解析。
15. `issue list` 分页和 `--workspace-id`。
16. Bridge login 只调用 `multica login`，不会调用 `daemon`。
17. 子进程非零退出、timeout。
18. 大于 pipe buffer 的 JSON/stdout 不死锁。

## 当前交付环境验证结果

```text
swift test
28 tests, 0 failures
```

核心 target 在 Linux Swift toolchain 上成功 build；`MulticaRemindersBridge` 在非 macOS 平台编译为明确的 unsupported stub，因此不会伪装执行 EventKit。

## macOS 自动构建

在 macOS 14+：

```bash
./scripts/verify-macos.sh
```

它会：

- `swift test`
- 构建 `.app`
- `plutil -lint` Info.plist
- codesign
- 检测 Multica CLI
- 检测 `reminders-bridge` auth profile
- 查询 workspace JSON

## 必须在真实 Mac/iCloud 上完成的验收

这些能力依赖 Apple TCC、EventKit、iCloud 和真实 Multica 账号，无法在非 macOS CI/当前交付环境中诚实地验证：

1. EventKit full-access 权限框出现并可授权。
2. `Multica Reviews` list 可创建/写入。
3. Test Reminder 同步到 iPhone/iPad。
4. 新 Reminder 的 absolute alarm 能触发 Apple Reminders 通知（受用户 Focus/通知设置影响）。
5. 真实 Multica Issue `in_review` 被唯一投影。
6. Reminder URL 能打开正确 Cloud Issue。
7. Issue `in_progress` / `done` 后 Reminder 正确收尾。
8. 第二个 Review cycle 生成新 Reminder。
9. App 作为 Login Item 运行。
10. Mac wake/network recovery 后自动 reconcile。

## GitHub Actions

`.github/workflows/ci.yml` 包含：

- Ubuntu core tests + secret scan。
- macOS 15 Swift tests + `.app` build + secret scan。

TCC/iCloud 仍需要交互式 Mac 做最终验收。
