# Multica Cloud × Apple Reminders Bridge — Implementation Plan & Status

> 日期：2026-09-11
> 项目：`multica-apple-reminders-bridge`
> 部署：Multica Cloud + Web/Desktop；不 self-host
> 版本：0.1.0
> 状态：**v1 implementation complete；macOS/iCloud interactive acceptance pending on a real Mac**

## 0. 最终范围

v1 实现一个独立 macOS Menu Bar app：

```text
Multica Cloud
  ↓
MulticaCliSource
  ↓
AttentionPolicy
  ↓
SyncEngine + SQLite
  ↓
EventKitReminderSink
  ↓
Apple Reminders / iCloud / iPhone
```

边界保持：

- Multica Desktop 可以继续使用；Bridge 不启动 daemon。
- Bridge 不读取 Desktop daemon DB/profile/token。
- Bridge 不要求每个 Issue 注入 Apple Reminder prompt。
- Apple Reminder 是 human-attention projection，不是 Multica Review authority。
- Personal AI 不在运行链上。

## 1. 已完成：工程初始化

- [x] Swift Package 初始化。
- [x] macOS 14 deployment target。
- [x] `BridgeCore` library。
- [x] `MulticaRemindersBridge` executable/Menu Bar app。
- [x] `CSQLite` system library。
- [x] XCTest target。
- [x] `.gitignore` / MIT License / Makefile。
- [x] GitHub Actions：Ubuntu core + macOS build。
- [x] app bundle build/install scripts。
- [x] Git repository 初始化。

## 2. 已完成：MulticaCliSource

实现：

```swift
protocol MulticaSource {
    func fetchIssues() async throws -> [IssueSnapshot]
    func fetchIssue(idOrKey: String) async throws -> IssueSnapshot
    func fetchRuns(issueIDOrKey: String) async throws -> [RunSnapshot]
    func authStatus() async throws -> String
    func version() async throws -> String
}
```

完成项：

- [x] 独立 `reminders-bridge` profile。
- [x] `multica login` 连接；不执行 `setup`/`daemon`。
- [x] `issue list --output json`。
- [x] `issue get --output json`。
- [x] `issue runs --output json`。
- [x] Workspace ID override。
- [x] Workspace list/selection。
- [x] issue pagination。
- [x] `--full-id`。
- [x] permissive JSON parser，兼容 array/wrapper/nested status/labels。
- [x] auth/workspace/command/malformed-output 错误分类。
- [x] subprocess timeout。
- [x] 大 JSON stdout 使用 file-backed capture，避免 pipe buffer deadlock。

### 为什么 v1 仍选 CLI

Bridge 不直接读取 PAT；登录和 token 生命周期由官方 CLI 负责。这样比读取 Desktop 私有 profile 更稳定，也比第一版直接绑定 REST schema 更安全。

`MulticaApiSource` 保留为 future adapter，不是 v1 缺失功能。

## 3. 已完成：AttentionPolicy

确定性规则：

| Multica state/fact | Decision |
|---|---|
| backlog/todo/in_progress | none |
| in_review | create/update Reminder |
| blocked + active Run | wait |
| blocked + no active Run + grace expired | create/update Reminder |
| open Issue + latest Run failed | create/update Reminder |
| done/cancelled | resolve Reminder |
| `no-reminder` | suppress |
| `reminder-always` | force attention |
| `reminder-urgent` / urgent priority | high Apple priority |

- [x] status category inference。
- [x] custom status category 优先。
- [x] blocked grace。
- [x] failed/no-visible-retry handling。
- [x] label override。
- [x] 不调用 LLM。
- [x] 不读取 task prompt 做普通判断。

## 4. 已完成：Review Cycle

实现：

```text
in_progress
 -> in_review     generation 1
 -> in_progress
 -> in_review     generation 2
 -> done
```

