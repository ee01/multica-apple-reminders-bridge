# Multica Cloud × Apple Reminders Bridge — Architecture

> 日期：2026-09-11
> 状态：v1 Implemented；macOS/iCloud runtime acceptance pending
> 部署前提：**Multica Cloud + Web 或 Desktop，不 self-host**

## 0. Implementation snapshot

当前仓库已实现设计中的 v1 主路径：`MulticaCliSource → AttentionPolicy → SyncEngine/SQLite → EventKitReminderSink → Menu Bar app`。CLI 登录使用独立 `reminders-bridge` profile，Bridge 不启动 daemon；EventKit projection 支持 review cycle、手工完成/删除抑制、identifier 恢复和新 attention absolute alarm。Direct API 与 semantic classifier 保留为 optional adapter。

实际源码以 `Sources/` 和 `Tests/` 为准；实施状态见 [PLAN.md](PLAN.md)。

## 1. 设计结论

Bridge 应该是一个 **独立 macOS Attention Projection Service**，不是 Multica Agent、不是 Multica daemon plugin，也不是给每个 Issue 塞进去的一段 prompt。

它持续观察 Multica Cloud 中的结构化工作状态，把“现在轮到人处理”的状态转换成 Apple Reminder。

```text
                    ┌───────────────────────────┐
                    │       Multica Cloud       │
                    │ Issue / Run / Comment     │
                    │ Status / Project / Agent  │
                    └─────────────┬─────────────┘
                                  │
                ┌─────────────────┴─────────────────┐
                │                                   │
        Execution Plane                      Attention Plane
                │                                   │
                ▼                                   ▼
       Multica daemon                     Reminders Bridge
       on execution Mac                   on a macOS device
                │                                   │
         Codex / Claude Code                        │
                │                            AttentionPolicy
                │                                   │
                └── results → Cloud                 ▼
                                                EventKit
                                                   │
                                                   ▼
                                            Apple Reminders
                                                   │
                                                iCloud
                                                   │
                                            iPhone/iPad/Mac
```

### 最重要的边界

**daemon 不通知 Bridge。Bridge 也不控制 daemon。**

两者唯一共享的是 Multica Cloud 中的事实：

- Issue status；
- Run status；
- assignee；
- latest update；
- labels/custom properties；
- comments/result summary（仅必要时读取）。

因此无论用户用 Multica Web 还是 Desktop，Bridge 的逻辑完全一样。

---

## 2. 为什么不需要每个 Task 写 Reminder Prompt

Multica 的 Issue 生命周期本来就提供结构化工作语义：

- Agent 真正开始处理 Issue 交付物时，Issue 进入 `in_progress`；
- Agent 交付结果时，Issue 进入 `in_review`；
- `done` 通常表示人工确认完成；
- `blocked` 表示暂时无法继续。

因此第一版 Bridge 不做“读自然语言猜人类是否要行动”，而采用确定性状态机：

```text
                ┌──────────────┐
                │ in_progress  │
                └──────┬───────┘
                       │ Agent delivers
                       ▼
                ┌──────────────┐
                │  in_review   │ ───────→ CREATE REMINDER
                └──────┬───────┘
                       │ Human reviews in Multica
            ┌──────────┴───────────┐
            ▼                      ▼
      in_progress/rework          done
            │                      │
            │                      └────→ RESOLVE REMINDER
            └── delivers again
                    │
                    └────────────→ NEW REVIEW CYCLE
```

这比在每个 Prompt 中加入：

> “如果有人类需要处理，请创建 Apple Reminder。”

更可靠，原因是：

1. Prompt 容易遗漏；
2. 不同 Agent/harness 的自然语言行为不稳定；
3. Reminder 是 workflow policy，不应该由任务正文决定；
4. Multica 已经有 Issue status 作为 machine-readable contract；
5. 将来换 Codex / Claude Code / Agent 时，Bridge 无需变化。

### 是否完全不需要 Agent 配置？

正常使用 Multica 的 Agent lifecycle 时不需要每个任务配置。

如果未来某个自定义 Agent 不遵循 Issue status 约定，则优先：

1. 在 Agent/Workspace 层一次性修正行为；
2. 或通过 status/label policy 补偿；
3. 最后才考虑语义 classifier。

绝不把相同 Reminder 指令复制进每个 Issue prompt。

---

## 3. Bridge 与 Multica Cloud 如何通信

### 3.1 Multica 登录与执行通信

