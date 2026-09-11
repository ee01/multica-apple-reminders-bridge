# Apple Reminders <-> Multica Dispatch & Attention Design

> 日期：2026-09-11
>
> 状态：v0.2 Design Revision 2；当前可运行代码仍为 v0.1（Multica -> Apple Attention），本文件定义下一阶段双向实现。
>
> 核心原则：**一个 Multica Issue 对应最多一个活跃 Apple Reminder 投影；Reminder 在不同 List 之间迁移，而不是为 Request / Review / Rework 各复制一条。**

## 1. 设计目标

Bridge 要同时支持两条方向：

```text
Apple Reminders                       Multica
----------------                      ----------------
用户随手创建 Agent Request   ------>  Issue / Run
用户需要 Review/解阻         <------  Issue / Run 状态
```

Apple Reminders 负责：

- 捕捉“我想交给 Agent 做”的意图；
- 在 iPhone / iPad / Mac 上提示“现在轮到我了”；
- 提供项目、摘要、产物提示和 Multica 深链。

Multica 负责：

- Project / resource / local_directory；
- Issue；
- Agent / runtime；
- Run；
- comments / attachments；
- 完整执行和 Review 上下文。

Bridge 负责：

- Apple Reminder 与 Multica Issue 的身份映射；
- dispatch routing；
- AttentionPolicy；
- EventKit List 迁移；
- 去重 / 恢复 / 状态协调。

---

## 2. 不使用 Subtask：原因不只是 EventKit 限制

Apple Reminders UI 支持 subtask，但截至 2026-09-11，EventKit 没有公开 API 获取 `EKReminder` 的 subtask 关系；Reminder List 的 group/folder/section 也不能作为稳定程序接口。

但即使 Apple 将来开放 subtask，本 Bridge 也不建议把 Agent 生命周期建模成：

```text
Request
  |- Agent running
  |- Review round 1
  |- Rework
  `- Review round 2
```

原因更本质：

- `running / review / rework` 是**同一个工作项的状态**，不是任务拆分；
- Multica 本身已经用一个 Issue + 多个 Run 表达这件事；
- 把 lifecycle 伪装成 subtask 会制造重复状态源；
- 一个“已完成 Request”下面挂一个“未完成 Review”在人的待办语义上也很别扭。

所以采用：

```text
1 Multica Issue
      <->
0..1 active Apple Reminder projection
```

---

## 3. Apple List 模型：Capture、Work、Attention

Bridge 管理三个概念层。

### 3.1 Agent Requests：捕捉入口

至少存在一个通用 List：

```text
Agent Requests
```

用户在 iPhone/Mac 创建 Reminder，即表示：

> 把这件工作委派给 Agent。

可以另外为少数高频项目配置 Route List：

```text
Agent · Personal AI
Agent · Website
Agent · Infra
```

这些 List 只是“快速项目选择器”，不是 Multica Project 的镜像。

### 3.2 Agent Work：Bridge 管理的非人类等待区

新增一个 Bridge-managed List：

```text
Agent Work
```

成功 dispatch 后，**原来的同一条 Reminder 不标记完成**，而是移动到 `Agent Work`：

```text
Agent · Personal AI
  修复 Ask skip
       |
       | dispatch success
       v
Agent Work
  修复 Ask skip · MUL-381
```

此时 Bridge：

- 清除“现在提醒我”的 alarm；
- 保留/记录 Issue deep link；
- 在 Notes managed block 写入 project / agent / issue / 当前状态；
- 不把 running progress 逐条塞进 Reminder。

这样 Reminder 仍然代表同一件工作，但不会污染人的 Attention 队列。

### 3.3 Agent Attention：现在轮到人

当 Multica Issue 进入真正的人类注意状态：

```text
in_review
blocked + human required
unrecoverable failure
input_required
```

Bridge 把**同一条 Reminder**移动到：

```text
Agent Attention
```

并设置：

- title 前缀：`Review / Unblock / Check`；
- compact summary；
- priority；
- EventKit alarm；
- Multica Issue URL；
- artifact manifest 摘要。

当人类动作结束、Agent 又开始工作时，再把同一条 Reminder 移回 `Agent Work`。

终态：

```text
Multica done / cancelled
     -> mark the same Reminder completed