- [x] `(issue_id, review_generation)` projection identity。
- [x] 同一 review 不重复创建。
- [x] rework 时自动收尾旧 Reminder。
- [x] 再次 review 新建新 cycle Reminder。
- [x] 用户手工完成后同 cycle 不重建。
- [x] 用户手工删除后同 cycle 不重建。

## 5. 已完成：SQLite Persistence

表：

```text
issue_observation
reminder_projection
bridge_meta
```

完成项：

- [x] WAL。
- [x] restart persistence。
- [x] projection receipt。
- [x] payload hash 幂等。
- [x] acknowledgement/dismissal 状态。
- [x] pending retry 状态。
- [x] last sync metadata。
- [x] Cloud list 不含 closed Issue 时，对 active projection 逐项 `issue get` 校准。
- [x] Cloud transient error 不解释成 done。

## 6. 已完成：EventKit Reminder Projection

实现：

- [x] Reminders full-access 请求。
- [x] 查找/创建 `Multica Reviews` List。
- [x] title/notes/url/priority/due-date 映射。
- [x] compact summary，不复制完整 transcript/代码/Markdown。
- [x] Multica deep link。
- [x] 新 attention item 默认设置 absolute alarm（默认 60 秒，可配置/关闭）。
- [x] Multica due date 与 attention alarm 分开。
- [x] Multica done/cancelled -> Reminder complete。
- [x] Apple Reminder completed/deleted -> 本地 ack/dismiss；不写回 Multica。

### EventKit identifier 恢复

EventKit 的 local `calendarItemIdentifier` 在 full sync 后可能变化，因此实现三级恢复：

1. `calendarItemIdentifier`；
2. `calendarItemExternalIdentifier`；
3. 扫描专用 List，匹配 Notes 中 `Bridge ref: <issue>#review-<n>`。

- [x] 避免 identifier 失效导致重复 Reminder。

## 7. 已完成：Menu Bar / Settings / Background

- [x] Menu Bar 状态。
- [x] Sync now。
- [x] Open Multica Reviews。
- [x] Settings window。
- [x] CLI path/profile。
- [x] Connect Multica（只执行 `login`）。
- [x] Workspace picker。
- [x] Reminder permission/test。
- [x] Reminder List name。
- [x] poll interval。
- [x] blocked grace。
- [x] failure reminder toggle。
- [x] attention alarm enable/delay。
- [x] Run at Login (`SMAppService.mainApp`)。
- [x] wake 后立即 sync。
- [x] network 恢复后立即 sync。
- [x] diagnostic log。

## 8. 已完成：构建与安装脚本

```bash
make build
make test
make verify
make mac-app
make install
```

- [x] release Swift build。
- [x] `.app` bundle assembly。
- [x] Info.plist Reminders usage description。
- [x] ad-hoc/default configurable codesign。
- [x] `plutil -lint`。
- [x] `~/Applications` install default。
- [x] `verify-macos.sh` interactive acceptance checklist。

## 9. 已完成：自动测试

当前：

```text
29 tests
0 failures
```

覆盖：policy、parser、CLI source、review cycle、SQLite、sync/reconciliation、large subprocess output、timeout、configuration backward decoding。

详情见 `docs/TESTING.md`。

## 10. 仍需真实 macOS 交互验收

当前交付环境为 Linux，无法真实访问：

- AppKit/SwiftUI macOS runtime；
- EventKit TCC permission；
- 用户 iCloud Reminders；
- 用户 Multica Cloud account/profile；
- iPhone push notification；
- SMAppService login item runtime。

因此以下不是“代码待实现”，而是**环境依赖的最终验收**：

- [ ] `make mac-app` 在用户 Mac 编译通过。
- [ ] Reminders 权限授权。
- [ ] Test Reminder 创建并同步 iPhone。
- [ ] absolute alarm 在 iPhone 产生 Reminders notification。
- [ ] 真实 Multica `in_review` 唯一投影。
- [ ] deep link 打开正确 Issue。
- [ ] rework/re-review/done 真实状态流验证。
- [ ] Run at Login 验证。

