# Apple Reminders → Multica Dispatch & Projection Design

> v0.3 implemented design (v0.2 dispatch model + v0.3 Human Action semantics)
> 默认：`apple_origin_only`

## 1. 核心决策：Main + Human Action sibling

不要用一个 Reminder 在不同 Lists 之间移动，也不要把 Review 当成 Main 的 checkbox 状态。

```text
Agent · Personal AI
○ 给 Ask 增加 Skip                       Main Reminder
○ Review: 给 Ask 增加 Skip       🔔      Human Action sibling
```

原因：

- Project List 始终能看到 Agent work；
- 用户可以直接完成 Review sibling，而不会完成整个 Main；
- Apple Reminders subtask/assignee 并没有足够稳定的 EventKit API；
- 一个 Multica Issue 可经历多个 Run/Review cycle，Bridge 自己保存逻辑关系更可靠。

## 2. Request intake

Bridge 扫描：

- `Agent Requests`；
- Settings 中配置的 Project Route Lists。

只有满足以下条件的 Reminder 才视为新 Request：

- 未完成；
- 在 request allowlist；
- Notes 不含 `Bridge ref:` marker。

### Project Route

```text
Apple List: Agent · Personal AI
Multica Project: Personal AI
Default Agent: Coding Agent
Mirror: apple_origin_only
```

代码目录不写入 Apple；Multica Project resource 负责 repo/local directory/daemon。

## 3. Dispatch lifecycle

```text
Apple Reminder
    ↓ route
create Multica Issue
    ↓
assign Agent
    ↓
original EventKit Reminder
    ↓
becomes Main projection in-place
```

Main 保持原 List，不由 Bridge 设置 human-attention alarm。

Issue description 包含：

```text
Apple Bridge request: <stable request id>
```

用于 crash recovery/idempotency。

## 4. Continuation

首选 UX：把已有 Multica Issue URL 放到新 Apple Reminder 的 URL 字段。

Bridge 检测到 Issue URL 后：

1. fetch existing Issue；
2. 如无 assignee 且 route 有 default Agent，则用 `issue assign --no-start` 绑定 Agent；
3. 把 Reminder title/notes 作为 follow-up comment；comment 作为唯一一次后续执行触发，避免 assign + comment 产生两个 Run；
4. 不创建新 Issue；
5. 如果该 Issue 已有 Main projection，则完成这条一次性 follow-up Request，而不会制造第二个 Main。

`Continue: MUL-381` 不是主 UX；需要时可未来作为 power-user fallback。

## 5. Human Action sibling

```text
in_review -> Review: <title>
blocked   -> Action Required: <title>
failed    -> Check failed Agent task: <title>
```

Human Action：

- 与 Main 在同一 Project List；
- URL 指向 Multica Issue；
- Notes 给 compact summary；
- 默认设置近期 EventKit absolute alarm；
- 每个 review/action generation 有独立 projection identity。

## 6. Direct Multica operation

用户可完全忽略 Apple，直接在 Multica 操作。

### Request Changes / rework

如果 active Run 出现：

```text
old Review sibling -> completed/resolved
Main -> remains open
```

status 暂时仍 `in_review` 也不产生新的 Human Action，因为 active Run 表示 Agent 当前拥有 turn。

### New delivery

active Run -> completed，Issue 仍/重新 `in_review`：

```text
reviewGeneration += 1
create Review sibling #N
```

### Done/Cancelled

```text
resolve Main
resolve all active Human Actions
```

## 7. Apple checkbox semantics

### Main completed/deleted

解释为：

> 不再在 Apple 项目 List 维持这个 Main 投影。

不会：

- 把 Multica Issue 设为 done；
- cancel Agent；
- delete Cloud work。

后续 Human Action 仍可重新出现。

### Human Action completed/deleted

解释为：

> 本轮人类提醒已 acknowledgement/dismissed。

不会修改 Multica。

同一 cycle 不重建；新的 review cycle 才产生新 sibling。

## 8. Mirror Modes

### apple_origin_only（默认）

- Apple-origin：Main + 必要 Human Actions；
- Multica-origin：无 Main；必要时 Human Action。

### all_active

- 该 route 的 Multica-origin active Issues 也维持 Main；
- 必要时 Human Action sibling。

### attention_only

- 不维持 Main；
- 只在人真正需要操作时创建 sibling。

## 9. 为什么不用 Assigned to Me / Subtask

它们是理想 UX 的候选，但当前 EventKit 没有稳定公开接口让 Bridge：

- 设置/读取 Reminders assignee；
- 创建/读取 parent/subtask 关系。

项目不依赖 UI Automation、Apple 私有数据库或其他脆弱 workaround。

未来 Apple API 若开放，可把 Human Action sibling 的 presentation 升级为 assigned/subtask，而不需要改变 Multica/Bridge domain model。

## 10. Artifact Review

v0.3 仍不把 PDF/PPT/大 Markdown 复制到 Reminders。

Human Action Notes 只放 compact summary，URL 始终优先指向 durable Multica Issue。完整 artifact/transcript/review 在 Multica 中完成。

未来若 Multica 提供稳定长期 artifact deep link，可添加 secondary/primary artifact shortcut；不把短时 signed URL 当 Reminder 的长期主链接。
