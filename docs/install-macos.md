# macOS 安装

需要 macOS 13+、Node.js 20+（含 npm）、Python 3.9+ 和桌面微信。Intel / Apple Silicon 自动选择，无需 Xcode、Git 或 WeChatBridge。

```sh
npx --yes https://github.com/huangjuhua-aigc/WechatConnectAgent/releases/download/v0.2.0/wechat-connect-agent-0.2.0.tgz
```

已有不同同名技能时先确认备份，可在已同意时追加 `--replace-existing-skill`。缺 Python 时，已有 Homebrew 可经确认或 `--install-python` 使用 `brew install python`；其他机器安装 [Python for macOS](https://www.python.org/downloads/macos/) 后重试。安装器不自动安装 Homebrew 或 Xcode。

## 测试版首次启动

此版使用 **ad-hoc 签名，无 Apple Developer ID 和公证**。签名校验不代表 Apple 已核验开发者。

1. 安装器尝试打开 `~/Applications/ChatInbox.app`。被阻止时，先从 Finder 尝试打开一次。
2. 在“系统设置 → 隐私与安全性”对应提示中点击“仍要打开 / Open Anyway”，按系统提示本人确认。旧系统也可能提供右键“打开”入口。
3. 若没有允许按钮或有组织管理限制，按系统/管理员要求处理。
4. 分享菜单没有“聊天收件箱”时，在系统设置搜索“扩展”或“共享”并启用。新系统通常在“通用 → 登录项与扩展 → 共享”，旧系统可能在“隐私与安全性 → 扩展”，以实际系统为准。
5. 重新打开微信分享菜单。仍不可见时请反馈 macOS / 微信版本和菜单状态。

安装器不关闭 Gatekeeper、不移除隔离属性、不修改系统安全策略。系统确认不能静默代替用户完成。[Apple 官方说明](https://support.apple.com/102445)。

## 位置与更新

- App：`~/Applications/ChatInbox.app`，内嵌 `Contents/PlugIns/ChatInboxShare.appex`
- 技能源：`~/.wechat-connect-agent/versions/0.2.0/skills/wechat-chat-select`
- 入口：`~/.agents/skills/wechat-chat-select`、`~/.claude/skills/wechat-chat-select`（符号链接）
- 收件箱：`~/.agent-chat-receiver/Inbox`
- 缓存和备份：`~/.wechat-connect-agent/downloads`、`~/.wechat-connect-agent/backups`

分享扩展启用 App Sandbox，仅声明收件箱目录的 home-relative 文件读写例外，使 Agent 可读普通路径。测试版不依赖开发团队 App Group。

新版用新版命令更新，相同版本验证文件并拒绝覆盖本地修改。旧 App 和技能先备份，不删除聊天。`--no-open` 避免启动窗口；`--non-interactive` 在缺少确认时报错。

## 真人 Mac 验证与卸载

重新打开 Agent 会话，先让它建立收件基线。微信选择一小批聊天，通过实际系统分享入口选择“聊天收件箱”，核对新 Ready 原件、清单、内容，以及 Finder 定位和 5 秒关闭。普通好友转发不是系统分享。

两类 GitHub Mac runner 测试编译、NSItemProvider、原生导入、安装和注册，不验证真实微信、Gatekeeper 界面或 GUI 视觉。

卸载时退出 App，从 Finder 将 `~/Applications/ChatInbox.app` 移到废纸篓，移除两处技能符号链接本身，再按需清理缓存或恢复备份。收件箱由用户决定是否保留。
