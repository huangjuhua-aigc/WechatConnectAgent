import AppKit
import ChatInboxCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var home: NSWindow?
    private var receipts: [ReceiptPanel] = []
    private var receivedURL = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let inbox = try? Capture.defaultInbox() {
            try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        if let path = option("--show-receipt") {
            showReceipt(URL(fileURLWithPath: path)); return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !self.receivedURL else { return }
            self.showHome()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        receivedURL = true
        for url in urls where url.scheme == "wechatconnectagent" && url.host == "receipt" {
            let batch = url.lastPathComponent.lowercased()
            guard UUID(uuidString: batch) != nil, let root = try? Capture.defaultInbox() else { continue }
            showReceipt(root.appendingPathComponent("Ready/\(batch)/manifest.json"))
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showHome() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func showReceipt(_ manifest: URL) {
        do {
            let data = try Data(contentsOf: manifest)
            guard data.count <= 1_048_576 else { throw CaptureError.limitExceeded }
            let receipt = try JSONDecoder().decode(Manifest.self, from: data)
            guard receipt.schemaVersion == 1, receipt.batchId == manifest.deletingLastPathComponent().lastPathComponent,
                  manifest.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Ready" else { throw CaptureError.invalidSource }
            let panel = ReceiptPanel(directory: manifest.deletingLastPathComponent().appendingPathComponent("files"), count: receipt.items.count)
            receipts.append(panel)
            panel.present()
        } catch { showHome(error: error.localizedDescription) }
    }

    private func showHome(error: String? = nil) {
        if let home { home.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 250), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "聊天收件箱"
        window.isReleasedWhenClosed = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        let title = NSTextField(labelWithString: error == nil ? "接收你选中的微信聊天" : "无法显示完成提示")
        title.font = .boldSystemFont(ofSize: 20)
        let detail = NSTextField(wrappingLabelWithString: error ?? "在微信中多选消息，合并转发或分享给“聊天收件箱”。如果没有此入口，请在系统设置的扩展/共享设置中启用它。\n\n本应用不会读取微信数据库，也不会自动发送消息。")
        let path = NSTextField(wrappingLabelWithString: (try? Capture.defaultInbox().path) ?? "")
        path.textColor = .secondaryLabelColor
        path.isSelectable = true
        let open = NSButton(title: "打开收件箱", target: self, action: #selector(openInbox))
        [title, detail, path, open].forEach { stack.addArrangedSubview($0) }
        window.contentView = stack
        window.center()
        home = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
    }

    @objc private func openInbox() {
        guard let inbox = try? Capture.defaultInbox() else { return }
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        NSWorkspace.shared.open(inbox)
    }
}
