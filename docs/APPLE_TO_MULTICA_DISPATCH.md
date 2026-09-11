# Apple Reminders -> Multica Dispatch Design

> 日期：2026-09-11
>
> 状态：Design for v0.2; v0.1 当前只实现 Multica -> Apple Attention projection
>
> 核心原则：**Apple Reminders 是 Human Action / Capture UI；Multica 是 Agent Work Source of Truth。**

## 1. 为什么需要第二条方向

v0.1 只解决：

```text
Multica Issue / Run
      ↓
需要人工 Review / 解阻 / 恢复
      ↓
Apple Reminder
```

v0.2 增加反方向：

```text
Apple Reminder
      ↓
用户想把一件工作交给 Agent
      ↓
Bridge Dispatch Policy
      ↓
Multica Issue / Comment-triggered follow-up
```

两个方向必须保持语义对称但数据权威不对称：

```text
Apple -> Multica : capture / dispatch intent
Multica -> Apple : human-attention projection

Multica remains authoritative for Agent work lifecycle.
```

## 2. 不使用 Apple Reminder 子任务作为主模型

Apple Reminders UI 支持 subtasks，但截至 2026-09-11，EventKit 没有公开 API 读取某个 `EKReminder` 的 subtask 关系。EventKit 同样没有公开的 Reminder List group/folder / section API 可以作为可靠集成契约。

因此 Bridge 不建立：

```text
Request Reminder
  ├── Agent running subtask
  ├── Agent completed subtask
  └── Review subtask
```

这在 Reminders UI 看起来漂亮，但程序端无法可靠维护。

推荐改成两个普通 List：

```text
Agent Requests     // human -> agent
Agent Attention    // agent -> human
```

用户可以在 Reminders UI 里手工把这些 List 放入一个 Folder/Group，但 Bridge 不读取、不创建、不依赖该 Folder。

## 3. Request 与 Attention 的生命周期

### 3.1 Request Reminder

用户创建：

```text
List: Agent · Personal AI
Title: 修复 Ask 外部查证无法跳过的问题
Notes: （可选）先补测试，再改实现
```

Bridge 看到一个未处理 Request 后：

```text
validate
  ↓
resolve route
  ↓
create Multica Issue
  ↓
assign Agent / start Run
  ↓
write receipt back to original Reminder
  ↓
mark Request Reminder completed
```

为什么 dispatch 成功后自动完成原 Reminder：

> 这条 Reminder 所表达的人类动作是“把工作委派出去”。成功提交 Multica 后，这个人类动作已经完成。Agent 的执行过程不是人的 pending todo。

原 Reminder 保留为 completed receipt，Notes 追加 Bridge 管理区：

```text
先补测试，再改实现

--- Multica Bridge ---
Status: Dispatched
Issue: MUL-381
Project: Personal AI
Agent: Coding Agent
Submitted: 2026-09-11 15:42
Open: https://multica.ai/...
Bridge ref: request/<uuid>
```

Bridge 只修改 marker 之后的 managed block，不改 marker 上方的用户 Notes。

### 3.2 Agent 正在执行

不持续更新 Apple Reminder：

```text
queued
running
waiting_local_directory
retrying
```

全部留在 Multica。

Apple Reminders 不做 progress tracker。

### 3.3 需要人工介入

Multica Issue：

```text
in_review
```

Bridge 在统一 `Agent Attention` List 新建：

```text
Review · Personal AI · Ask external verification skip

Codex 已完成第一轮实现。
2 个文件修改，27 tests passed。
Multica: MUL-381

[Open Multica]
```

这是一条新的 Human Action，而不是 Request 的 subtask。

### 3.4 Rework / 第二轮 Review

用户在 Multica：

```text
Request changes
  ↓
Agent rework
  ↓
in_review again
```

Bridge 创建下一轮 Attention Reminder：

```text
MUL-381 / review-generation-2
```

不复活原 Request。

## 4. Project / 代码目录应该如何选择

### 4.1 Apple 侧不要直接保存本地目录路径

不要让 Reminder 写：

```text
/Users/alice/Code/Personal-AI
```

原因：

- 路径是 machine-local，不适合 iCloud；
- 可能泄露用户目录结构；
- 同一 Project 在两台 daemon 上可以有不同路径；
- Multica 已经有更正确的 `Project -> Resources` 抽象。

Multica Project 可以绑定 Git repository 或某台 daemon 上的 `local_directory`。当 Issue 属于该 Project，Project description/resources 会进入 Run context；local directory 绑定由 Multica Desktop/daemon 负责。

