# Windows 与 macOS

需要区分安装。共用的是 Agent 的 `SKILL.md` 约定、选取范围核对规则、本地 Inbox 数据契约和 Python 文件解析。负责从微信收取系统分享的原生程序取决于操作系统。

| 部分 | Windows 当前版本 | macOS |
| --- | --- | --- |
| 接收方式 | `windows.shareTarget` / `ShareOperation.Data` | 需开发并验证原生系统分享接收扩展 |
| 原生包 | x64 MSIX + .NET Framework 4.8 | 需单独构建适用 Intel / Apple Silicon 的应用及扩展 |
| 安装、签名 | Windows 代码签名和 AppX 注册 | 需要 macOS 自身的签名、分发和扩展安装流程 |
| 自动操作微信 | 使用 Agent 的 Windows 桌面工具 | 需适配 Mac 微信界面及 Agent 的 macOS 桌面工具 |
| 现成导出文件解析 | Python 标准库 | Python 脚本可以复用；不等于原生收件已支持 |

Apple 提供 [Share extension](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html) 机制，但这不保证某个微信版本一定提供兼容的入口或载荷。需要在真实 Mac 上验证多选、分享入口、各类附件、扩展生命周期、存储目录及签名安装。

本仓库当前没有 macOS 接收器、`.dmg`、`.pkg`、Homebrew 包或 Mac 一键安装命令。Windows 安装器在非 Windows 平台会直接拒绝。不能把 Windows 安装成功的结果当作 Mac 已支持。

未来可以保留一个统一安装入口，根据平台分别选择经过验证的 Windows / macOS 发布资产；平台原生实现仍需分开。
