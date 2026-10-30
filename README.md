# WechatConnectAgent

把选中的微信聊天和附件保存为本地文件，供 Codex、Claude Code、Kimi Code 等 Agent 读取和分析。独立运行，无需 WeChatBridge。

## 一条命令安装

先安装 **Node.js 20+（含 npm/npx）**，在 Windows 普通终端或 Mac 终端运行同一条命令：

```sh
npx --yes https://github.com/huangjuhua-aigc/WechatConnectAgent/releases/download/v0.2.0/wechat-connect-agent-0.2.0.tgz
```

安装器自动识别系统和芯片，下载对应接收器并验证固定的 SHA-256，不需要用户选择系统。这是 GitHub Releases 分发的 npm 格式安装器，**尚未发布到 npm registry**。

| 系统 | 接收器 | 首次确认 |
| --- | --- | --- |
| Windows 10 19041+ / 11 x64 | 签名 MSIX | 指定证书信任，必要时本人点击 UAC |
| macOS 13+，Intel / Apple Silicon | Universal App + 分享扩展 | **测试版，无 Developer ID 和公证**；可能需要系统设置允许打开 |

Windows ARM64、Linux 暂不支持。另需 **Python 3.9+**（无 pip 依赖）、已登录的桌面微信和本地 Agent。缺 Python 时，Windows 可经确认使用 winget 安装；Mac 已有 Homebrew 时可经确认安装，否则按提示安装 Python。发布包不需要 Git、SDK 或 Xcode。

- [Mac 系统确认及安装位置](docs/install-macos.md)
- [Windows 证书与不依赖 Node 的安装方式](docs/install-windows.md)
- [平台状态](docs/platforms.md) · [发布文件](https://github.com/huangjuhua-aigc/WechatConnectAgent/releases/tag/v0.2.0)

可追加 `--dry-run` 查看检测结果，`--download-only` 只下载校验，`--help` 查看参数。已有不同同名技能时先提示备份；已同意的自动化环境可用 `--replace-existing-skill --non-interactive`。

## 使用与验证

安装后重新打开 Agent 会话，例如：“使用 wechat-chat-select，把我跟某位联系人的最近 5 条消息保存并总结。”有桌面工具的 Agent 可按描述选择；没有桌面工具时由用户多选并分享给“聊天收件箱”。安装技能不会增加桌面控制能力。

完整批次保存到 `~/.agent-chat-receiver/Inbox/Ready`，包含原件和 SHA-256 清单。成功后显示路径、打开Explorer/Finder 和“我知道了”按钮；提示卡置顶，5 秒自动关闭。Agent 直接读取本地文件。

文件、ZIP、文字等实际格式由微信提供。未知格式保留原件，不声称已经理解；链接不自动访问、附件不执行。接收器没有网络上传、模型调用或自动回复。

Windows 已验证真实微信分享。Mac 已在 Intel 和 Apple Silicon runner 验证编译、NSItemProvider、原生导入、签名和扩展注册。**Mac 微信真实分享、首次系统确认和提示卡视觉效果仍待真人 Mac 验证。**

源码：通用技能 `skills/wechat-chat-select/`；Windows 接收器 `skills/wechat-chat-select/receiver/`；Mac 接收器 `macos/`；统一安装器 `bin/`、`lib/`。

[构建与发布](docs/development.md) · [详细验证记录](skills/wechat-chat-select/references/validation.md)

MIT License。分享和收件箱设计参考 [WeChatBridge](https://github.com/freestylefly/WeChatBridge)，保留其版权说明。聊天落到本机；Agent 后续数据处理遵循所用 Agent 的配置。
