# Windows 安装与更新

## 需要什么

- Windows 10 build 19041+ / Windows 11，x64；目前只在 Windows 11 本机验证。
- .NET Framework 4.8+。安装器检查系统版本，不会替换系统运行时。
- Windows 微信：需要本人登录，并能在合并转发时选择其他电脑应用。
- Codex、Claude Code 或 Kimi Code 等至少一个本地 Agent。它们各自的账号、安装和费用由相应产品管理。
- Python 3.9+。全部脚本只用标准库，无需 `pip install`。缺失时安装器可经你确认后使用 `winget install --exact --id Python.Python.3.14 --source winget --scope user`。
- 自动选择微信消息需要当前 Agent 的桌面控制工具；手动选择则不需要。

README 中的统一 npx 命令需要 Node.js 20+。以下 Windows 专用 PowerShell 入口无需 Node.js、npm、Git、Windows SDK 或 Visual Studio，Windows PowerShell 5.1 即可运行。

## 安装命令

在普通、非管理员的 Windows PowerShell 中执行：

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/huangjuhua-aigc/WechatConnectAgent/v0.2.0/install.ps1')))
```

命令和安装器固定到 `v0.2.0`，包的 SHA-256 固定在该脚本里。不会在同一次安装中漂移到其他版本。它不修改 PowerShell 执行策略；如果组织策略禁止执行，联系管理员，不要绕过组织策略。

你也可以先下载脚本查看，再运行同一份文件；或从 Releases 下载 ZIP 并核对 `SHA256SUMS.txt` 后使用其中的 `setup.ps1`。

## 证书确认

当前是自签名的非 CA 代码签名证书：

- 发布者：`CN=Agent Chat Receiver`
- SHA-1 证书指纹：`9AB5B045406F74CC726D6F583F85AC0C02958BB1`
- 信任位置：`LocalMachine\TrustedPeople`（本机各用户）
- 不加入 `Root`；不开启开发者模式；不禁用签名校验。

SHA-1 在这里用于证书指纹标识；安装包和可执行文件的完整性使用 SHA-256。首次安装需你同意该具体证书，并本人确认 Windows UAC。普通用户不应整体以管理员身份运行安装器，只有证书信任步骤单独提权；接收器随后安装到当前用户。已有相同证书信任时不重复询问。

详见 [Microsoft 的 MSIX 证书说明](https://learn.microsoft.com/en-us/windows/msix/package/create-certificate-package-signing)。当前用户证书存储在本机测试中不足以完成 AppX 安装。

## 参数

只下载并校验，暂不安装：

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/huangjuhua-aigc/WechatConnectAgent/v0.2.0/install.ps1'))) -DownloadOnly
```

已阅读上述行为，并要预先授权依赖安装、该证书信任以及旧技能备份替换：

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/huangjuhua-aigc/WechatConnectAgent/v0.2.0/install.ps1'))) -InstallPython -TrustCertificate -ReplaceExistingSkill
```

这些选项不能替你点击 UAC。`-NonInteractive` 关闭命令行询问；缺少必要授权就报错，不代表绕过授权。

本地 ZIP 解压后的 `setup.ps1` 还支持：

- `-CheckOnly`：只检查包、平台、依赖、证书状态及现有技能，不安装。
- `-SkillsOnly`：只安装技能及其 Python 依赖，不注册接收器或修改证书信任；不能借此接收微信系统分享。
- `-InstallRoot <path>`、`-AgentHome <path>`：用于维护者的隔离测试或明确指定的本地目录。正常使用不需要。

## 安装位置和更新

程序由 MSIX 安装，包标识 `AgentChat.Receiver`，微信中显示“聊天收件箱”。

- 技能源：`%USERPROFILE%\.wechat-connect-agent\versions\0.2.0\skills\wechat-chat-select`
- Codex / Kimi Code 入口：`%USERPROFILE%\.agents\skills\wechat-chat-select`
- Claude Code 入口：`%USERPROFILE%\.claude\skills\wechat-chat-select`
- 收件箱：`%USERPROFILE%\.agent-chat-receiver\Inbox`
- 下载缓存：`%USERPROFILE%\.wechat-connect-agent\downloads`
- 被替换的技能：`%USERPROFILE%\.wechat-connect-agent-skill-backups\<时间与唯一编号>`

下载和安装目录放在用户主目录，避免打包桌面 Agent 对 AppData 的文件重定向让 Windows AppX 服务或其他 Agent 无法访问。入口是目录联接，共用同一份技能。不要手动移动或删除当前源目录。已有不同的同名技能时，先得到同意才移动到备份位置；原文件或原联接都会保留。重复安装同一版本会核对文件，不覆盖本地修改。更新时使用新版 Release 对应的命令，旧版本目录和聊天文件不会自动删除。

如果你还保留旧版 `.codex/skills/wechat-chat-select`，先确认来源并备份移出技能扫描目录，避免同名重复。WSL、容器和远程 Agent 需要单独提供能访问本机文件的映射路径；此安装器面向原生 Windows Agent。

安装后重新打开 Agent 会话。先让 Agent 创建收件基线，再在微信中分享一次明确范围的聊天，确认它收到本次新批次。证书和包注册成功不等于已完成真实微信分享测试。

## 卸载

普通 PowerShell 下卸载接收器：

```powershell
Get-AppxPackage -Name AgentChat.Receiver | Remove-AppxPackage
```

然后移除 `.agents/skills` 与 `.claude/skills` 下这个技能的**目录联接本身**，再按需清理 `WechatConnectAgent` 的安装目录和下载缓存。不要递归删除联接指向的其他目录。聊天收件箱不会自动清除；是否删除由你决定。需要恢复旧技能时，可从备份位置移回。

若确定本机不再使用任何同一证书签名的接收器版本，可由管理员单独删除 `LocalMachine\TrustedPeople` 中上述**准确指纹**的证书。不要删除其他证书。