```

因此 Apple 中的一个 Reminder 与 Multica 的一个 Issue 生命周期连续对应。

---

## 4. 完整状态机

```text
             Apple capture
                  |
                  v
        [Agent Requests / Project Route]
                  |
          dispatch succeeds
                  |
                  v
              [Agent Work]
                  |
       Multica needs a human
                  |
                  v
           [Agent Attention]
            /             \
           /               \
   human requests rework    human accepts
         /                       \
        v                         v
  [Agent Work]               completed
        |
    next review
        |
        +----------> [Agent Attention]
```

### 4.1 Attention 不会因为用户从 Multica 直接 Review 而积压

Bridge 必须做**双向 reconciliation**。

例如用户没有从 Apple Reminder 打开，而是直接打开 Multica：

```text
MUL-381 = in_review
Apple    = Agent Attention
```

用户在 Multica：

```text
Request changes -> new run / in_progress
```

Bridge 下一轮同步看到：

```text
active run exists OR issue leaves in_review
```

立即：

```text
Agent Attention -> Agent Work
clear attention alarm
```

如果用户确认完成：

```text
MUL-381 -> done
```

Bridge：

```text
mark Apple Reminder completed
```

所以 `Agent Attention` 只应包含**此刻仍轮到人的任务**。

### 4.2 Multica 状态没有变化时怎么办

Multica 官方说明：Run 完成不会自动等于 Issue done；Agent 会显式写 `in_review`，`done` 通常由人工确认。

因此如果用户只在 Multica 看过结果，但：

- 没有改 Issue status；
- 没有触发新的 Run；
- 没有把 Issue 设为 done；

Bridge 无法可靠知道“Review 已经结束”。这种情况下 Attention 保持是正确行为。

如果用户评论并 @Agent 触发新 Run，但 Issue 仍暂时保持 `in_review`，Bridge 应优先看 **active Run**：

```text
in_review + active agent run
    => agent_working
    => move to Agent Work
```

避免 Review Reminder 在 Agent 已经返工时继续显示。

---

## 5. Project / 代码目录选择

### 5.1 Apple 只选择 Multica Project，不选择 raw path

Multica Project Resource 已经负责：

```text
Project
  |- Git repository
  `- local_directory on daemon A/B
```

同一 Project 在不同 daemon 上甚至可以绑定不同本地目录。因此 Apple 不保存：

```text
/Users/foo/code/project
```

只保存/解析：

```text
Multica Project ID / alias
```

### 5.2 Route List 在 Bridge Settings 配置

Bridge Settings：

```text
Apple Request List          Multica Project      Default Agent
----------------------------------------------------------------
Agent · Personal AI         Personal AI          Coding Agent
Agent · Website             Website              Frontend Agent
Agent · Infra               Infra                DevOps Agent
```

所以用户选择 Apple List 就完成了最常见的 project routing。

### 5.3 不要求每个 Project 都建一个 List

推荐规则：

- 2~5 个高频 Project：建立 Route List；
- 其他偶发 Project：走 `Agent Requests`；
- 不自动为 Multica 的所有 Project 镜像 Apple List。

Bridge Settings 增加：

```text
Projects
Personal AI   [Pin to Reminders]  -> Agent · Personal AI
Website       [Pin to Reminders]  -> Agent · Website
Data Tools    [not pinned]
```

这样 Apple Reminders 不会被几十个 Project List 污染。

### 5.4 Generic Agent Requests 如何选择 Project

第一版 fallback：

```text
Bridge default project
```

如果没有默认或无法安全判断：

```text
do not dispatch
mark as needs_route
notify on Mac
```

