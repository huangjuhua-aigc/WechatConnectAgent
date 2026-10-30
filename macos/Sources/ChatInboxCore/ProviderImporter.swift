import Foundation
import UniformTypeIdentifiers

public enum ProviderImporter {
    public enum ImportError: Error, LocalizedError {
        case noRepresentation, unavailable(String)
        public var errorDescription: String? {
            switch self {
            case .noRepresentation: return "The shared item has no supported representation."
            case .unavailable(let type): return "The source did not supply the advertised format: \(type)."
            }
        }
    }

    public static func preferredType(_ identifiers: [String]) -> String? {
        for wanted in [UTType.zip, .archive] {
            if let found = identifiers.first(where: { UTType($0)?.conforms(to: wanted) == true }) { return found }
        }
        if let found = identifiers.first(where: { id in
            guard let type = UTType(id) else { return false }
            return type.conforms(to: .data) && !type.conforms(to: .url)
        }) { return found }
        if identifiers.contains(UTType.fileURL.identifier) { return UTType.fileURL.identifier }
        if identifiers.contains(UTType.url.identifier) { return UTType.url.identifier }
        return identifiers.first
    }

    public static func receive(_ provider: NSItemProvider, into capture: Capture) async throws {
        let types = provider.registeredTypeIdentifiers
        for type in types where !capture.formats.contains(type) { capture.formats.append(type) }
        guard let identifier = preferredType(types) else { throw ImportError.noRepresentation }
        let type = UTType(identifier)
        if type?.conforms(to: .url) == true {
            let url = try await loadURL(provider, type: identifier)
            if url.isFileURL {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                var coordinatorError: NSError?
                var copyError: Error?
                NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinatorError) { source in
                    do { try capture.addFile(source, displayName: provider.suggestedName) }
                    catch { copyError = error }
                }
                if let coordinatorError { throw coordinatorError }
                if let copyError { throw copyError }
            } else {
                try capture.addText(url.absoluteString, name: "shared-link.txt", contentType: "text/uri-list", kind: "uri")
            }
            return
        }
        let contentType = type?.preferredMIMEType ?? identifier
        let kind = type?.conforms(to: .plainText) == true ? "text" : "file"
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                provider.loadFileRepresentation(forTypeIdentifier: identifier) { temporary, error in
                    guard error == nil, let temporary else {
                        continuation.resume(throwing: ImportError.unavailable(identifier)); return
                    }
                    do {
                        // The temporary representation is valid only until this callback returns.
                        try capture.addFile(temporary, displayName: displayName(provider, type: type, fallback: temporary.lastPathComponent), contentType: contentType, kind: kind)
                        continuation.resume()
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } catch is ImportError {
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let data { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: ImportError.unavailable(identifier)) }
                }
            }
            try capture.addData(data, name: displayName(provider, type: type, fallback: "shared"), contentType: contentType, kind: kind)
        }
    }

    private static func displayName(_ provider: NSItemProvider, type: UTType?, fallback: String) -> String {
        var name = provider.suggestedName.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        if (name as NSString).pathExtension.isEmpty { name += "." + (type?.preferredFilenameExtension ?? "bin") }
        return name
    }

    private static func loadURL(_ provider: NSItemProvider, type: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let error { continuation.resume(throwing: error); return }
                if let url = item as? URL { continuation.resume(returning: url) }
                else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { continuation.resume(returning: url) }
                else if let text = item as? String, let url = URL(string: text) { continuation.resume(returning: url) }
                else { continuation.resume(throwing: ImportError.unavailable(type)) }
            }
        }
    }
}
