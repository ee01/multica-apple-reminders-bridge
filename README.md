# Multica Apple Reminders Bridge

一个独立的 macOS Menu Bar 应用：把 **Multica Cloud 中真正轮到人处理的 Agent 工作**投影到 Apple Reminders。

- 不 self-host Multica。
- 可继续使用 Multica Desktop；Bridge 不启动第二个 daemon。
- 不读取 Desktop daemon 的数据库或私有 token/profile。
- 不要求每个 Multica Issue 写“完成后提醒我”的 prompt。
- 不依赖 Personal AI；Personal AI × Multica v3 方案仅作为附带架构参考。

当前版本：`0.1.0`。

## 工作原理

```text
                          Multica Cloud
                   Issues / Runs / Status
                    /                 \
                   /                   \
        execution path                attention path
                /                         \
               v                           v
      Multica Desktop daemon       Multica CLI (read/query)
               |                           ^
         Codex / Claude Code               |
               |                    Reminder Bridge
               +---- results ----------> Cloud
                                           |
                                      AttentionPolicy
                                           |
                                        EventKit
                                           |
                                    Apple Reminders
                                           |
                                         iCloud
                                           |
                                    iPhone/iPad/Mac
```

Multica Desktop 的 daemon 与 Bridge 完全独立：

- Desktop daemon 负责本机 Codex/Claude Code 执行，并把结果同步到 Multica Cloud。
- Bridge 作为另一个 Cloud client，周期调用官方 Multica CLI 的 JSON 接口读取 Issue/Run 状态。
- Bridge 根据结构化状态判断是否“轮到人”，再用 EventKit 创建/更新 Apple Reminder。

### 使用 Desktop 会不会多一个 daemon？

不会。Bridge 的连接按钮只执行：

```bash
multica login --profile reminders-bridge
```

`login` 只建立独立 CLI 登录/profile。Bridge **从不执行** `multica setup`、`multica daemon start` 或 Desktop 的私有 daemon profile，因此不会因为安装 Bridge 多出一个 Multica runtime/daemon。

## 默认 Attention Policy

```text
backlog / todo / in_progress       -> 不提醒
in_review                          -> 创建或更新 Reminder
blocked + 无 active run + 超过宽限 -> 创建或更新 Reminder
open Issue + 最新 Run failed       -> 创建或更新 Reminder
done / cancelled                   -> 完成对应 Reminder
```

覆盖 label：

```text
no-reminder       永不投影
reminder-urgent   提高 Apple Reminder priority
reminder-always   即使非 review 状态也创建 Reminder
```

绝大多数任务不需要额外 prompt。只有自定义 Agent 根本不维护 Multica status lifecycle 时，才应在 Agent/Workspace 层一次性修正行为，而不是给每个任务重复 Reminder 指令。

## Apple Reminder 行为

Bridge 默认建立/使用 `Multica Reviews` List。新的人类注意事项会：

- 生成简短 title、summary 和 Multica Issue deep link；
- 保留 Multica Issue due date（如果存在）；
- 默认增加一个约 60 秒后的 EventKit alarm，用于让 iPhone/iPad 真正收到提醒；
- 不复制完整 transcript、大段代码或 Markdown；深度 Review 仍在 Multica。

用户在 Apple Reminders 手工打勾/删除，只表示处理了这条个人提醒，**不会把 Multica Issue 自动改成 done**。Multica 仍是 Agent 工作的 Source of Truth。

## 安装

前置条件：

1. macOS 14+。
2. Multica Desktop 可以照常使用。
3. 另外安装官方 Multica CLI（Bridge 使用它查询 Cloud，不启动 daemon）。
4. Xcode Command Line Tools / Swift toolchain。

在项目目录运行：

```bash
make install
```

默认安装到：

```text
~/Applications/Multica Reminders Bridge.app
```

首次启动：

1. 打开 Settings。
2. 点击 **Connect Multica**。
3. 浏览器完成 Multica 登录；Bridge 使用独立 `reminders-bridge` profile。
4. 选择 Workspace。
5. 点击 **Grant / Check Permission** 允许 Reminders。
6. 点击 **Create Test Reminder** 验证 iCloud/iPhone。
7. 可开启 **Run at Login**。

