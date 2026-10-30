import AppKit
import ChatInboxCore

@objc(ChatInboxShareViewController)
final class ShareViewController: NSViewController {
    private var started = false

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 90))
        let label = NSTextField(labelWithString: "正在保存到聊天收件箱…")
        label.frame = NSRect(x: 24, y: 34, width: 280, height: 24)
        container.addSubview(label)
        view = container
        preferredContentSize = container.frame.size
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard !started, let context = extensionContext else { return }
        started = true
        Task { @MainActor in
            var capture: Capture?
            do {
                let batch = try Capture(inbox: Capture.defaultInbox(), source: "macos.shareExtension")
                capture = batch
                for case let item as NSExtensionItem in context.inputItems {
                    let attachments = item.attachments ?? []
                    if attachments.isEmpty, let content = item.attributedContentText?.string, !content.isEmpty {
                        batch.formats.append("public.utf8-plain-text")
                        try batch.addText(content)
                    }
                    for provider in attachments { try await ProviderImporter.receive(provider, into: batch) }
                }
                _ = try batch.commit()
                Self.showReceipt(batchId: batch.batchId)
                context.completeRequest(returningItems: nil, completionHandler: nil)
            } catch {
                capture?.fail(error)
                context.cancelRequest(withError: error)
            }
        }
    }

    private static func showReceipt(batchId: String) {
        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard app.pathExtension == "app", let url = URL(string: "wechatconnectagent://receipt/" + batchId) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        // Notification is best effort. The durable Ready batch never depends on launching the app.
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) { _, _ in }
    }
}