官方模式：

```text
Multica Web / Desktop
        │
        ▼
Multica Cloud API
        ▲
        │ daemon outbound connection
        │
Execution Mac
  └── Multica daemon
        └── Codex / Claude Code / Cursor
```

Desktop 会自动管理自己的 daemon；使用 Web 时可以安装 CLI 并通过 `multica setup` 启动 daemon。Web 和 Desktop 连接同一 Multica service 时读取同一份 workspace 数据。

### 3.2 Bridge 是第三个 Cloud Client

Bridge 与 Desktop/Web 并列：

```text
                    Multica Cloud
                  /       |       \
                 /        |        \
              Web      Desktop    Bridge
                         │          │
                       daemon     EventKit
                         │          │
                      Codex      Reminders
```

Bridge 只需要只读 Multica 工作状态；创建 Apple Reminder 时不经过 Multica daemon。

---

## 4. MulticaSource 设计

```swift
protocol MulticaSource {
    func fetchAttentionCandidates() async throws -> [IssueSnapshot]
    func fetchIssue(id: String) async throws -> IssueSnapshot
    func fetchLatestRuns(issueID: String) async throws -> [RunSnapshot]
}
```

### 4.1 v1 推荐：CLI JSON Adapter

当前官方 CLI 明确支持：

```bash
multica issue list --output json
multica issue get MUL-123
multica issue runs MUL-123
```

脚本被明确建议使用 JSON 输出而不是解析终端表格。

因此 v1：

```text
Swift Bridge
   │
   ├── Process()
   ▼
Multica CLI --output json
   │
   ▼
Multica Cloud
```

优点：

- 不依赖 Multica 内部 Web UI；
- 不读取 Desktop 私有数据；
- 不逆向 daemon protocol；
- CLI 是官方脚本 surface；
- Multica Cloud / 未来 self-host 都可由 adapter 隔离（本项目当前只支持 Cloud）。

注意：Multica Desktop 内置 CLI 只服务 Desktop 自己的 runtime；如果 Bridge 走 CLI，用户需要**单独安装官方 Multica CLI**并建立 Bridge 专用 profile。

推荐：

```text
profile = reminders-bridge
workspace = <目标 workspace>
```

### 4.2 v2 可选：Direct API Adapter

Multica PAT 明确用于 CLI、daemon、scripts 和 API；workspace API 使用 Bearer PAT + `X-Workspace-ID`。

但在没有把所需 Issue/Run endpoint contract 固化并测试前，不让业务核心直接绑定 REST JSON。

因此：

```text
MulticaCliSource   // v1 default
MulticaApiSource   // v2 / verified contract
```

两者共用同一 `IssueSnapshot` domain model。

### 4.3 不依赖 Multica Realtime WebSocket

Multica 自己的 Web/Desktop 用 realtime WebSocket 更新 UI，但当前 Bridge 不把内部 realtime 路径当作第三方稳定插件协议。

v1 已实现轮询：

```text
默认 120~300 秒
```

以后有正式 outbound event / plugin API 再增加 EventSource。

---

## 5. AttentionPolicy：自动判断的核心

```swift
struct AttentionDecision {
    enum Action {
        case none
        case createOrUpdateReminder
        case resolveReminder
    }

    let action: Action
    let reason: Reason
    let severity: Severity
}
```

### 5.1 第一版确定性规则

| Multica 状态/事实 | 决策 |
|---|---|
| `in_progress` | none |
| `todo` / `backlog` | none |
| `in_review` | create/update Reminder |
| `blocked` 且没有 active/retry path | create/update Reminder |
| latest Run failed + 无 active retry + Issue 未结束 | create/update Reminder |
| `done` | resolve Reminder |
| `cancelled` | resolve Reminder |

### 5.2 以 status category 为优先

Multica 支持 custom statuses，例如 `Code Review`、`QA`、`Rework`，它们继承 `in_review` / `in_progress` 等 category 行为。

Bridge 不应该只硬编码显示名；如果 source 能获得 status category，则按 category 判断。

若 CLI v1 输出暂时拿不到 category，则在设置中维护一次 custom-status mapping，而不是给每个 task 加 prompt。

### 5.3 覆盖规则

默认规则足以覆盖大多数任务，特殊需求使用结构化 override：

```text
label: no-reminder       → 永不投影
label: reminder-urgent   → 提高 Reminder priority
label: reminder-always   → 即使非 in_review，也按 policy 投影
```

