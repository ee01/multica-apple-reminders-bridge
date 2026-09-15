# Multica Apple Reminders Bridge

一个独立的 macOS Menu Bar 应用，在 **Multica Cloud** 与 **Apple Reminders** 之间建立双向工作流：

- 在 Apple Reminders 创建 Agent Request，Bridge 将它派发到 Multica；
- 一个 Apple-origin Multica Issue 保留一个 **Main Reminder**，用于项目视图；
- 当 Agent 真正需要人处理时，Bridge 在**同一个项目 List**创建三类简单 Human Action sibling：**Review / Action Required / Failed**，并设置近期 alarm；
- 用户也可以直接在 Multica Review/返工/Done，Bridge 会自动回收 Apple 侧 sibling；
- Apple checkbox 默认不承担泛化控制语义；唯一例外是当前 Review sibling：严格门禁通过后，勾选即表示审核通过并把 Multica Issue 设为 `done`。

当前版本：`0.4.0`。

## 核心模型

```text
Apple Project List                       Multica
────────────────────────────────────────────────────────────
○ 修复 Ask verification     ───────────> MUL-381 (Main Issue)

Agent working:
○ 修复 Ask verification                 Run running

Agent delivered:
○ 修复 Ask verification                 MUL-381 in_review
○ Review: 修复 Ask verification  🔔      Human Action sibling

User requests changes in Multica:
○ 修复 Ask verification                 new active Run
✓ Review: 修复 Ask verification

Agent delivers again:
○ 修复 Ask verification
✓ Review: 修复 Ask verification
○ Review: 修复 Ask verification  🔔      Review cycle #2

Multica done:
✓ 修复 Ask verification
✓ Review: ...
```

**Main 与 Human Action 是不同 Reminder。**因此 Action Required / Failed 可以独立 acknowledgement，不会误把整个 Agent Task 完成。Review 是唯一的高责任例外：它只用于“最终交付等待验收”，默认勾选即表示 approve；Bridge 通过严格门禁后把 Multica Issue 设为 `done`，随后反向完成 Main。若某个“审核”通过后 Agent 还应继续下一阶段，它必须建模为 Action Required / 后续 Run，而不是 Review。

## 默认 Mirror Mode

默认值按设计为：

```text
apple_origin_only
```

含义：

- 从 Apple Reminders 发起的 Agent work：保留 Main Reminder；
- 直接从 Multica 创建的 Issue：默认不镜像 Main；
- 但任何来源的 Issue 一旦真正需要人处理，仍会在绑定 Project List（无绑定则 `Agent Requests`）产生 Human Action sibling。

每个 Project Route 可以覆盖为：

- `apple_origin_only` — 默认；
- `all_active` — 该 Multica Project 的 active Issues 都维持 Main Reminder；
- `attention_only` — 只创建 Human Action sibling，不维持 Main。

## Project Route

Bridge Settings 可以把常用 Apple List 绑定到 Multica Project + 默认 Agent：

```text
Apple List              Multica Project       Default Agent
Agent · Personal AI  -> Personal AI        -> Coding Agent
Agent · Website      -> Website            -> Frontend Agent
Agent Requests       -> fallback/default   -> default Agent
```

Apple 侧**不保存本地代码目录**。Multica Project 自己负责 Git/local directory/daemon resource 绑定。

## Apple → Multica

用户在 `Agent Requests` 或绑定的 Project List 创建普通 Reminder：

```text
Agent · Personal AI
○ 给 Ask 外部查证增加 Skip

Notes:
先补测试，再修改实现。
```

Bridge 会：

1. 根据 Apple List 选择 Project Route；
2. 创建 Multica Issue；
3. assign 默认 Agent；
4. 将**原 Reminder 本身**升级为 Main Reminder，不移动 List、不完成；
5. 写入 Multica deep link 与 Bridge marker，后续不再当作新 Request 扫描。

如果新 Reminder 的 URL 已指向现有 Multica Issue，则 Bridge 把它解释为 follow-up：在已有 Issue 增加 comment/必要时 assign Agent，而不是创建新 Issue。

## Multica → Apple Human Action

确定性 Attention Policy：

