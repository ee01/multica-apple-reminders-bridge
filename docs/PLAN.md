# Multica Cloud × Apple Reminders Bridge — v0.3 Implementation Plan & Status

> 日期：2026-09-13
> 部署：Multica Cloud + Web/Desktop；不 self-host
> 默认 Mirror Mode：`apple_origin_only`
> 状态：**Phase A–F implemented；真实 macOS/iCloud/Cloud interactive acceptance pending**

## 0. 最终目标

```text
Apple Reminders                     Multica Cloud
────────────────────────────────────────────────────────
Project Request/Main   <--------->  Issue
Human Action sibling  <-----------  Review / Action Required / Failed
                                      |
                                      v
                                Desktop daemon
                                Codex / Claude
```

设计原则：

1. Main Reminder 始终留在原 Project List；不用 List 移动表达 ownership。
2. Human Action 只有三种简单类型：Review / Action Required / Failed；都与 Main 同 List。
3. Human Action sibling 才设置近期 alarm；Main 不由 Bridge 设置提醒时间。
   - `Review` 只表示最终交付验收；默认勾选可关闭整个 Issue。
   - 仍需用户输入、修复、授权或恢复后继续执行的场景使用 `Action Required` / `Failed`，其 checkbox 只 acknowledgement。
4. 默认 `apple_origin_only`。
5. Multica 是 Issue/Run 权威；Review checkbox 在严格门禁下可作为显式 approval，其余 checkbox 不直接 mutate Multica。
6. 用户可完全绕过 Apple、直接在 Multica Review；Bridge 必须自动 reconciliation。

---

## Phase A — Domain Model & Persistence ✅

已实现：

- `MirrorMode`: `apple_origin_only | all_active | attention_only`；
- `IssueOrigin`: `apple | multica`；
- `IssueBinding`：Issue ↔ route/project/list；
- `ReminderProjectionKind`: `main_issue | human_action`；
- `HumanActionKind`: `review | action_required | failed`；v0.2 `unblock/failure/explicit` 自动迁移；
- `AgentRequestRecord`；
- `ProjectRoute`；
- SQLite v2 tables：binding / request / observation / projection；
- v0.1 best-effort migration；
- `apple_origin_only` 作为 config decode/init 默认值。

Main 和 Human Action 独立持久化：

```text
MUL-381
├─ main_issue / generation 0
└─ human_action / generation 1..N
```

---

## Phase B — Project Projection Policy ✅

Project Route：

```text
Apple List -> Multica Project -> Default Agent -> Mirror Mode
```

策略：

| Mode | Apple-origin Main | Multica-origin Main | Human Action |
|---|---:|---:|---:|
| apple_origin_only | yes | no | yes |
| all_active | yes | yes while active | yes |
| attention_only | no | no | yes |

无 Project binding 时使用 `Agent Requests` fallback。

---

## Phase C — Apple Request -> Multica Issue + Main ✅

已实现：

1. EventKit 扫描 generic/project request Lists 中未被 Bridge 管理的 Reminder；
2. List route 解析 Project + Agent；
3. 创建 Multica Issue；
4. assign Agent；
5. 原 Apple Reminder receipt 被直接复用为 Main projection；
6. Main 不移动 List、不完成；
7. Notes/URL 更新为 Multica receipt/deep-link；
8. request marker `Apple Bridge request: <id>` 写入 Issue description；
9. crash recovery 先 search marker，避免重复创建；
10. 若 Issue 已创建但 assign 尚未完成，恢复路径会补 assign；
11. Multica Issue URL 作为 Apple-side continuation：comment existing Issue，而不是 create duplicate；
12. 若 existing Issue 尚无 assignee，先 `assign --no-start` 绑定 route default Agent，再 add comment，避免双 Run。

Main completion 并不代表 Multica completion，见 Phase F。

---

## Phase D — Project-local Human Action sibling ✅

当结构化状态判断“轮到人”时：

```text
Agent · Personal AI
○ 修复 Ask verification                 Main
○ Review: 修复 Ask verification 🔔      Human Action sibling
```

已实现：

- Review sibling；
- blocked grace 后 Action Required sibling；
- 最终失败且没有更新 active retry 时 Failed sibling；
- Run failure reason code 写入 Failed Notes；
- 与 Main 使用同一 `appleListName`；
- Human Action 默认 absolute alarm；
- Main 无 Bridge-managed alarm；
- same cycle 幂等；
- generation-based multi-review；
- Multica-origin + `apple_origin_only`：不建 Main，但需要人时仍建 sibling。

---

## Phase E — Direct Multica Reconciliation ✅

用户不需要从 Apple 开始 Review。

已实现优先级：