也可在项目级设置：

```yaml
projects:
  - project: Personal-AI
    remind_on: [in_review, blocked]

  - project: Background-Experiments
    remind_on: [blocked]
```

这仍然不是 task prompt。

### 5.4 什么时候才考虑“智能语义判断”

只有状态不足以说明人类责任时才进入 Phase 4：

```text
blocked
  + latest comment
  + run failure reason
  → SemanticAttentionClassifier
```

例如区分：

- “等用户提供 API token” → human required；
- “等待 CI 重试” → 不需要人；
- “等待另一个 Agent” → 不需要人。

即使增加语义 classifier，也只作为**模糊状态补充**，不能替代结构化状态机。

---

## 6. AppleReminderSink

Bridge 是原生 macOS App/Agent，因为 Apple Reminders 的正式读写接口是 EventKit。

```swift
protocol ReminderSink {
    func upsert(_ item: HumanAttentionItem) async throws -> ReminderReceipt
    func resolve(_ receipt: ReminderReceipt) async throws
}
```

Apple 侧：

```text
EKEventStore
  └── requestFullAccessToReminders()
       └── EKReminder
            ├── title
            ├── notes
            ├── url
            ├── priority
            └── dueDateComponents
```

首次运行由 macOS 弹系统权限框；Bridge 必须在 app bundle 的 Info.plist 中声明 Reminders 权限用途。

### 6.1 推荐 List

```text
Multica Reviews
```

不要混入用户普通个人提醒 List，除非用户明确选择。

### 6.2 Reminder 内容

示例：

```text
Title
Review: Memory regression investigation

Notes
MUL-123 · Coding Reviewer
Agent 已交付结果，等待 Review。
发现 2 个高风险 regression，其中 1 个涉及 migration compatibility。

URL
<Multica Cloud Issue Link>
```

完整 Markdown、代码、transcript、comments 不复制到 Notes；点击 URL 回 Multica Web 做深度 Review。

因为使用 Multica Cloud，iPhone 在外网直接打开该 Web Issue 的可达性比 LAN self-host 简单很多。

---

## 7. Review Cycle 与去重

一个 Issue 可以：

```text
in_progress
→ in_review      # Review 1
→ in_progress
→ in_review      # Review 2
→ done
```

Bridge 必须识别“Review cycle”，不能把 Issue 永久绑定成一个不可更新的 Reminder。

建议状态：

```text
issue_id
last_status_category
review_generation
last_run_id
last_payload_hash
last_seen_updated_at
```

默认：

```text
(issue_id, review_generation) = projection identity
```

配置：

```text
new_per_review_cycle  // 推荐
reuse_per_issue       // 可选
```

---

## 8. Apple Reminder 是否反向控制 Multica

v1：**不反向写 Multica。**

```text
用户在 Apple Reminders 打勾
        │
        └── 只表示“我处理了这个提醒”
```

不等价于：

```text
Issue = done
Review approved
PR can merge
```

因此：

```text
Multica -> Reminder  authoritative projection
Reminder -> Multica  no status mutation (v1)
```

如果用户在 Multica 把 Issue 标记 `done/cancelled`，Bridge 可以自动完成对应 Reminder。

用户自己手工完成/删除 Reminder 时，Bridge 记录 `user_acknowledged`，在同一个 Review cycle 不反复重建；下一次 Issue 从非-review 再进入 review 时才创建下一轮提醒。

---

## 9. 本地状态与恢复

SQLite：

```sql
CREATE TABLE issue_observation (
  issue_id TEXT PRIMARY KEY,
  issue_key TEXT,
  status_name TEXT,
  status_category TEXT,
  review_generation INTEGER NOT NULL DEFAULT 0,
  latest_run_id TEXT,
  latest_run_status TEXT,
  payload_hash TEXT,
  observed_updated_at TEXT,
  updated_at INTEGER NOT NULL
);

CREATE TABLE reminder_projection (
  id TEXT PRIMARY KEY,
  issue_id TEXT NOT NULL,
  review_generation INTEGER NOT NULL,
  apple_calendar_item_id TEXT,
  apple_external_id TEXT,
  projection_state TEXT NOT NULL,
  user_acknowledged INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE(issue_id, review_generation)
);
```

EventKit 的 `calendarItemIdentifier` 只能视为本地定位提示；Apple 文档说明 full sync 后 identifier 可能失效，因此必须保留 Issue identity、payload marker 等恢复锚点。

