import AppKit
import ChatInboxCore

func option(_ key: String) -> String? {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: key), index + 1 < args.count else { return nil }
    return args[index + 1]
}

func writeResult(_ value: [String: Any], to path: String?) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    if let path { try data.write(to: URL(fileURLWithPath: path), options: .withoutOverwriting) }
    else { FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8)) }
}

if CommandLine.arguments.contains("--import") || CommandLine.arguments.contains("--identity") {
    do {
        if CommandLine.arguments.contains("--identity") {
            try writeResult(["ok": true, "name": Bundle.main.bundleIdentifier ?? "unbundled", "platform": "macos"], to: option("--result"))
        } else {
            guard let path = option("--import") else { throw CaptureError.empty }
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard data.count <= 16_777_216, let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CaptureError.empty }
            let inbox = try option("--inbox").map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Capture.defaultInbox()
            let limit = option("--max-bytes").flatMap(Int64.init) ?? Capture.defaultLimit
            let capture = try Capture(inbox: inbox, source: "explicit-local-import", limit: limit)
            do {
                for file in payload["files"] as? [String] ?? [] {
                    capture.formats.append("StorageItems")
                    try capture.addFile(URL(fileURLWithPath: file))
                }
                for kind in ["text", "uri", "html", "rtf"] {
                    guard let text = payload[kind] as? String else { continue }
                    capture.formats.append(kind)
                    let suffix = (kind == "text" || kind == "uri") ? "txt" : kind
                    let mime = kind == "html" ? "text/html" : kind == "rtf" ? "application/rtf" : "text/plain"
                    try capture.addText(text, name: "shared." + suffix, contentType: mime, kind: kind)
                }
                let manifest = try capture.commit()
                try writeResult(["ok": true, "manifest": manifest.path], to: option("--result"))
            } catch { capture.fail(error); throw error }
        }
        exit(0)
    } catch {
        try? writeResult(["ok": false, "error": error.localizedDescription], to: option("--result"))
        exit(2)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
