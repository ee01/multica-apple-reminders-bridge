# Installation and First Run

## 1. 推荐组合

```text
Multica Desktop          UI + 本机 daemon
Official Multica CLI     Bridge Cloud client（不会启动第二个 daemon）
Bridge                   Menu Bar + SQLite + EventKit
```

## 2. CLI

确认：

```bash
multica version
```

不要为了 Bridge 执行 `multica setup`。Settings 的 Connect Multica 等价于：

```bash
multica login --profile reminders-bridge
```

## 3. Build / Install

### 下载发布包（推荐）

在 [GitHub Releases](https://github.com/ee01/multica-apple-reminders-bridge/releases) 下载最新的 `Multica-Reminders-Bridge-v*-macos.zip`，解压后将 `Multica Reminders Bridge.app` 拖入 `Applications` 或 `~/Applications`。

### 本地构建

macOS 14+：

```bash
make install
```

只构建：

```bash
make mac-app
```

默认安装：

```text
~/Applications/Multica Reminders Bridge.app
```

### 发布新版本（维护者）

在 macOS 上提交并推送所有变更后：

```bash
npm run deploy
```

该命令会运行测试、构建 `.app`、打包 zip，并创建/更新对应版本的 GitHub Release。

## 4. 首次设置

### Multica

1. Connect Multica；
2. 浏览器登录；
3. 选择 Workspace；
4. Refresh Projects / Agents；
5. 配置 fallback Agent（generic `Agent Requests` 必须有可用 Agent 才能 dispatch）；
6. 可选配置 fallback Project。

### Project Routes

常用项目可 Pin：

```text
Apple list: Agent · Personal AI
Multica project: Personal AI
Default agent: Coding Agent
Mirror: apple_origin_only
```

默认不要求一 Project 一 List；只配置高频项目即可。

### Reminders

1. Grant / Check Reminders Permission；
2. 首次 sync 会自动确保 `Agent Requests` 与所有 configured Project Route Lists 存在，无需手工创建；
3. Create Test Reminder；
4. 在 Mac 与 iPhone 确认 iCloud 同步；
5. 保留 Human Action alarm 开启（默认 60 秒）。

### Background

建议 Run at Login。默认 180 秒同步，wake/network recovery 会额外 sync。

## 5. 使用

### Apple 发起

在 `Agent Requests` 或项目 List 新建普通 Reminder。Bridge 会把原条目升级为 Main，不移动 List。

### Review

Agent 最终交付后，同 Project List 出现：

```text
Review: <task> 🔔
```

两种处理方式：

- 在 Multica 深度 Review；Request Changes 会产生新的 Run，Bridge 自动收尾当前 Review sibling；
- 如果结果可接受且本次 Review 就是任务最终验收，直接在 Apple Reminders 勾选该 Review。默认配置下 Bridge 会在严格门禁通过后执行 Multica `done`，再反向完成 Main。

`Action Required` / `Failed` 的 checkbox 不具备上述 approval 语义。

### 继续已有 Issue

建立新 Reminder，并把 URL 设置为对应 Multica Issue URL。Bridge 会把 Reminder 内容作为 follow-up comment，而不是创建第二个 Issue。

## 6. 本地数据

```text
~/Library/Application Support/MulticaRemindersBridge/
  config.json
  bridge.sqlite
  bridge.log
```

CLI token 不属于 Bridge 数据目录。