所以 Apple Reminder 只选择：

```text
Multica Project
```

不选择 raw path。

### 4.2 推荐：Routing Lists

对经常使用的项目，在 Bridge Settings 建立路由：

```text
Apple List                  Multica Project     Default Agent
----------------------------------------------------------------
Agent · Personal AI         Personal AI         Coding Agent
Agent · Website             Website             Frontend Agent
Agent · Infra               Infrastructure      DevOps Agent
```

用户在 iPhone 只需要选择 Reminder List，就等价于选项目：

```text
Reminders
  Agent · Personal AI
    + 修复 Ask skip verification
```

Bridge 根据 EventKit `calendar` / List identity 路由：

```text
Agent · Personal AI
   ↓
projectId = <Personal AI>
agentId   = <Coding Agent>
```

这是移动端最省操作的方式。

### 4.3 为什么不使用 Apple Tags 作为主契约

Reminders UI 支持 `#tags` 和基于 tag 的 Smart Lists，但 EventKit 的公开 `EKReminder` / `EKCalendarItem` API 没有暴露 Reminders tag 字段。

因此：

- 用户当然可以自己使用 Apple tags；
- Bridge 不把 Apple tag 当机器可依赖的 project selector；
- 不通过逆向 Reminders SQLite 获取 tag。

### 4.4 大量/偶发项目：Generic Request List + Notes override

如果项目很多，不值得每个项目创建一个 Apple List：

```text
List: Agent Requests
Title: 检查登录模块 regression
Notes:
Project: Website
Agent: Backend Reviewer
```

Bridge 支持一个很小的 managed dispatch header：

```text
Project: <project alias>
Agent: <optional agent alias>
Continue: <optional MUL issue key>

<remaining text becomes task details>
```

优先级：

```text
explicit Notes override
    > routed List preset
    > Bridge default project/agent
```

如果 project/agent 无法唯一匹配，Bridge **不派发**，保留 Request 未完成，并加一个本地错误 receipt / macOS notification，让用户到 Bridge Settings 修复 route。

## 5. 新建 Issue 还是继续旧 Issue

Bridge 必须区分两种 intent。

### 5.1 默认：New Work

普通 Request：

```text
Title: 修复 Ask 外部查证无法跳过的问题
```

创建新 Multica Issue：

```bash
multica issue create \
  --title ... \
  --description-stdin \
  --project <project> \
  --assignee <agent>
```

Multica Issue 是长期工作单元，后续可以包含多次 Run。

### 5.2 Continue Existing Issue

用户希望继续已有 Agent 工作：

```text
Title: 再检查一下这个 patch 的 backward compatibility
Notes:
Continue: MUL-381
```

Bridge 不创建第二个 Issue，而是：

```text
resolve MUL-381
  ↓
validate access / current project
  ↓
add issue comment
  ↓
@mention configured/current agent
  ↓
new Multica Run against the same Issue
```

这样 Issue 的讨论、结果与 session continuation 都留在同一个工作记录中。

Multica 对同一 Issue 后续运行会尽量恢复原 AI coding-tool session；如果原 session 不可用，Multica 负责 fallback。Bridge **不保存、不选择 raw Codex / Claude session id**。

### 5.3 也可用 URL 作为 continuation target

如果 Apple Reminder 的 URL 字段已经是一个 Multica Issue URL：

```text
https://.../MUL-381
```

Bridge 可以把它解释为：

```text
Continue = MUL-381
```

这比要求用户记 Issue key 更友好。

## 6. “继续特定历史 Chat”应该怎么做

需要区分两个概念。

### 6.1 历史 Issue conversation —— v0.2 推荐支持

这是最应该支持的：

```text
Continue: MUL-381
```

Issue 的 comments + runs 本来就是长期上下文；Multica 还会尽量 resume 同一 provider session。

### 6.2 Multica private Chat —— 暂不作为 CLI v0.2 核心能力

Multica 也有独立 private Chat；同一 Chat 会尽量继续原 AI coding-tool session，也可以挂 Project context。

但是当前官方 CLI 的 `multica chat` 主要服务外部 chat integration，不是任意浏览/选择 Workspace private Chat 的通用 CLI contract。

因此 v0.2 不设计：

```text
Apple Reminder
 -> browse all Multica private chats
 -> pick arbitrary chat
 -> append message
```

未来有两个实现方向：