---

## 10. 运行方式

推荐一个轻量 macOS Menu Bar App：

```text
Multica Reminders Bridge
  ├── Status: Connected
  ├── Workspace: xxx
  ├── Last sync: 14:32
  ├── Pending review reminders: 3
  ├── Sync now
  ├── Test reminder
  └── Settings
```

后台：

```text
launch at login
→ timer every N minutes
→ fetch Multica snapshot
→ diff with SQLite
→ AttentionPolicy
→ EventKit
```

不需要保持 Multica Desktop 窗口打开才能运行 Bridge；但如果本机 Agent 的 daemon 只由 Desktop 管理，那么 Desktop 关闭后，该 runtime 的执行能力可能离线。Bridge 仍可读取 Cloud 中已经存在的状态。

### 常开机器建议

Bridge 必须运行在能使用 EventKit 的 macOS 上。

如果它安装在经常睡眠的 MacBook：

```text
Mac sleep → Bridge 不执行 → Reminder 延迟到唤醒后同步
```

需要稳定、接近实时的手机提醒时，优先部署到常开的 Mac mini / Mac desktop。

---

## 11. 凭据与安全

### Multica

v1 CLI adapter：使用独立 CLI profile；不要读取 Desktop 私有 daemon profile。

v2 API adapter：使用独立 PAT，存 macOS Keychain，不放 yaml、不写日志。

Multica PAT 代表账号访问能力，应按密码级凭据保护。

### Apple

- 不需要 Apple ID 密码；
- EventKit 由 macOS TCC 授权；
- iCloud 同步由系统 Reminders 完成。

### 数据最小化

Reminder 会进入用户 iCloud：

- 默认只写短摘要；
- 不写 token/secrets；
- 不复制大量源代码；
- `no-reminder` 可禁止敏感 Issue 投影。

---

## 12. 与 Multica Web / Desktop 的关系

### Web 用户

```text
Web → Multica Cloud
Mac CLI daemon → Multica Cloud → Codex/CC
Mac Bridge → Multica Cloud → EventKit
```

### Desktop 用户

```text
Desktop → Multica Cloud
Desktop bundled daemon → Multica Cloud → Codex/CC
Mac Bridge → Multica Cloud → EventKit
```

两种模式下 Bridge 完全相同。

Bridge 不依赖：

- Desktop Electron IPC；
- Desktop bundled CLI；
- daemon websocket；
- Multica source fork；
- self-host server。

---

## 13. 为什么第一版不做 Multica Plugin / Fork

独立 Bridge 的优势：

1. 可以直接使用 Multica Cloud；
2. Multica 升级不会产生 fork merge 成本；
3. Apple EventKit 是 macOS 平台能力，本来就适合独立 native app；
4. 将来 Multica 有稳定 Plugin/Extension API 时，可把 `MulticaSource + AttentionPolicy` 移入 plugin，而 `ReminderSink` 继续由本机 helper 提供；
5. 可以独立迭代 Apple-specific UX。

因此项目应按“未来可插件化的 sidecar”设计，而不是现在就侵入 Multica 源码。

---

## 14. 最终心智模型

```text
Multica daemon
= 机器执行桥

Multica Cloud
= Agent 工作事实源

Apple Reminders Bridge
= 人类注意力投影器

Apple Reminders
= 移动 Human Action Queue
```

Bridge 的本质不是“Agent 完成后执行一个 prompt”，而是：

> **持续观察工作状态，把结构化的 human-attention transition 投影成 Apple Reminder。**

---

## 15. 外部依据（2026-09-11）

Multica：

- Cloud Quickstart: https://multica.ai/docs/cloud-quickstart
- Desktop App: https://multica.ai/docs/desktop-app
- Daemon and Runtimes: https://multica.ai/docs/daemon-runtimes
- Issues / status lifecycle: https://multica.ai/docs/issues
- CLI / JSON scripting: https://multica.ai/docs/cli
- Authentication and PAT: https://multica.ai/docs/auth-tokens
- Project Architecture: https://multica.ai/docs/developers/architecture

Apple：

- EKEventStore: https://developer.apple.com/documentation/eventkit/ekeventstore
- requestFullAccessToReminders: https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoreminders(completion:)
- EKReminder: https://developer.apple.com/documentation/eventkit/ekreminder
- calendarItemIdentifier: https://developer.apple.com/documentation/eventkit/ekcalendaritem/calendaritemidentifier
