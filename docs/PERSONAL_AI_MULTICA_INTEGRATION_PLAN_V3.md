# Personal AI × Multica Integration Plan v3 — Boundary Update

> 日期：2026-09-11
> 目的：根据 Personal AI 当前 executor 能力与 Multica Cloud 使用方式，收缩 Multica 在 Personal AI 中的职责，并把 Apple Reminders Bridge 完全解耦。

## 1. 最终边界

```text
Personal AI
├── Memory / Reflection / Dream / Ask verification
│   └── Personal AI native executor registry
│       ├── OpenClaw
│       ├── ACP Codex
│       ├── ACP Claude Code
│       └── remote worker
│
└── Task Center
    ├── Bot / AsMe
    ├── AI Report
    ├── Outreach
    └── scheduled/conditional AgentTask
        └── Personal AI native executor registry

Multica Cloud
└── 可选 Agent Workbench
    ├── 手工/长期 Agent Issues
    ├── Board
    ├── multi-run discussion
    └── deep human review

Independent Apple Reminders Bridge
└── Multica Cloud human-attention state
    → Apple Reminders
```

## 2. 不再把 Multica 作为 Personal AI 默认 Executor Plane

原因：Personal AI 当前 develop 已有统一 executor registry、ACP Codex/Claude Code、local/remote runtime、reflection_research 默认 executor、AgentTask 与结果通知拆分。

因此：

- Reflection verification 不需要经 Multica；
- Ask verification 不需要经 Multica；
- Scheduled/conditional AgentTask 不需要迁移到 Multica Autopilot；
- Personal AI Task Center 继续是所有定时推送/AgentTask 的统一 schedule source of truth。

## 3. Multica 仅在“工作项需要长期协作/Review”时有增量价值

适合：

```text
investigation
→ result
→ human review
→ add comments
→ rerun
→ code/change review
→ done
```

不适合仅为了：

```text
一次快速 fact check
普通 Reflection evidence lookup
Ask synchronous verification
每小时后台检查
Bot/AI Report schedule
```

## 4. Personal AI「帮我做」保留范围

保留：

- scheduled AgentTask；
- conditional AgentTask；
- 带 Personal AI notification/outcome policy 的 AgentTask；
- 从 Personal AI 内部 domain 触发的自动执行。

普通、一次性、纯 coding Agent work 可直接在 Multica 创建，不强制绕 Personal AI。

## 5. Apple Reminders 不通过 Personal AI

Apple Reminders Bridge 独立：

```text
Multica Cloud
→ Bridge on macOS
→ EventKit
→ Apple Reminders
```

Personal AI 不承担：

- Multica Review mirror；
- Apple Reminder projection；
- Multica PAT；
- Bridge state database。

这样 Multica 与 Personal AI 可以分别升级，Apple Bridge 也能独立发布。

## 6. Multica Cloud 使用方式

不 self-host。

用户可二选一：

```text
Multica Desktop
→ 自动管理本机 daemon
→ Cloud
```

或：

```text
Multica Web
+ official CLI daemon
→ Cloud
```

Bridge 始终只读取 Cloud 工作状态，与 daemon 独立。

## 7. Apple Reminder 规则不进入 Agent prompt

不应给每个 Multica Issue 加：

> 完成后帮我创建 Apple Reminder。

Bridge 使用：

```text
Issue/Run status
→ deterministic AttentionPolicy
→ Reminder
```

`in_review` 是最主要的 human-review signal；特殊情况使用 labels/project policy，语义 classifier 只作为后期 fallback。

## 8. 对原 Plan 的替代决策

以下旧方向降级/取消：

- ❌ Personal AI 默认 `MulticaExecutionProvider` 作为 AgentTask 主路径；
- ❌ Personal AI schedule 同步到 Multica Autopilot；
- ❌ Personal AI 内实现 Multica Review mirror；
- ❌ Personal AI → Apple Reminders attention routing 作为 Multica 的必经链；
- ❌ 为 Apple Reminders fork/self-host Multica。

保留：

- ✅ Multica 作为独立 Agent Board / Review Workspace；
- ✅ 必要时 Personal AI 可以显式“升级为 Multica Issue”（未来可选）；
- ✅ Multica Cloud 统一多机器 Agent work；
- ✅ Apple Reminders Bridge 作为独立 sidecar。

## 9. 下一步

1. 先日常使用 Multica Cloud + Desktop/Web，验证 Board/Review 是否真正改善 Codex/CC 多 session 管理。
2. 并行实现独立 Apple Reminders Bridge 的 Phase 0~P5。
3. Personal AI 优先投资 Ask/Reflection 共用 VerificationOrchestrator，而不是 Multica executor integration。
4. 等 Multica 长期使用习惯稳定后，再决定是否做 Personal AI → Multica Issue escalation adapter。


## 10. 2026-09-11 Bridge implementation receipt

独立仓库 `multica-apple-reminders-bridge` 已按上述边界实现 v1 主路径：

```text
Multica Cloud
→ independent Multica CLI profile
→ deterministic AttentionPolicy
→ SQLite reconciliation
→ EventKit Reminder projection
```

它没有新增 Personal AI runtime 依赖，也不会启动/控制 Multica daemon。Personal AI 后续仍只需把 Multica 视为可选长期 Agent Workbench；Apple Reminders bridge 的版本、认证和 projection state 均留在独立项目。

当前自动测试覆盖核心同步状态机；EventKit/TCC/iCloud 和真实 Multica Cloud E2E 由该 Bridge 仓库的 `scripts/verify-macos.sh` 在目标 Mac 完成。