1. `MulticaApiSource` 验证并固定 private-chat API contract 后加入 `ChatTarget`；
2. 用户从 Multica Chat 分享/复制一个稳定 Chat deep link 到 Reminder URL，Bridge 只做 target resolution。

无论哪一种，都不要让用户选择 raw Codex/Claude session ID。session 生命周期是 Multica/runtime concern，不是 Apple Reminder domain。

## 7. Apple 侧推荐信息模型

### 7.1 List

```text
Agent Requests              // generic fallback
Agent · Personal AI         // optional route preset
Agent · Website             // optional route preset
Agent · Infra               // optional route preset

Agent Attention             // all projects, unified human queue
```

为什么 Attention 不按项目拆 List：

> Attention 是“今天轮到我做什么”，应该统一进入人的行动队列；Project 是上下文，不应该再次分裂人类 Review inbox。

Title 中带 compact project label：

```text
Review · Personal AI · Ask verification skip
Unblock · Website · OAuth regression
```

### 7.2 Notes

Request 用户可编辑区：

```text
Project: Personal AI          // optional
Agent: Coding Agent           // optional
Continue: MUL-381             // optional

请先补取消/skip 的测试，再修改实现。
```

Bridge receipt 区：

```text
--- Multica Bridge ---
Status: Dispatched
Issue: MUL-381
...
```

### 7.3 URL

Request 提交后，Bridge 写 Multica Issue URL。

Attention Reminder 一开始就写对应 Issue URL。

### 7.4 Due / Alarm

第一版建议：

- Request Reminder 的 Apple due/alarm 是**人的 capture/dispatch reminder**，不自动解释成 Agent deadline；
- 如果需要 Multica Issue due date，使用 Notes `Due:` override 或未来 Bridge UI/Shortcut；
- Bridge 自己检测到 Request 时立即 dispatch。

以后如要支持“明天 9 点才让 Agent 开始”，增加显式：

```text
Dispatch-At: 2026-09-12 09:00
```

不要隐式重解释 Apple due date，避免用户以为是人的提醒时间，Bridge 却把它当 Agent schedule。

## 8. Dispatch 状态机

```text
Apple Request created
      |
      v
DISCOVERED
      |
      +-- invalid route ------> NEEDS_CONFIGURATION
      |
      +-- future dispatch ----> DEFERRED
      |
      v
DISPATCHING
      |
      +-- create issue/comment failed -> RETRYABLE_ERROR
      |
      v
DISPATCHED
      |
      v
complete original Request Reminder
      |
      v
Multica owns lifecycle
      |
      +-- in_review ----------> Agent Attention Reminder
      +-- human-blocked ------> Agent Attention Reminder
      +-- failure/no retry ---> Agent Attention Reminder
      `-- done ---------------> no new human action
```

Bridge DB 新增：

```text
request_projection
  request_reminder_id
  request_external_id
  request_payload_hash
  route_id
  multica_issue_id
  multica_issue_key
  dispatch_kind = new_issue | continue_issue
  state
  dispatched_at
```

保证 Bridge 重启、iCloud identifier 变化或 CLI timeout 后不会重复创建 Multica Issue。

## 9. Request 修改与幂等

### 派发前修改

只要仍是 `DISCOVERED/DEFERRED`，读取最新 title/notes。

### 派发中修改

以 dispatch transaction 捕获的 payload hash 为准；成功后 receipt 写明提交版本。

### 派发后修改 completed Request

默认**不自动修改 Multica Issue**。

原因：用户编辑一个已完成 Reminder 可能只是整理个人记录，不能隐式产生 Agent side effect。

要继续工作，创建新 Request 并指定 `Continue:` 或 Multica URL。

## 10. 删除/完成语义

### 用户在派发前完成 Request

解释为：

```text
cancel local dispatch intent
```

Bridge 不创建 Multica Issue。

### 用户在派发后取消完成状态

不自动重新派发。

### 用户删除已派发 Request

只删除本地 capture receipt，不删除 Multica Issue。

### 用户完成 Attention Reminder

仍然只代表“我处理了提醒”，不等于 Multica `done`。

## 11. 推荐设置 UI

新增 `Request Routing`：

```text
Apple -> Multica Dispatch
[x] Enable request intake

Generic request list
Agent Requests

Routes
----------------------------------------------------------------
Apple List              Project           Agent
Agent · Personal AI     Personal AI       Coding Agent
Agent · Website         Website           Frontend Agent
Agent · Infra           Infrastructure    DevOps Agent

[+ Add Route]

Default behavior
Create: Multica Issue
Start immediately: Yes
Complete Request after accepted: Yes

