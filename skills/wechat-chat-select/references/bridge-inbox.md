# WeChatBridge 本地接收与核对

只在用户明确指定 WeChatBridge / 微信流时使用。默认 ZIP 和附件接收使用独立“聊天收件箱”，见 `receiver.md`；纯文本复制见 `native-text.md`。

适配 [freestylefly/WeChatBridge](https://github.com/freestylefly/WeChatBridge)，依据提交 `3d181a2cc29a9e0b2534f2c36df4ea8d918c0d32` 的 Windows `InboxModels.cs` 和 macOS `WeChatForward.swift`。它不是 iLink 聊天机器人，没有供本技能调用的“选择消息 API”。

## 接收契约

Windows 默认目录：`%LOCALAPPDATA%\WeChatBridge\Inbox`。

- 不读取正在写入的 `Staging`；只读取 `Ready/<batchId>/manifest.json`。
- manifest 使用 camelCase：`schemaVersion`、`batchId`、`createdAt`、`action`、`items`。
- 每项有 `relativePath`、`displayName`、`byteCount` 等字段；按清单找文件，不猜子目录布局。
- 不伪造、删除或修改微信流的 `intent.json`、`state.json`。

Windows 分享入口通常显示“微信流”，再选复制/归档目标。显示名可能含不可见分隔字符，以实际标签和应用身份判断。选择“复制到剪贴板”让 ZIP 留在 Inbox，避免触发其他 AI 应用自动粘贴。只有界面明确是本地目标时才继续，不把微信联系人转发当作系统分享。

1.1.17 的目标选择器取消或超时后，也可能提交 Ready 批次，记录显示“未执行”（表示未投递到目标）。此时若新批次、文件和所选范围均已核对，可直接保存 ZIP/TXT，无须再次发送或修改 intent/state。不要读取仍在 Staging 的内容。

## 辅助脚本

`scripts/wechat_archive.py` 使用 Python 3 标准库，无 pip 依赖。下面的 `$skillScript` 按技能实际安装位置赋值；设置了 CODEX_HOME 时以其目录为准。这些命令只操作文件，不操作界面。

```powershell
$skillScript = Join-Path $skillRoot 'scripts\wechat_archive.py'
$taskOutput = Join-Path (Get-Location) 'artifacts\wechat-selection-YYYYMMDD-HHMMSS'
python $skillScript doctor
python $skillScript snapshot --output (Join-Path $taskOutput 'before-001.json')
```

`doctor` 只检查平台和 Inbox 是否存在，不能证明已安装或分享入口注册成功。桌面应用列表未发现微信流，也不能绝对证明便携版不存在。用户提供其他收件箱位置时可传 `--inbox`。

分享成功后：

```powershell
python $skillScript changes --baseline (Join-Path $taskOutput 'before-001.json')
```

只列新批次元数据及文件路径，不读取旧正文。没有新批次时先检查分享界面，再有限重查。基线默认 30 分钟有效；超时新建基线并重新确认。多个新批次需按界面记录、时间和清单辨别，不直接取最新一个。脚本只能证明批次是新的，不能证明属于指定聊天。

对已确认的 ZIP 执行：

```powershell
python $skillScript inspect --zip 'C:\absolute\confirmed-export.zip' --expect-count 20
python $skillScript inspect --zip 'C:\absolute\confirmed-export.zip' --records --output (Join-Path $taskOutput 'messages-001.json')
```

- 默认只打印时间、计数和附件清单，不打印正文；`--records` 在需要分析或内容核对时使用。
- 输出独占创建，不覆盖已有文件。重跑使用新文件名。
- `--expect-count` 不匹配返回退出码 2，保留实际结果，不能忽略。
- TXT 格式未知返回 `unrecognized`，不能说成零条消息。
- 完整性校验限于读取的 TXT；附件清单不代表附件已读取或校验。
- 不解压附件、不执行归档内容、不联网。

需要长期保存时，将已核对的原始 ZIP 复制到用户指定输出目录，保留微信流原文件；用脚本报告的 SHA-256 核对副本。Inbox 可能被历史清理功能清除，不能称为永久归档。

## 格式和计数

已知原生 TXT 消息头：

```text
·发言人
2026年10月29日 12:34
消息正文
```

保留原顺序和重复消息。时间无时区/秒，输出 `local_unspecified` 和分钟精度，不自动标为 UTC。多个 TXT 优先 basename“聊天记录.txt”；多个同优先级候选要求显式 `--member`，避免读到作为附件发送的另一份聊天。没有原生 TXT 时可以接收文件，但不声称已解析聊天。

界面选中数、解析数及首尾消息均相符，才记用例通过。分别报告缺失、重复、格式不识别或历史未加载完整。