统一命令：

```bash
./scripts/verify-macos.sh
```

## 11. v1 明确不做 / 后续可选

这些不是当前可用性的缺口：

### Optional: MulticaApiSource

收益：

- 无需 spawn CLI；
- 精确 HTTP retry/rate-limit/pagination；
- 最终用户可不安装 CLI；
- 易于未来接官方 stable event/realtime API。

前提：固定并契约测试所需 REST endpoints；PAT 放 macOS Keychain。

### Optional: SemanticAttentionClassifier

只在 blocked/input-required 的结构化字段不足时考虑。默认关闭，不应成为普通 review 判断主路径。

### Optional: explicit mobile review actions

未来可做“Open / Approve / Request changes”的 Shortcut/deep link，但不能把 Reminders checkbox 直接映射为 Multica done。

## 12. Release Gate

v1 可发布给个人使用前的 gate：

```text
[x] core tests green
[x] secret scan green
[x] Git history initialized
[ ] real Mac app build green
[ ] EventKit permission green
[ ] iCloud test Reminder green
[ ] real Multica in_review E2E green
```

前 3 项已在本交付环境验证。后 4 项由 `verify-macos.sh` 在目标 Mac 完成。

---

## 13. v0.2 设计：Apple Reminders -> Multica Dispatch

v0.1 只实现 `Multica -> Apple Attention`。v0.2 计划增加 `Apple -> Multica Request`，完整设计见 [APPLE_TO_MULTICA_DISPATCH.md](APPLE_TO_MULTICA_DISPATCH.md)。

推荐信息模型：

```text
Agent Requests / Agent · <Project>   human -> agent capture
Agent Attention                      agent -> human review/unblock/failure
```

不使用 Apple Reminder subtasks、sections、list groups 或 tags 作为程序契约；EventKit 对这些 Reminders UI 能力没有完整公开 API。

### Phase A — Request domain / persistence

- [ ] `AgentRequestSnapshot`
- [ ] `DispatchRoute`
- [ ] `DispatchTarget = newIssue | continueIssue`
- [ ] `request_projection` SQLite migration
- [ ] payload hash / retry / restart idempotency

### Phase B — EventKit Request Source

- [ ] 扫描 allow-listed Request Lists
- [ ] 忽略 Bridge 自己的 Attention List
- [ ] 识别未完成、未消费 Request
- [ ] managed Notes block
- [ ] dispatch 成功后写 receipt + complete original Request
- [ ] 派发前用户 complete -> cancel local intent

### Phase C — Routing

- [ ] Settings 中配置 `Apple List -> Multica Project + Agent`
- [ ] 从 Multica 拉 Projects/Agents picker
- [ ] Generic `Agent Requests` List
- [ ] Notes `Project:` / `Agent:` override
- [ ] route ambiguity fail-closed
- [ ] 不把 local directory path 写入 Apple Reminders

### Phase D — Multica Issue Dispatch

- [ ] create Issue with project/assignee
- [ ] long description via stdin
- [ ] write issue deep link receipt
- [ ] `Continue: MUL-xxx`
- [ ] Multica Issue URL continuation
- [ ] follow-up via comment/@mention rather than raw provider session id

### Phase E — E2E

- [ ] iPhone create Request -> iCloud -> Mac Bridge -> Multica Issue
- [ ] Request completed receipt
- [ ] Issue `in_review` -> independent `Agent Attention` Reminder
- [ ] rework -> second review generation
- [ ] project routing with local-directory resource
- [ ] duplicate/restart/CLI-timeout does not double-create Issue

### Explicitly deferred

- [ ] arbitrary private Multica Chat browser/continuation (CLI is not a stable arbitrary-chat management surface)
- [ ] Apple Reminder tags as routing contract
- [ ] Apple subtasks/groups/sections
- [ ] raw Codex/Claude session ID selection
- [ ] Reminder checkbox -> Multica approval/done