更详细步骤见 [docs/INSTALLATION.md](docs/INSTALLATION.md)。

## 开发与验证

核心模块没有 Apple framework 依赖，因此 Linux/macOS 都可运行：

```bash
make verify
```

macOS 上运行完整构建与人工验收清单：

```bash
make mac-app
./scripts/verify-macos.sh
```

本交付环境已完成：

- Swift package build；
- 28 个核心/集成测试全部通过；
- SQLite restart persistence；
- CLI 参数与分页/独立 profile 测试；
- 大 stdout 子进程回归测试；
- secret scan。

由于当前构建环境不是 macOS，EventKit/TCC/iCloud、Menu Bar app bundle 和真实 Multica Cloud 登录无法在此环境完成最终真机验收；`scripts/verify-macos.sh` 已将这些步骤固化为一条 macOS 验收流程。详见 [docs/TESTING.md](docs/TESTING.md)。

## 源码结构

```text
Sources/
  BridgeCore/
    AttentionPolicy.swift
    BridgeDatabase.swift
    Configuration.swift
    Models.swift
    MulticaCliSource.swift
    MulticaJSONParser.swift
    ProcessRunner.swift
    ReminderFormatter.swift
    SyncEngine.swift
  MulticaRemindersBridge/
    AppMain.swift
    BridgeAppModel.swift
    EventKitReminderSink.swift
    MenuBarView.swift
    SettingsView.swift
  CSQLite/
Tests/BridgeCoreTests/
Fixtures/
resources/Info.plist
scripts/
docs/
```

## 文档

- [Architecture / Design](docs/ARCHITECTURE.md)
- [Implementation Plan & Status](docs/PLAN.md)
- [Attention Policy](docs/ATTENTION_POLICY.md)
- [Installation](docs/INSTALLATION.md)
- [Testing](docs/TESTING.md)
- [Verification Receipt](docs/VERIFICATION.md)
- [Security](docs/SECURITY.md)
- [Personal AI × Multica Integration Plan v3](docs/PERSONAL_AI_MULTICA_INTEGRATION_PLAN_V3.md)
- [Apple Reminders → Multica Dispatch Design (v0.2)](docs/APPLE_TO_MULTICA_DISPATCH.md)

## Direct API 为什么没作为 v1 默认？

`MulticaCliSource` 已经是官方 Cloud API 的受支持脚本前端，并且 CLI 自己管理登录/profile。这样 Bridge 不需要接触 PAT，也不需要绑定 REST JSON 细节。

未来可以增加 `MulticaApiSource`，主要收益是减少子进程开销、精确控制 HTTP 分页/错误/重试、摆脱 CLI 安装依赖，以及在官方稳定 event/realtime API 出现后更容易改成事件驱动。它是优化 adapter，不是本项目正常工作的前置条件。

## v0.2 方向：Apple Reminders 也可以成为 Agent Request Inbox

v0.1 只把 Multica 中需要人处理的工作投影到 Apple Reminders。v0.2 设计增加反方向，并采用“一 Issue 一 Reminder 投影”：用户在 `Agent Requests` 或项目路由 List 创建 Reminder，Bridge 将其派发为 Multica Issue 后把**同一条 Reminder**移动到 `Agent Work`；需要人工 Review/解阻时再移动到统一 `Agent Attention`，返工时移回 `Agent Work`，Multica `done/cancelled` 后才最终标记完成。这样发起与结束不会被拆成两张票据。

项目/代码目录不直接写进 Reminder。Apple 侧选择 Multica Project；项目到 Git repo / local directory / daemon 的绑定继续由 Multica 管理。EventKit 没有可靠的 Reminders subtask/tag/list-group API；而且 lifecycle 本身也不适合伪装成 subtask。完整设计见 [docs/APPLE_TO_MULTICA_DISPATCH.md](docs/APPLE_TO_MULTICA_DISPATCH.md)。

## License

MIT。Multica 与 Apple 是各自所有者的商标；本项目不是 Multica 或 Apple 官方项目。
