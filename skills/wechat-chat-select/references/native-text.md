# 原生复制与文本核对

## 实机行为

Windows 微信的消息多选工具栏有“复制”。2026-10-29 在本机实测：5 条纯文本被复制为发言人、分钟时间、正文，消息之间为空行，未经过 WeChatBridge 分享入口。与同批原生 ZIP 的解析结果逐条一致。

不要推断所有微信版本、媒体、长消息和引用回复都具有相同格式。复制前以真实界面确认范围；出现“已复制”后立即读取本次剪贴板。不轮询剪贴板、不读取历史，不在复制失败时保存遗留内容。若用户在其间复制了其他内容，重新核对选择并复制。

## 保存

先完成 `windows-workflow.md` 的选择和核对，再点击实际可见的“复制”。复制成功后可以用普通文件/剪贴板命令保存；Windows 控件操作仍只用 Computer Use。

示例中的 `$taskOutput` 应为本次已确定的绝对输出目录。保留原文，输出独占创建，不覆盖已有文件：

```powershell
$copiedChatText = Get-Clipboard -Raw
if ([string]::IsNullOrWhiteSpace($copiedChatText)) { throw 'No text after native copy' }
New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
$textPath = Join-Path $taskOutput 'messages.txt'
$stream = [System.IO.File]::Open($textPath, [System.IO.FileMode]::CreateNew,
    [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
try {
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($copiedChatText)
    $stream.Write($bytes, 0, $bytes.Length)
} finally { $stream.Dispose() }
```

然后解析：

```powershell
$skillScript = Join-Path $skillRoot 'scripts\wechat_archive.py'
python -X utf8 $skillScript inspect-text --text-path $textPath --expect-count 5 --records --output (Join-Path $taskOutput 'messages.json')
```

数量应替换为本次实际目标。`--records` 只在正文核对/分析需要时使用。此子命令只读指定 TXT；不检查微信流是否安装，也不读取 Inbox。只核对数量还不够，必须核对首尾和发言人；同一时刻/重复正文要保留，不按正文去重。

原生复制格式与 ZIP 的 `聊天记录.txt` 不同：复制文本的发言人行没有前导 `·`，因此显式使用 `--text-format clipboard`（默认）。若分析已提取的 ZIP 原生 TXT，使用 `--text-format native`。时间无时区且只有分钟精度，不补造秒和 UTC 偏移。

聊天文本没有结构转义。正文若包含“空行 + 发言人 + 日期时间”这样的引用，可能与真实消息头冲突；解析是候选分段，仍需界面核对，不能自动去除不匹配的记录。媒体占位符只能保留文字表示，不能声明已导出图片、视频或原文件。

## Agent 消费

Codex、Claude Code、Kimi Code 当前任务都可直接用文件工具读取 TXT 或 `messages.json` 并分析；不需要向输入框粘贴，不创建额外任务，不由脚本调用模型 API。用户明确要求送到另一个 Agent 会话时，再按已授权的目标使用实际提供的任务工具。

## 与 WeChatBridge 源码的关系

参考版本：`freestylefly/WeChatBridge` 提交 `3d181a2cc29a9e0b2534f2c36df4ea8d918c0d32`。

- [ShareTarget/Program.cs](https://github.com/freestylefly/WeChatBridge/blob/3d181a2cc29a9e0b2534f2c36df4ea8d918c0d32/windows/src/WeChatBridge.ShareTarget/Program.cs#L234)：从 Windows 分享激活读取 `ShareOperation`，通过 `GetStorageItemsAsync()` 获得微信提供的文件；没有可直接读取任意聊天的函数。
- [InboxModels.cs](https://github.com/freestylefly/WeChatBridge/blob/3d181a2cc29a9e0b2534f2c36df4ea8d918c0d32/windows/src/WeChatBridge.Windows.Core/InboxModels.cs)：复制文件到 Staging、写 manifest，再移动到 Ready，属于本地文件接收。
- [WeChatTranscriptRecord.cs](https://github.com/freestylefly/WeChatBridge/blob/3d181a2cc29a9e0b2534f2c36df4ea8d918c0d32/windows/src/WeChatBridge.Windows.Core/Archive/WeChatTranscriptRecord.cs)：解析原生 TXT；技能的 Python 解析器独立实现并额外适配复制格式。
- [DeliveryEngine.cs](https://github.com/freestylefly/WeChatBridge/blob/3d181a2cc29a9e0b2534f2c36df4ea8d918c0d32/windows/src/WeChatBridge.Windows.Core/Delivery/DeliveryEngine.cs)：目标应用激活、剪贴板和粘贴，不是 Codex 消息 API。
- [AppxManifest.xml](https://github.com/freestylefly/WeChatBridge/blob/3d181a2cc29a9e0b2534f2c36df4ea8d918c0d32/windows/packaging/SparsePackage/AppxManifest.xml)：`windows.shareTarget` 注册让微信能够列出接收器。若提取独立 ZIP 接收器，仍需自己的包身份和分享入口注册，不能只把接收函数放进 Python 就得到分享载荷。

项目为 MIT 许可。未来若直接复制其实现，随衍生代码保留原版权和许可；本次文本流程使用微信原生复制及技能自己的脚本，没有植入或调用微信流运行时。
