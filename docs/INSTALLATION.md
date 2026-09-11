# Installation and First Run

## 1. 推荐组合

```text
Multica Desktop              保持原样，用于 UI + 本机 daemon
Official Multica CLI         Bridge 的 Cloud 查询客户端
Multica Reminders Bridge     Menu Bar + EventKit
```

Bridge 不替换 Desktop，也不会启动第二个 daemon。

## 2. 安装 Multica CLI

按 Multica 官方文档安装 CLI。安装后确认：

```bash
multica version
```

**不要为了 Bridge 执行 `multica setup`。** `setup` 会连同 daemon 一起初始化；Bridge 只需要登录：

```bash
multica login --profile reminders-bridge
```

正常情况下不必手工运行上面的命令：App Settings 的 **Connect Multica** 会执行它。

## 3. 构建并安装 Bridge

需要 macOS 14+ 和 Swift/Xcode Command Line Tools：

```bash
make install
```

如果只构建 `.app`：

```bash
make mac-app
```

输出：

```text
dist/Multica Reminders Bridge.app
```

`make install` 默认复制到：

```text
~/Applications/Multica Reminders Bridge.app
```

可指定：

```bash
INSTALL_DIR=/Applications make install
```

发布/长期稳定使用时建议用自己的 Developer ID 签名：

```bash
SIGN_IDENTITY='Developer ID Application: Your Name (...)' make mac-app
```

未提供时脚本使用 ad-hoc signing，适合本机开发验证。

## 4. 首次设置

打开 Menu Bar App -> Settings：

### Multica Cloud

- CLI path：通常 Apple Silicon 为 `/opt/homebrew/bin/multica`，Intel Homebrew 通常 `/usr/local/bin/multica`。
- CLI profile：默认 `reminders-bridge`。
- 点击 **Connect Multica**。
- 浏览器完成登录。
- 选择目标 Workspace。
- **Test** 应显示 Connected。

登录数据由 Multica CLI 自己保存在其独立 profile；Bridge 不解析 token 文件。

### Apple Reminders

- List name：默认 `Multica Reviews`。
- 点击 **Grant / Check Permission**。
- macOS 系统权限框允许 Reminders full access。
- 点击 **Create Test Reminder**。
- 确认 Mac Reminders 与 iPhone 的 iCloud Reminders 都出现测试项。

### 通知

默认开启“新的人类 Review Reminder 增加 alarm”，延迟 60 秒。它用于让 iPhone/iPad 收到真正的 Reminders 通知，而不仅仅是在 List 里出现一条无日期任务。

Multica Issue 的 due date 仍独立映射为 Reminder due date。

### 后台运行

建议开启 **Run at Login**。默认每 180 秒同步一次；Mac 从睡眠恢复或网络恢复时会主动触发一次 reconcile。

## 5. 推荐 Multica 工作流

无需给每个 Issue 加 Apple Reminder prompt。正常使用 Multica status：

```text
todo -> in_progress -> in_review -> done
```

Bridge 看到 `in_review` 自动创建 Reminder。

如果某个 Issue 不想提醒，加：

```text
no-reminder
```

如果某个 Issue 要提高提醒优先级：

```text
reminder-urgent
```

## 6. 配置与本地数据

目录：

```text
~/Library/Application Support/MulticaRemindersBridge/
```

包含：

```text
config.json      Bridge 设置，不保存 Multica PAT
bridge.sqlite    Issue observation / Reminder projection
bridge.log       脱敏诊断日志
```

CLI token 属于 Multica 自己的 `reminders-bridge` profile，不属于 Bridge 配置。

## 7. 卸载

退出 App，删除应用；若也要删除 Bridge 的本地 projection：

```bash
rm -rf "$HOME/Library/Application Support/MulticaRemindersBridge"
```

如需注销 Bridge 专用 Multica CLI profile，请按 Multica CLI 的 profile/logout 机制处理。不要删除 Desktop 的 `desktop-*` profile。
