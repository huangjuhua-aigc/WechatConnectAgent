# WechatConnectAgent

把你选中的微信聊天和附件保存为本地文件，供 Codex、Claude Code、Kimi Code 等 Agent 读取和分析。

**当前支持 Windows x64。macOS 接收器尚未实现，请勿在 Mac 上运行 Windows 安装命令。**

流程：微信中选择聊天 → 分享给“聊天收件箱” → 文件保存到本机 → Agent 读取。接收器不查询微信数据库，不自动发消息，也不需要安装 WeChatBridge。它不会自行调用模型或上传文件；Agent 分析数据时遵循该 Agent 的服务和配置。

## Windows 一键安装

打开普通的 **Windows PowerShell** 窗口，粘贴这一行：

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/huangjuhua-aigc/WechatConnectAgent/v0.1.9/install.ps1')))
```

安装器会下载并校验固定版本的 Release 安装包，检查依赖，安装接收器，并为三个 Agent 设置技能入口。无需 Git、Node.js、npm、Visual Studio 或 Windows SDK。

- Python 已有 3.9+ 就直接复用；没有时会询问是否通过 winget 安装 Python 3.14。
- 当前接收器使用自签名证书。首次安装会展示发布者和完整指纹，询问是否信任，然后弹出 Windows 管理员确认。只添加到本机 `TrustedPeople`，不添加根证书，不开启开发者模式，不修改执行策略。
- 如果有旧的同名技能，会询问是否备份并替换；不会直接覆盖。
- Windows UAC 需要你本人点击。“一键安装”不代表静默批准系统信任。

如果网络无法打开 GitHub，可从 [Releases](https://github.com/huangjuhua-aigc/WechatConnectAgent/releases) 手动下载 `WechatConnectAgent-windows-x64-0.1.9.zip`，解压到普通目录后，在该目录打开 PowerShell：

```powershell
& ([scriptblock]::Create((Get-Content -Raw -Encoding UTF8 .\setup.ps1))) -BundleRoot (Get-Location).Path
```

更详细的依赖、校验、更新、卸载和安装参数见 [Windows 安装说明](docs/install-windows.md)。本项目没有发布 npm 包；上述命令是当前正式安装入口。

## 使用

1. 安装并登录 Windows 微信，以及你选用的一个 Agent。
2. 安装完成后重新打开 Agent 会话，让它发现 `wechat-chat-select` 技能。
3. 对 Agent 说：“把我与某位联系人的最近 5 条消息保存到本地，并总结待办事项。”
4. Agent 有可用桌面工具时，可按描述选择和分享消息；没有桌面工具时，你手动在微信多选 → 合并转发 → 其他应用 → 聊天收件箱，Agent 再读取收到的文件。
5. 保存完成会显示右下角置顶提示卡，展示文件位置，5 秒后自动关闭。点“打开Explorer”可定位文件，点“我知道了”可立即关闭。

默认收件箱：`%USERPROFILE%\.agent-chat-receiver\Inbox`。原始 ZIP、附件和清单留在本地。接收器的文件数不等于聊天消息数，Agent 需要核对选取范围。

## 支持范围

| 项目 | 当前状态 |
| --- | --- |
| Windows 10 build 19041+ / Windows 11 x64 | 提供签名 MSIX，Windows 11 本机验证通过 |
| macOS Intel / Apple Silicon | 尚无原生接收器或安装包；可用 Python 处理已有导出文件 |
| Windows ARM64、Linux | 尚未支持原生接收 |
| Codex | 技能接入和本机微信选择、接收、文本解析已实测 |
| Claude Code / Kimi Code | 技能目录和本地脚本已接入；各自的完整桌面操作尚未实测 |
| 纯文本聊天 | 微信真实分享已验证 |
| 文件、链接、HTML、RTF、位图等 | 有保存处理逻辑；并非每种微信实际载荷都已实测 |

自动选择需要 Agent 自身可用的桌面控制工具，技能本身不提供桌面控制引擎。不应把某一个 Agent 的工具名称当作其他 Agent 也有的能力。文件分析也需要相应解析工具。

## 仓库内容

```text
install.ps1                         固定版本、固定哈希的下载入口
scripts/install-windows.ps1          本地安装器（Release 中名为 setup.ps1）
scripts/package-release.py           生成发布包和校验信息
skills/wechat-chat-select/
  SKILL.md                          Agent 技能
  scripts/                          Python 解析、导出和测试
  receiver/src/                     Windows 接收器 C# 源码
  receiver/                         MSIX 清单、构建、安装和证书脚本
  references/                       使用流程与验证记录
docs/                               安装、平台差异和维护说明
```

从源码构建和运行测试见 [开发说明](docs/development.md)。安装包在 Releases，不需要下载整个开发环境。仓库和安装包不包含聊天记录、账号凭据或签名私钥。

## 许可与来源

MIT 许可。Windows 分享注册与 Staging/Ready 收件箱设计参考了 [WeChatBridge](https://github.com/freestylefly/WeChatBridge)，保留了其 [版权及 MIT 许可](skills/wechat-chat-select/receiver/THIRD_PARTY_NOTICES.txt)。本项目是独立接收器，不由微信官方提供，也不依赖 WeChatBridge 应用。

## English

WechatConnectAgent saves explicitly selected WeChat messages and attachments through a standalone Windows share target, then lets an Agent read local files. The Windows x64 receiver and shared `SKILL.md` support Codex, Claude Code and Kimi Code workflows. Desktop automation requires the Agent's own desktop tools; manual sharing also works. The receiver never queries the WeChat database, sends chat messages, or calls an AI service. A native macOS receiver is **not available**. See [platform differences](docs/platforms.md) and [development](docs/development.md).
