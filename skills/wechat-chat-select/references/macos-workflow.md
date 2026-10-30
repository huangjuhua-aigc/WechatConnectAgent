# macOS 选择与接收

接收器为 `~/Applications/ChatInbox.app`，内嵌系统分享扩展，显示“聊天收件箱”，支持 macOS 13+ Intel/Apple Silicon。默认 Inbox 为 `~/.agent-chat-receiver/Inbox`。采用与 Windows 相同的 schemaVersion 1 清单和 Python 导出流程。

## 安装和平台边界

按 [统一安装与 Mac 说明](https://github.com/huangjuhua-aigc/WechatConnectAgent/blob/v0.2.0/docs/install-macos.md) 安装，入口自动识别系统。测试版 ad-hoc 签名、未公证；首次系统确认由用户完成，不移除隔离属性或关闭安全机制。入口缺失时检查分享扩展是否启用。只有 Python 不能注册分享扩展。

Mac 原生测试和注册检查已经在两类 Mac CI 完成；真实微信菜单、首次系统确认及提示卡视觉尚未在真人 Mac 验证。不要凭 Windows 菜单猜测操作成功。

## 选择

使用当前 Agent 实际可用的 Mac 桌面工具及其操作规则。有工具时先观察联系人和会话标题，再定位底部、固定末条锚点，从新到旧选择最近 N 条，核对首尾和数量。时间/主题请求按当前界面可用的搜索和多选能力执行，搜索命中不代表全部历史。

没有桌面工具时，由用户完成同样范围的多选和系统分享。若当前微信不提供所需系统分享入口，明确报告阻塞，不改为转发给朋友，也不声称保存附件。界面坐标、菜单名称和快捷键必须来自实际观察。

## 接收和读取

以下路径由任务确定，命令中的变量需要先赋值。使用 Python 3.9+；无第三方依赖。

```sh
python3 "$skillRoot/scripts/chat_inbox.py" prepare --output "$taskOutput/before.json"
```

完成基线后，微信选择内容并通过系统分享菜单选择“聊天收件箱”。不要把好友转发当作系统分享。然后：

```sh
python3 "$skillRoot/scripts/chat_inbox.py" wait --baseline "$taskOutput/before.json" --timeout 30
python3 "$skillRoot/scripts/chat_inbox.py" export --manifest "$manifestPath" --output "$taskOutput/export"
```

只处理基线之后的新 Ready 批次；多候选需辨别，不能任取最新。输出目录必须不存在。核对 index.json、原件、TXT 计数/发言人/时间/首尾；文件数不等于消息数，不能把 parsedMessageCount 当去重后的选择计数。

扩展逐项选择 ZIP/归档优先的一个表示，避免同一项目重复保存多个预览。普通文件、数据、文本和链接也可保存；格式随源应用而异。原件和 SHA-256 写入 Staging，全部成功后才移动 Ready。单批最多 1 GiB、1000 项，失败进入 Failed。无法理解的格式保留原件，按 Agent 实际解析工具处理；不自动访问链接或执行附件。

保存完成后尝试唤起主 App 的 5 秒置顶卡片，包含“打开Finder”“我知道了”。唤起失败不会撤销已经完成的 Ready 批次，Agent 仍可从磁盘读取。命令行导入测试不显示卡片，也不证明真实微信分享成功。
