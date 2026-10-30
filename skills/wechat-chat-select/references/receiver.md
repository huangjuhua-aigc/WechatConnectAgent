# 独立 Windows 分享接收器

显示名为“聊天收件箱”，包名 `AgentChat.Receiver`。它注册 Windows `windows.shareTarget`，从 `ShareOperation.Data` 读取当前分享的载荷，先写 Staging，写完清单后原子移动到 Ready。失败批次进入 Failed，Agent 不读取未完成的 Staging。每批至多 1 GiB、1024 个项目。

无需安装或启动 WeChatBridge。源代码借鉴其 MIT 许可的分享和收件箱设计，保留版权说明于 `receiver/THIRD_PARTY_NOTICES.txt`。接收器没有聊天历史查询 API；需要微信生成并分享选中的内容。

## 一次安装

构建机需要 PowerShell 7、Windows SDK 19041+ 和 .NET Framework 4.8。本机安装可直接使用已生成的签名构建，无须再装 SDK。

```powershell
& (Join-Path $skillRoot 'receiver/build.ps1') -OutputDirectory $buildDirectory -Sign
& (Join-Path $skillRoot 'receiver/install.ps1') -BuildDirectory $buildDirectory
```

本机构建使用单独的自签名代码签名证书。构建和安装脚本不会修改信任设置。首次安装若尚未信任，脚本会停止并显示指纹。向用户说明 Windows 需要在本机 TrustedPeople 信任该代码签名叶证书、这会影响本机各用户；获得明确授权后由管理员运行下述独立脚本。证书私钥留在构建目录 `private/`，不随技能或安装包分发。

```powershell
& (Join-Path $skillRoot 'receiver/trust-machine.ps1') -BuildDirectory $buildDirectory -ExpectedThumbprint $authorizedThumbprint -ResultPath $newResultFile
```

该命令需要管理员环境，UAC 由用户本人确认；脚本校验具体指纹与非 CA 的代码签名用途，仅加入 `LocalMachine\TrustedPeople`，不加入根证书、不关闭签名校验、不启用开发者模式。之后以原用户运行安装脚本。2026-10-30 已实测仅 CurrentUser 信任不足，报 `0x800B0109`；最终遵循 [MSIX 证书文档](https://learn.microsoft.com/en-us/windows/msix/package/create-certificate-package-signing)使用本机 TrustedPeople。若会话已有对同一范围和指纹的明确授权，不重复询问。

安装脚本核对包和程序哈希，安装完整 MSIX，并检查程序获得的包身份。当前版本使用 `packagedClassicApp`，程序和配置都放进包内；没有外部位置依赖。系统分享入口和真实载荷仍需通过一次微信分享验证。相关要求见 [Microsoft MSIX 组件文档](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-manual-conversion)。

诊断：

```powershell
Get-AppxPackage -Name AgentChat.Receiver
python -X utf8 (Join-Path $skillRoot 'scripts/chat_inbox.py') doctor
```

`doctor` 只报告目录，不证明已注册或原生分享可用。菜单入口缺失时不要把文字复制当作附件导出成功；报告入口状态。微信可能缓存分享应用列表，刷新或重启由具体界面和用户当前工作状态决定。

## 每次导出

准备一个本次任务专用目录。以下变量均由 Agent 根据当前技能和任务确定，不照抄其他人的绝对路径：

```powershell
$inboxScript = Join-Path $skillRoot 'scripts/chat_inbox.py'
$baseline = Join-Path $taskOutput 'before.json'
python -X utf8 $inboxScript prepare --output $baseline
```

随后操作微信分享给“聊天收件箱”，再等待：

0.1.7 起，接收器在原始文件与清单已经保存后，在当前屏幕右下角显示置顶圆角提示卡，显示本批文件数和完整目录。出现时不抢输入焦点，从显示开始倒计时 5 秒并自动关闭，底部进度条同步缩短。“打开Explorer”打开该目录，单文件时选中该文件；“我知道了”立即关闭弹窗。点击打开目录不会重置倒计时。弹窗不阻塞 Ready 批次的读取，关闭弹窗不会删除已保存文件。命令行导入和身份检查不会弹窗。这里的文件数不是聊天消息数。

开发时可用已安装程序的 `--show-receipt <manifest.json>` 重放一个明确批次的完成提示；同样 5 秒自动关闭，不重新接收或修改文件。只使用当前任务授权的批次，不扫描其他历史聊天。

```powershell
python -X utf8 $inboxScript wait --baseline $baseline --timeout 30
```

返回 `newBatches` 含明确清单路径。超时是未收到，不是“聊天为空”。`rejectedBatches` 表示无法验证；多个新批次要辨别，不取最大时间戳猜测。基线过期后应重新准备并分享，不能通过新建基线假装旧分享仍是新批次。

```powershell
python -X utf8 $inboxScript export --manifest $manifestPath --output (Join-Path $taskOutput 'export')
```

输出目录必须不存在。`originals/` 保存原件；支持的 ZIP 安全解包至 `unpacked/`；`index.json` 含文件路径、SHA-256、可识别 TXT 记录和差异。先读索引，再按需读取内容。`selectionVerified` 初始为 false，必须对照界面/用户选取才可报告验证通过。直接导入测试会标记 `source=explicit-local-import`，不能冒充系统分享。

## 格式与限制

| 输入 | 保存 | 解释 |
| --- | --- | --- |
| 文件（任意扩展名） | 原始字节、名称、内容类型、SHA-256 | ZIP/TXT 自动识别，其他文件按需用对应工具 |
| Text | UTF-8 TXT | 尝试微信原生/复制文本结构，无法识别则保留原文 |
| WebLink / ApplicationLink | 文本链接 | 不自动访问 |
| HTML | 原始 CF_HTML 文本 | 不运行、不渲染 |
| RTF | RTF 文件 | 不宣称已转纯文本 |
| Bitmap | 原始图像流 | 类型决定扩展名，未自动 OCR |
| 未知自定义格式 | 记录格式名和未处理状态 | 不宣称已保存该格式的全部内容 |

文件夹不支持直接接收，先分享文件或 ZIP。加密、路径穿越、大小超限、不支持压缩法等 ZIP 保留原件并报告解析失败。一个消息可能含多个文件；一份载荷也可能同时有 ZIP 和文本，不能把表示数量当独立消息数。正文没有严格结构转义，消息分段仍需要范围核对。

## 数据契约

收件箱路径：`%USERPROFILE%\.agent-chat-receiver\Inbox\Ready\<UUID>\manifest.json`。放在用户目录是为了避免 MSIX 对 AppData 的重定向造成其他 Agent 看不到文件。

清单 schemaVersion=1，包含 batchId、UTC createdAt、source、formats、items、warnings、unhandledFormats、partial。每个 item 包含相对路径 relativePath、原名 displayName、byteCount、sha256、kind、contentType。以 manifest 中实际给出的路径为准，不遍历其他历史聊天猜测文件。

`Ready` 文件留存本地，多个 Agent 可读取同一批次而不消费/删除它。任务目录为独占创建，不互相覆盖。不默认清理用户历史；删除或自动保留期限需要另外明确约定。
