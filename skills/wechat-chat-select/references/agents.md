# Agent 接入

接收器、Inbox 和 Python 脚本与 Agent 品牌无关。`SKILL.md` 定义操作流程，Python 3.9+ 标准库负责本地读取；系统分享接收器目前仅支持 Windows 10 19041+ / Windows 11 x64（.NET Framework 4.8）。其他系统可以读取已经导出的文件，不能运行此接收器。

| Agent | 用户技能目录 | 调用示例 |
| --- | --- | --- |
| Codex | `~/.agents/skills/wechat-chat-select` | `$wechat-chat-select` 或自然语言 |
| Claude Code | `~/.claude/skills/wechat-chat-select` | `/wechat-chat-select` 或自然语言 |
| Kimi Code | `~/.agents/skills/wechat-chat-select`；也支持 `$KIMI_CODE_HOME/skills` | `/skill:wechat-chat-select` 或自然语言 |

以上为官方当前文档：

- [Codex skills](https://developers.openai.com/codex/skills)
- [Claude Code skills](https://code.claude.com/docs/en/skills)
- [Kimi Code skills](https://moonshotai.github.io/kimi-code/en/customization/skills)

安装：优先使用 [WechatConnectAgent 的发布版与安装说明](https://github.com/huangjuhua-aigc/WechatConnectAgent)。手动接入开发目录时，将整个技能目录放在稳定位置，执行 `scripts/install-skill.ps1`。该手动脚本在 `.agents/skills` 和 `.claude/skills` 建目录联接，已经存在不同技能时拒绝覆盖；发布版安装器则可经确认后先备份再替换。旧版 `.codex/skills/wechat-chat-select` 可通过 `-MigrateLegacyCodex` 先备份再迁移，避免重复发现。不要移动作为联接目标的源目录。安装后重新打开会话或刷新技能。

接收器要单独注册一次，见 [receiver.md](receiver.md)。在同一 Windows 用户下各 Agent 读取相同的 `%USERPROFILE%\.agent-chat-receiver\Inbox`。在 WSL、容器、远程主机中，先显式提供映射后的 `--inbox` 路径；本地 Windows 接收器不会自动跨机器传文件。

## 能力边界

- 有文件工具和 Python：能接收后的导出、解析和分析。
- 另有可用桌面控制工具：能根据描述定位、选择和分享微信消息。各 Agent 的桌面能力不同，安装技能不会凭空提供操作系统控制工具。
- 无桌面工具：请用户手动多选并分享给“聊天收件箱”，Agent 建基线并等待新批次，再读取文件。
- 图片、PDF、音视频等附件：先保存原件，再调用该 Agent 已有的对应解析工具。没有解析工具就报告未分析；新增外部上传/转录需沿用用户授权与工具规则。

技能目录发现、命令行可运行和真实端到端操作是三项不同验证。没有实际启动某个 Agent 并验证前，不声称已验证它的自动桌面操作。
