import AppKit

final class ReceiptPanel: NSPanel {
    private let directory: URL
    private let countdown = NSTextField(labelWithString: "5 秒后关闭")
    private let progress = NSProgressIndicator()
    private var timer: Timer?
    private var shownAt: TimeInterval = 0

    init(directory: URL, count: Int) {
        self.directory = directory
        super.init(contentRect: NSRect(x: 0, y: 0, width: 460, height: 260), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        let card = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 260))
        card.wantsLayer = true
        card.layer?.cornerRadius = 18
        card.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let title = NSTextField(labelWithString: "✓  文件已保存")
        title.font = .boldSystemFont(ofSize: 22)
        title.textColor = .systemGreen
        title.frame = NSRect(x: 24, y: 203, width: 280, height: 32)
        countdown.textColor = .secondaryLabelColor
        countdown.alignment = .right
        countdown.frame = NSRect(x: 320, y: 208, width: 115, height: 20)
        let descriptor = NSTextField(labelWithString: "\(count) 个文件 · 保存位置")
        descriptor.textColor = .secondaryLabelColor
        descriptor.frame = NSRect(x: 24, y: 166, width: 410, height: 20)
        let path = NSTextField(wrappingLabelWithString: directory.path)
        path.isSelectable = true
        path.font = .systemFont(ofSize: 12)
        path.frame = NSRect(x: 24, y: 92, width: 410, height: 66)
        let open = NSButton(title: "打开Finder", target: self, action: #selector(openFolder))
        open.bezelStyle = .rounded
        open.bezelColor = .systemBlue
        open.frame = NSRect(x: 24, y: 33, width: 255, height: 38)
        let dismiss = NSButton(title: "我知道了", target: self, action: #selector(dismissReceipt))
        dismiss.bezelStyle = .rounded
        dismiss.frame = NSRect(x: 290, y: 33, width: 145, height: 38)
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 5
        progress.doubleValue = 5
        progress.frame = NSRect(x: 24, y: 15, width: 412, height: 4)
        [title, countdown, descriptor, path, open, dismiss, progress].forEach { card.addSubview($0) }
        contentView = card
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func present() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let area = screen?.visibleFrame { setFrameOrigin(NSPoint(x: area.maxX - frame.width - 20, y: area.minY + 20)) }
        orderFrontRegardless()
        shownAt = ProcessInfo.processInfo.systemUptime
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let remaining = max(0, 5 - (ProcessInfo.processInfo.systemUptime - self.shownAt))
            self.countdown.stringValue = "\(Int(ceil(remaining))) 秒后关闭"
            self.progress.doubleValue = remaining
            if remaining <= 0 { self.close() }
        }
    }

    @objc private func openFolder() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        if files.count == 1 { NSWorkspace.shared.activateFileViewerSelecting(files) }
        else { NSWorkspace.shared.open(directory) }
    }
    @objc private func dismissReceipt() { close() }
    override func close() { timer?.invalidate(); timer = nil; super.close() }
}
