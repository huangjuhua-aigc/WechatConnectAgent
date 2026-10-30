import XCTest
import UniformTypeIdentifiers
@testable import ChatInboxCore

final class CaptureTests: XCTestCase {
    private func temporary() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        return folder
    }

    func testAtomicReadyManifestAndDuplicateNames() throws {
        let root = try temporary()
        let capture = try Capture(inbox: root, source: "synthetic-test")
        try capture.addText("first", name: "same.txt")
        try capture.addText("second", name: "same.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Ready").path))
        let path = try capture.commit()
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: path))
        XCTAssertEqual(manifest.items.count, 2)
        XCTAssertEqual(manifest.items[0].sha256, "a7937b64b8caa58f03721bb6bacf5c78cb235febe0e70b1b84cd99541461a08e")
        XCTAssertNotEqual(manifest.items[0].relativePath, manifest.items[1].relativePath)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Staging").path), [])
        XCTAssertThrowsError(try capture.addText("late"))
    }

    func testFailureNeverBecomesReady() throws {
        let root = try temporary()
        let capture = try Capture(inbox: root, source: "synthetic-test", limit: 3)
        do { try capture.addText("too large"); XCTFail("Expected limit error") }
        catch { capture.fail(error) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Ready").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Failed").path).count, 1)
    }

    func testSymlinkAndDirectoryAreRejected() throws {
        let root = try temporary()
        let file = root.appendingPathComponent("original")
        try Data("data".utf8).write(to: file)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let capture = try Capture(inbox: root.appendingPathComponent("inbox"), source: "synthetic-test")
        XCTAssertThrowsError(try capture.addFile(link))
        XCTAssertThrowsError(try capture.addFile(root))
    }

    func testArchiveHasPriorityOverPreviewAndURL() {
        XCTAssertEqual(ProviderImporter.preferredType([UTType.fileURL.identifier, UTType.png.identifier, UTType.zip.identifier]), UTType.zip.identifier)
        XCTAssertEqual(ProviderImporter.preferredType([UTType.fileURL.identifier]), UTType.fileURL.identifier)
    }

    func testDataProviderPreservesBytes() async throws {
        let root = try temporary()
        let provider = NSItemProvider()
        let bytes = Data("Synthetic provider text".utf8)
        provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
            completion(bytes, nil); return nil
        }
        let capture = try Capture(inbox: root, source: "synthetic-provider")
        try await ProviderImporter.receive(provider, into: capture)
        let path = try capture.commit()
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: path))
        XCTAssertEqual(manifest.items.count, 1)
        XCTAssertEqual(try Data(contentsOf: path.deletingLastPathComponent().appendingPathComponent(manifest.items[0].relativePath)), bytes)
    }

    func testFileProviderCopiesBeforeSourceDisappears() async throws {
        let root = try temporary()
        let file = root.appendingPathComponent("attachment.zip")
        let bytes = Data([0x50, 0x4b, 0x03, 0x04, 0, 1, 2])
        try bytes.write(to: file)
        let provider = try XCTUnwrap(NSItemProvider(contentsOf: file))
        let capture = try Capture(inbox: root.appendingPathComponent("inbox"), source: "synthetic-provider")
        try await ProviderImporter.receive(provider, into: capture)
        try FileManager.default.removeItem(at: file)
        let path = try capture.commit()
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: path))
        XCTAssertEqual(try Data(contentsOf: path.deletingLastPathComponent().appendingPathComponent(manifest.items[0].relativePath)), bytes)
    }
}