长期可增加一个 Apple Shortcut / Share workflow 提供菜单式项目选择，但不把 EventKit tag 当机器契约。

---

## 6. Continue Existing Work：不要要求手输 `Continue: MUL-381`

`Continue: MUL-381` 只保留为调试/高级语法，不作为正常用户 UX。

### 6.1 最优先：Multica Issue URL

如果 Reminder 的 `URL` 是 Multica Issue URL：

```text
https://multica.ai/<workspace>/.../MUL-381
```

Bridge 自动解析：

```text
intent = continue_existing_issue
issue  = MUL-381
```

用户不需要记 key。

### 6.2 从已有 Agent Reminder 继续，不需要任何 ID

更重要的是：采用“一 Issue 一 Reminder”以后，绝大多数 continuation 根本无需新建 Reminder。

例如：

```text
Agent Attention
Review · Personal AI · Ask Skip
URL = MUL-381
```

用户点开 Multica，在同一个 Issue 中评论/Request Changes；Bridge 自动跟随状态：

```text
Attention -> Work -> Attention
```

所以正常 rework workflow 完全没有 `Continue:` 输入。

### 6.3 用户主动从 Apple 新建“继续旧任务”

推荐体验：

```text
Multica Web/Desktop/iPhone browser
  -> Copy/Share Issue URL
  -> Add to Reminders / Agent Requests
  -> 用户只写新的要求
```

Bridge 看到 Multica URL 后，把 Reminder 内容作为该 Issue 的 follow-up comment / Agent trigger，而不是创建新 Issue。

### 6.4 可选后续：Recent Work picker

若以后需要更顺滑，可实现 macOS Bridge 的：

```text
New Agent Request
  Project: Personal AI
  Continue: [Recent Multica Issues...]
```

移动端若要做到无 token 的“最近 Issue picker”，更适合通过专门的 Shortcut/轻量 companion 实现；不建议把 Multica PAT 塞进普通 Apple Shortcut。

---

## 7. 历史 Chat continuation

### 7.1 Issue conversation：支持

Multica Issue 本身已经包含：

- description；
- comments；
- previous runs；
- provider session reference。

同一 Issue 后续 Run 会尽量恢复 provider session，不能恢复时由 Multica 创建新 session。

因此 Bridge 的正常 continuation target 是：

```text
Multica Issue
```

而不是 raw Codex / Claude Code session id。

### 7.2 Multica private Chat：暂不纳入 v0.2 核心

当前 CLI 的 `multica chat` 不是浏览 arbitrary Workspace private Chat 的通用 contract。因此：

```text
v0.2 target = new issue | existing issue
```

未来 Direct API adapter 若有稳定 Chat API，再增加：

```text
existing_chat
```

---

## 8. Artifact Review：Apple Reminder 应该提供什么

原则：

> Reminder 是 Review launcher，不是 artifact storage/viewer。

EventKit 可靠提供的是 title、notes、URL、alarms、due/priority 等；不要依赖没有公开 Reminder attachment API 的能力，把文件强行复制到 Reminder。

### 8.1 Attention Reminder 内容

例：

```text
Review · Personal AI · Architecture proposal

Multica: MUL-421
Project: Personal AI
Agent: Claude Code

Result:
完成架构方案，需要人工确认 3 个决策。

Artifacts:
- architecture.md
- migration-plan.pdf
- review-deck.pptx

Primary review: Open Multica
```

`URL` 永远优先放**稳定的 Multica Issue deep link**。

原因：Multica Issue 是持久上下文；临时 attachment download URL 可能过期，不适合存进长期 Reminder。

### 8.2 Markdown

如果 Agent 的主要结果已经写在 Multica comment / result 中：

- Apple Notes 放 3~10 行 summary；
- Reminder URL 打开 Multica Issue；
- 用户在 Multica 直接看 Markdown/rendered discussion。

### 8.3 PDF / PPT / Office 文档

Multica comments 支持 attachments，CLI 也支持 attachment upload/download。