```text
terminal
  > active Run
  > in_review
  > blocked/failure
```

因此：

- 用户直接在 Multica Request Changes / comment-triggered rework：active Run 出现后，旧 Review sibling 自动 resolve；Main 保留；
- 即使 Issue status 暂时仍为 `in_review`，active Run 仍优先，避免 Attention 假阳性；
- 同一 rework Run 完成且 Issue 仍 `in_review`：识别为新的 review generation；
- Multica `done/cancelled`：Main + active Human Actions 一起 resolve；
- closed Issue 从 `issue list` 消失时，对 active projection 逐项 `issue get` 校准，不把查询空集错误解释为完成。

---

## Phase F — Apple Completion Semantics ✅

### Main

用户完成或删除 Main：

```text
mainProjectionDismissed = true
projection = acknowledged
```

Bridge 不再重建该 Main，但**不会写 Multica Issue done/cancelled**。

如果 Issue 后续需要人：Human Action sibling 仍正常创建。

### Human Action

Human Action completion semantics：

```text
Review complete
→ 默认 approve current delivery
→ strict guards
→ multica issue status <issue> done
→ Main + Review resolve

Action Required / Failed complete
→ acknowledge only
→ no status mutation / no retry
```

删除 Review 仍只表示 dismiss，不是 approve。若 `reviewCompletionBehavior=acknowledge_only`，Review 也回到旧的 acknowledge-only 语义。

同一 cycle 不重建；发生真实 rework + 新 delivery 后创建下一 generation。

### Settings UI

已实现：

- Generic request list；
- default Mirror Mode（默认 apple_origin_only）；
- fallback Project / Agent；
- Project Route CRUD；
- route-level mirror mode；
- Workspace/project/agent catalog；
- Reminders permission/test；
- Human Action alarm；
- poll/grace/failure；
- Run at Login。

---

## v0.3 Human Action refinement ✅

本轮从 v0.2 继续完成：

1. 不注入 Agent System Prompt / Skill；Bridge 只消费 Issue + Run 结构化状态。
2. `blocked` 统一投影为 **Action Required**。
3. 最终 failed Run 且没有更新 active retry 时投影为 **Failed**；覆盖 runtime offline retry exhausted、queued_expired、auth/quota/config/environment 等失败。
4. stale failed snapshot 会先 `issue runs` 校准，避免已有 queued/running retry 时误报 Failed。
5. stale `in_review` 也会用 Runs 校准，active rework 优先。
6. Review checkbox 默认成为显式 approval：严格门禁后执行 `multica issue status <issue> done`；Cloud status write 失败会重新打开 Review Reminder。
7. Action Required / Failed checkbox 只 acknowledgement，不自动重跑或解除 blocked。
8. 首次同步自动 `ensureLists()`：创建 `Agent Requests` 和所有配置的 Project Route Lists。

详细决策见 [HUMAN_ACTION_V0.3_PLAN.md](HUMAN_ACTION_V0.3_PLAN.md)。

---

## 测试矩阵

自动测试覆盖至少包括：

- config backward compatibility + default mirror mode；
- project policy 三种 mode；
- Apple Request dispatch；
- original Reminder -> Main；
- URL continuation；
- create crash idempotency；
- recovered assignment；
- Main + Review sibling；
- Multica-origin human-only default；
- all_active；
- blocked/failure；
- direct Multica rework；
- stale in_review + active Run；
- second review generation；
- Multica done；
- Main Apple completion/delete semantics；
- Review approval-to-done 严格门禁与失败回滚；
- Action Required / Failed acknowledgement-only semantics；
- SQLite restart；
- closed-list recovery；
- CLI login never starts daemon；
- pagination/parser/process timeout/large output。

最终数量与命令结果见 [VERIFICATION.md](VERIFICATION.md)。

---

## 仍需真实 macOS 验收

当前交付环境不是用户的真实 Mac/iCloud/Multica Cloud，因此不能伪报：

- EventKit TCC permission；
- iCloud Reminders 实际同步；
- iPhone alarm notification；
-真实 Multica CLI create/assign/comment 项目流；
- SwiftUI Settings 真实交互；
- `SMAppService` login item。

运行：

```bash
./scripts/verify-macos.sh
```

---

## 不在 v0.3 的范围

- Apple Reminders assignee / Assigned to Me（EventKit 无稳定写接口）；
- Reminders subtask（EventKit 无公开 parent/subtask API）；
- UI Automation/private database workaround；
- arbitrary Multica private Chat continuation；
- Direct REST `MulticaApiSource`；
- LLM Attention classifier；
- artifact direct-link capability URL。

这些都不影响 Phase A–F 的完整工作流。
