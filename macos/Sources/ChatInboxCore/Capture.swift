import Foundation
import CryptoKit
import Darwin

public enum CaptureError: Error, LocalizedError {
    case invalidSource, limitExceeded, empty, finished, invalidHome
    public var errorDescription: String? {
        switch self {
        case .invalidSource: return "Only regular, non-symlink files can be received."
        case .limitExceeded: return "Shared data exceeds the 1 GiB / 1000 item limit."
        case .empty: return "The share contains no readable content."
        case .finished: return "This capture is already finished."
        case .invalidHome: return "Cannot resolve the current user's home directory."
        }
    }
}

public struct ManifestItem: Codable {
    public let id, relativePath, displayName, contentType, kind, sha256: String
    public let byteCount: Int64
}

public struct Manifest: Codable {
    public let schemaVersion: Int
    public let batchId, createdAt, action, source: String
    public let formats: [String]
    public let items: [ManifestItem]
    public let warnings, unhandledFormats: [String]
    public let partial: Bool
}

public final class Capture {
    public static let defaultLimit: Int64 = 1_073_741_824
    public let batchId = UUID().uuidString.lowercased()
    public var formats: [String] = []
    public var warnings: [String] = []
    public var unhandledFormats: [String] = []
    private let root: URL
    private let stage: URL
    private let source: String
    private let limit: Int64
    private var total: Int64 = 0
    private var items: [ManifestItem] = []
    private var finished = false

    public static func accountHome() throws -> URL {
        // NSHomeDirectory points inside the extension's sandbox, not the account home.
        guard let entry = getpwuid(getuid()), let path = entry.pointee.pw_dir else { throw CaptureError.invalidHome }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }

    public static func defaultInbox() throws -> URL {
        try accountHome().appendingPathComponent(".agent-chat-receiver/Inbox", isDirectory: true)
    }

    public init(inbox: URL, source: String, limit: Int64 = Capture.defaultLimit) throws {
        guard limit > 0 else { throw CaptureError.limitExceeded }
        self.root = inbox.standardizedFileURL
        self.source = source
        self.limit = limit
        self.stage = inbox.appendingPathComponent("Staging/\(batchId).staging", isDirectory: true)
        try FileManager.default.createDirectory(at: stage.appendingPathComponent("files"), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    public static func safeName(_ raw: String) -> String {
        let invalid = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:*?\"<>|"))
        let clean = raw.unicodeScalars.map { invalid.contains($0) ? "_" : String($0) }.joined()
        let trimmed = String(clean.prefix(160)).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return trimmed.isEmpty ? "shared.bin" : trimmed
    }

    public func addFile(_ file: URL, displayName: String? = nil, contentType: String = "application/octet-stream", kind: String = "file") throws {
        let descriptor = Darwin.open(file.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw CaptureError.invalidSource }
        let input = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? input.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { throw CaptureError.invalidSource }
        guard info.st_size <= limit - total else { throw CaptureError.limitExceeded }
        try addStream(name: displayName ?? file.lastPathComponent, contentType: contentType, kind: kind) {
            try input.read(upToCount: 131_072) ?? Data()
        }
    }

    public func addData(_ data: Data, name: String, contentType: String, kind: String) throws {
        var offset = 0
        try addStream(name: name, contentType: contentType, kind: kind) {
            let end = min(offset + 131_072, data.count)
            defer { offset = end }
            return data.subdata(in: offset..<end)
        }
    }

    public func addText(_ text: String, name: String = "shared-text.txt", contentType: String = "text/plain", kind: String = "text") throws {
        try addData(Data(text.utf8), name: name, contentType: contentType, kind: kind)
    }

    private func addStream(name: String, contentType: String, kind: String, read: () throws -> Data) throws {
        guard !finished else { throw CaptureError.finished }
        guard items.count < 1000 else { throw CaptureError.limitExceeded }
        let relative = "files/" + String(format: "%04d_", items.count + 1) + Self.safeName(name)
        let destination = stage.appendingPathComponent(relative)
        let descriptor = Darwin.open(destination.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? output.close() }
        var digest = SHA256()
        var count: Int64 = 0
        while true {
            let chunk = try read()
            if chunk.isEmpty { break }
            guard Int64(chunk.count) <= limit - total else { throw CaptureError.limitExceeded }
            total += Int64(chunk.count)
            count += Int64(chunk.count)
            try output.write(contentsOf: chunk)
            digest.update(data: chunk)
        }
        try output.synchronize()
        items.append(ManifestItem(id: UUID().uuidString.lowercased(), relativePath: relative, displayName: name,
            contentType: contentType, kind: kind, sha256: digest.finalize().map { String(format: "%02x", $0) }.joined(), byteCount: count))
    }

    @discardableResult public func commit() throws -> URL {
        guard !finished else { throw CaptureError.finished }
        guard !items.isEmpty else { throw CaptureError.empty }
        let manifest = Manifest(schemaVersion: 1, batchId: batchId, createdAt: ISO8601DateFormatter().string(from: Date()),
            action: "capture", source: source, formats: formats, items: items, warnings: warnings,
            unhandledFormats: unhandledFormats, partial: !warnings.isEmpty || !unhandledFormats.isEmpty)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: stage.appendingPathComponent("manifest.json"), options: .withoutOverwriting)
        let ready = root.appendingPathComponent("Ready/\(batchId)", isDirectory: true)
        try FileManager.default.createDirectory(at: ready.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.moveItem(at: stage, to: ready)
        finished = true
        return ready.appendingPathComponent("manifest.json")
    }

    public func fail(_ error: Error) {
        guard !finished else { return }
        let failed = root.appendingPathComponent("Failed/\(batchId)", isDirectory: true)
        do {
            let data = try JSONSerialization.data(withJSONObject: ["source": source, "batchId": batchId, "error": error.localizedDescription])
            try data.write(to: stage.appendingPathComponent("error.json"), options: .withoutOverwriting)
            try FileManager.default.createDirectory(at: failed.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.moveItem(at: stage, to: failed)
            finished = true
        } catch { /* An incomplete Staging batch is never consumed by an Agent. */ }
    }
}
