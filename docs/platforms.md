# 平台支持

统一入口自动识别系统和架构，不让用户选择。Windows ARM64、Linux 暂不支持。

| 项目 | Windows | macOS |
| --- | --- | --- |
| 系统 | Windows 10 19041+ / 11 x64，.NET 4.8 | macOS 13+，Intel / Apple Silicon |
| API | windows.shareTarget / ShareOperation.Data | com.apple.share-services / NSItemProvider |
| 包 | MSIX | Universal App + Share Extension |
| 签名 | 自签名证书，需 TrustedPeople 信任 | ad-hoc 测试签名，无 Developer ID、公证 |
| 原生自动测试 | 通过 | 两类 Mac runner 通过 |
| 微信真实分享 | 本机纯文本已验证 | 待真人 Mac 验证 |
| 提示卡 | 置顶、5 秒、Explorer | 置顶、5 秒、Finder；视觉待验证 |

统一命令需要 Node.js 20+ / npm；解析需要 Python 3.9+。Windows 另有 PowerShell 入口。发布包不需要编译工具。

Codex / Kimi Code 共用 `~/.agents/skills/wechat-chat-select`，Claude Code 使用 `~/.claude/skills/wechat-chat-select`。同一用户共用 `~/.agent-chat-receiver/Inbox`。WSL、容器和远程主机需要文件映射。

接收器不读取微信数据库，没有查询历史的隐藏接口。AI 选择依靠实际桌面工具；缺少桌面工具时由用户选择分享。跨 Agent 会话发送仍需用户指定目标。