推荐：

```text
Reminder
  -> show artifact names/count + summary
  -> URL opens Issue
  -> user taps attachment
  -> iPhone/macOS opens PDF/PowerPoint/Keynote/Files as appropriate
```

不把文件本体复制进 Apple Reminder。

### 8.4 Primary Artifact 快捷打开（可选 v0.3）

如果 Direct API 能稳定取得**可长期访问**的 artifact link，可增加：

```text
Primary Artifact: migration-plan.pdf
```

但 Reminder 的唯一 `URL` 默认仍指向 Issue；如果要一键打开 primary artifact，更适合在 Notes managed block 中附链接，或由 Bridge companion UI 提供 `Open Primary Artifact`。

不要把短时 signed download URL 作为 Reminder 的长期主 URL。

### 8.5 Artifact 摘要来源

Bridge 不必自己用 LLM 重新读 PDF/PPT。

优先：

```text
latest Agent result / final comment summary
+ attachment names/types
```

如未来要做智能 artifact digest，再作为 optional classifier，而不是 v0.2 dispatch 的前置能力。

---

## 9. 一条 Reminder 的 managed metadata

Reminder 用户正文与 Bridge managed block 分离：

```text
用户输入正文，可自由编辑。

--- Multica Bridge ---
Bridge-ID: brg_...
Issue: MUL-381
Issue-ID: ...
Project: Personal AI
Agent: Coding Agent
State: agent_work | attention_review
Source-List: Agent · Personal AI
Last-Sync: 2026-09-11T16:45:00+08:00
Open: https://multica.ai/...
```

SQLite 仍是主要 identity store；managed block 用于 EventKit identifier 因 full sync 失效后的恢复。

Apple 官方说明 `calendarItemIdentifier` 在 full sync 后可能失效，因此必须保留可恢复锚点。

---

## 10. Identity / Projection 模型

建议数据表从“review cycle -> reminder”升级成“issue -> reminder projection”：

```sql
CREATE TABLE issue_projection (
  issue_id TEXT PRIMARY KEY,
  issue_key TEXT NOT NULL,
  reminder_calendar_item_id TEXT,
  bridge_ref TEXT NOT NULL UNIQUE,
  source_request_list_id TEXT,
  current_list_role TEXT NOT NULL,
  current_attention_reason TEXT,
  review_generation INTEGER NOT NULL DEFAULT 0,
  last_issue_status TEXT,
  last_active_run_id TEXT,
  last_payload_hash TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
```

`review_generation` 仍保留做诊断/历史，但不再为每轮 Review 创建一条新的 Apple Reminder。

---

## 11. Reconciliation 优先级

每次 sync：

```text
1. Multica terminal state?
   -> complete Reminder

2. Active agent Run?
   -> Agent Work

3. Issue status category = in_review?
   -> Agent Attention

4. blocked/failure human-required?
   -> Agent Attention

5. still-open normal agent work?
   -> Agent Work
```

重要：

```text
active Run > stale in_review presentation
```

用于处理人类在 Multica 评论并触发 rework、但 status 还未马上改变的情况。

---

## 12. 用户直接操作 Apple Reminder

### 12.1 在 Agent Work 中手工完成

默认不把 Multica Issue 设 done。

Bridge 记录：

```text
user_suppressed_projection = true
```

后续除非出现新的高优 Attention 或用户选择恢复，否则不死循环重新打开。

### 12.2 在 Agent Attention 中手工完成

同样不解释为“批准结果”。

只表示：

> 不要再用 Apple Reminders 提醒我这一轮/这个投影。

Multica 仍权威。

### 12.3 在 Multica Review

这是推荐的真正业务操作位置：

```text
Approve -> done
Request changes -> new run / work state
Comment + @Agent -> new run
```

Bridge 只是跟随并移动 Apple Reminder。

---

## 13. 典型真实场景

### A. 手机随手派一个新 coding task