Continuation
[x] Recognize `Continue: MUL-xxx`
[x] Recognize Multica Issue URL
```

Bridge 应从 Multica 查询 Projects/Agents，让用户在 Settings picker 中选择，不手输 ID。

## 12. 安全边界

1. 不把 raw local directory path 写进 iCloud Reminders。
2. 不把 Multica PAT 写入 Reminder。
3. 默认只允许 dispatch 到 Settings 中显式 allow-listed Workspace/Project/Agent。
4. Request title/notes 属于不可信用户输入；CLI 使用 stdin / structured args，不能拼 shell command。
5. `Continue:` 只能解析当前 Workspace 中用户可访问的 Issue。
6. 删除 Apple Reminder 不删除 Multica work。
7. 不用 checkbox 映射 approval / merge / issue done。

## 13. 真实使用场景

### 场景 A：在外面用 iPhone 派一个 Coding Task

```text
Apple Reminders
List: Agent · Personal AI
Title: 给 Ask 的外部查证增加 Skip 按钮
Notes: 先写测试，不能让 skip 把已有答案丢掉
```

Mac 上 Bridge：

```text
Agent · Personal AI route
 -> Multica Project: Personal AI
 -> Coding Agent
 -> create MUL-421
 -> complete Request receipt
```

Codex 在家里的 Mac mini daemon 工作。

完成后：

```text
Agent Attention
Review · Personal AI · Ask external verification skip
```

你在手机点链接进入 Multica Review。

### 场景 B：一个项目对应本机代码目录

Multica Desktop 里一次配置：

```text
Project: Personal AI
Resource:
  local_directory
  daemon: MacBook-Pro
  path: /Users/.../Personal-AI
```

Apple 以后只选：

```text
List = Agent · Personal AI
```

Reminder 不需要、也不应该知道绝对路径。

### 场景 C：两台机器有同一个项目

Multica Project 同时有不同 daemon 上对应资源/运行上下文；Agent 自己绑定具体 runtime。

Apple 仍然只是：

```text
Project = Personal AI
Agent = Coding Agent
```

机器选择留在 Multica。

### 场景 D：继续昨天的 Agent Task

昨天：

```text
MUL-381
```

今天 iPhone 新建：

```text
Agent · Personal AI
Title: 再确认 Windows 路径兼容，并补一个测试
Notes:
Continue: MUL-381
```

Bridge：

```text
comment on MUL-381
@Coding Agent ...
```

Multica 在同一 Issue 中产生新 Run，并尽量 resume 历史 provider session。

### 场景 E：Agent 被卡住

Multica：

```text
blocked
reason: 需要用户确认是否允许修改 production config
```

Bridge：

```text
Agent Attention
Unblock · Infra · production config decision
```

不污染原 Request。

### 场景 F：Agent 自己恢复的错误

Run failed 但 Multica 正在 retry：

```text
No Apple Reminder
```

重试最终失败且没有 active retry：

```text
Agent Attention
Check failed Agent task · Personal AI · ...
```

### 场景 G：私人 exploratory Chat

“帮我跟 Agent 随便讨论一下设计”更适合 Multica Chat，而不是 Apple Request 默认路由。

Bridge v0.2 可以先让用户在 Reminder URL 放 Chat deep link作为打开入口，但不自动向任意 private Chat 发消息；等稳定 API contract 后再实现真正 ChatTarget。

## 14. Bridge 能力地图

```text
                         Apple Reminders
                    /                     \
                   /                       \
          Human -> Agent              Agent -> Human
             Requests                   Attention
                |                          ^
                v                          |
          Dispatch Router          Attention Policy
                |                          |
                +---------- Multica -------+
                           |
                Project / Issue / Runs
                           |
                 Codex / Claude / ...
```

### 已实现 v0.1

- Multica Cloud -> Apple `in_review`
- blocked/failure attention
- review generation
- Apple Reminder deep link
- Multica done/cancelled reconciliation
- CLI profile / SQLite / EventKit / Menu Bar

### v0.2 设计新增

- Apple Request List intake
- Routing List -> Multica Project + Agent
- Generic Request + Notes override
- New Issue dispatch
- Continue existing Issue
- original Request receipt + auto-complete
- project/agent settings picker
- request idempotency/retry
- request cancellation-before-dispatch

### 后续 optional

- delayed dispatch
- Multica direct private Chat target
- macOS/iOS Shortcut for richer project/agent picker
- share extension / Siri/App Intent
- Direct API source/sink