```text
active Run                       -> Agent owns turn, no Human Action
in_review + no active Run        -> Review sibling + alarm
blocked + grace expired          -> Action Required sibling + alarm
failed + no newer active retry   -> Failed sibling + alarm
done / cancelled                 -> resolve Main + Human Actions
```

特殊 label：

```text
no-reminder       suppress Human Action
reminder-urgent   raise Apple priority
reminder-always   force Human Action
```

不需要给每个 Issue 写“完成后创建 Apple Reminder”的 prompt。

## Multica Desktop 与 Bridge daemon

可以继续正常使用 Multica Desktop。

Bridge 的 `Connect Multica` 只执行：

```bash
multica login --profile reminders-bridge
```

Bridge **从不执行** `multica setup` 或 `multica daemon`。Desktop 继续管理自己的 daemon；Bridge 的 CLI profile 只是访问 Multica Cloud 的脚本客户端，因此不会因为 Bridge 再启动第二个 daemon。

## Apple checkbox 语义

- 完成/删除 **Main Reminder**：仅表示“不要继续在 Apple 里维持这个 Main 投影”；不会关闭 Multica Issue。以后如果该 Issue 新出现 Human Action，Bridge 仍可创建 sibling。
- 完成当前 **Review sibling**：默认等价于“审核通过”。Bridge 只有在 Issue 仍为 `in_review`、没有 active Run、且是当前 review generation 时才执行 `multica issue status <issue> done`，随后反向完成 Main。状态写失败时会重新打开 Review Reminder。
- 删除 Review sibling：只 dismiss，不是 approve。
- 完成/删除 **Action Required / Failed sibling**：仅 acknowledgement/dismissal，不改变 Multica status，也不会自动 retry。
- 在 Multica `done/cancelled`：Bridge 自动完成对应 Main 与未完成 Human Action。

这是刻意的 authority boundary：Review checkbox 有明确的 approval 语义；blocked/failure 的解决方式不确定，因此不能从一个 checkbox 猜测已恢复。

## 安装

前置条件：

1. macOS 14+；
2. Multica Desktop 可继续照常使用；
3. 另外安装官方 Multica CLI；
4. Xcode Command Line Tools / Swift toolchain。

```bash
make install
```

首次启动：

1. Settings → **Connect Multica**；
2. 浏览器登录，建立独立 `reminders-bridge` profile；
3. 选择 Workspace；
4. Refresh Projects / Agents；
5. 配置 fallback Agent，以及需要的 Project Routes；
6. Grant Reminders Permission；
7. Bridge 首次同步会自动确保 `Agent Requests` 与已配置的 Project Route Lists 存在；
8. Create Test Reminder；
9. 可开启 Run at Login。

详见 [docs/INSTALLATION.md](docs/INSTALLATION.md)。

## 验证

```bash
make verify
```

真实 Mac/iCloud/Multica Cloud 端到端验收：

```bash
./scripts/verify-macos.sh
```

当前交付环境无法替代真实 EventKit/TCC/iCloud 登录，因此最终验证收据会明确区分自动测试与需在目标 Mac 执行的交互式 E2E。

## 文档

- [Architecture](docs/ARCHITECTURE.md)
- [Phase A–F Implementation Plan](docs/PLAN.md)
- [Apple → Multica Dispatch](docs/APPLE_TO_MULTICA_DISPATCH.md)
- [Attention Policy](docs/ATTENTION_POLICY.md)
- [v0.3 Human Action Decision](docs/HUMAN_ACTION_V0.3_PLAN.md)
- [Static Settings Mockup](docs/settings-mockup.html)
- [Installation](docs/INSTALLATION.md)
- [Testing](docs/TESTING.md)
- [Verification Receipt](docs/VERIFICATION.md)
- [Security](docs/SECURITY.md)
- [Personal AI × Multica Integration Plan v3](docs/PERSONAL_AI_MULTICA_INTEGRATION_PLAN_V3.md)

## Source adapters

`MulticaCliSource` 是 v0.3 默认：官方 CLI 管理登录/token，Bridge 不读取 Desktop 私有 token，也不直接持有 PAT。

未来仍可实现 `MulticaApiSource` 来减少 subprocess、精细控制 HTTP/retry/event，但它不是当前功能完整性的前置条件。

## License

MIT。Multica 与 Apple 是各自所有者的商标；本项目不是 Multica 或 Apple 官方项目。