```text
iPhone
Agent · Personal AI
“Ask 的 verification 加 Skip，并补测试”
        |
        v
Bridge -> Multica Personal AI Project -> Coding Agent
        |
        v
same Reminder -> Agent Work
        |
        v
Agent delivers -> in_review
        |
        v
same Reminder -> Agent Attention + alarm
```

### B. 用户直接在 Multica Review

```text
Apple Attention exists
User ignores Apple and opens Multica directly
Request Changes
Agent run starts
Bridge next sync
Attention -> Agent Work
```

没有旧 Review 残留。

### C. 第二轮 Review

```text
Agent Work
 -> agent delivers again
 -> same Reminder moves back to Agent Attention
```

不创建 `Review #2` 垃圾条目，但 `review_generation=2` 保留在 Bridge DB/Notes receipt。

### D. 多项目

```text
Agent · Personal AI -> Personal AI Project -> Coding Agent
Agent · Website     -> Website Project     -> Frontend Agent
Agent Requests      -> default/fallback route
```

所有真正轮到人的工作仍统一进入：

```text
Agent Attention
```

因为它回答的是“我现在要处理什么”，而不是“属于哪个项目”。

### E. 继续已有 Multica Issue

用户从 Multica 复制/分享 MUL-381 URL 到新 Reminder，只写：

```text
再补 Windows path 测试
```

Bridge 识别 URL：

```text
continue MUL-381
```

不要求手输 Issue key。

### F. 文档 / PDF / PPT 交付

Agent 在 Multica Issue 中交付：

```text
architecture.md
review.pdf
proposal.pptx
```

Apple Attention：

```text
Review · Proposal package
3 artifacts · 2 decisions required
[Open Multica]
```

手机进入 Cloud Issue 后直接查看/下载附件。

### G. Agent 失败但会自动 retry

```text
failed -> retry active
```

Reminder 保持 `Agent Work`，不骚扰用户。

若：

```text
failed + no retry + human action required
```

移动到 `Agent Attention`。

### H. Multica 原生创建的 Issue

如果某 Issue 不是从 Apple 发起：

```text
Multica-created Issue
 -> in_progress: Apple 无投影（默认）
 -> first human Attention: Bridge 创建一条 Reminder in Agent Attention
 -> rework: same Reminder moves to Agent Work
 -> done: complete Reminder
```

所以 Bridge 不会把整个 Multica Board 镜像进 Apple。

---

## 14. 最终产品心智

Apple 中不是两套互不相关的 Request / Review 票据，而是一条工作投影在不同“人的状态”之间移动：

```text
Capture     -> Agent Requests / project route
Delegated   -> Agent Work
Your turn   -> Agent Attention
Finished    -> completed
```

Multica 仍然是实际 Agent Work Source of Truth。

一句话：

> **同一个工作项，在 Multica 里用 Issue/Run 推进；在 Apple Reminders 里用同一条 Reminder 的 List 位置表达“现在是谁的回合”。**

---

## 15. 参考资料

### Apple

- EventKit / EKReminder: https://developer.apple.com/documentation/eventkit/ekreminder
- `EKCalendarItem.calendar` 可读写: https://developer.apple.com/documentation/eventkit/ekcalendaritem/calendar
- `EKCalendarItem.url`: https://developer.apple.com/documentation/eventkit/ekcalendaritem/url
- `calendarItemIdentifier` full sync 注意事项: https://developer.apple.com/documentation/eventkit/ekcalendaritem/calendaritemidentifier
- EventKit 不提供 EKReminder subtask API（Apple DTS）: https://developer.apple.com/forums/thread/820848

### Multica

- Issues: https://multica.ai/docs/issues
- Runs: https://multica.ai/docs/tasks
- Projects: https://multica.ai/docs/projects
- Project resources: https://multica.ai/docs/project-resources
- Comments / attachments: https://multica.ai/docs/comments
- Providers / session resumption: https://multica.ai/docs/providers
- CLI: https://multica.ai/docs/cli
