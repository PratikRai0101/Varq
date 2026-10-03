import Foundation
import Testing
@testable import Varq

@MainActor
struct ReaderSessionStorageServiceTests {
    @Test func failedCloseBlocksNewAllocationUntilCleanupCanBeRetried() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = FailingSessionCleanupFileManager()
        let storage = ReaderSessionStorageService(rootDirectory: root, fileManager: manager)
        let directory = try storage.makeDirectory()
        let file = directory.appendingPathComponent("private.pdf")
        try Data("private text".utf8).write(to: file)
        manager.failingPath = directory.path
        #expect(throws: SessionCleanupTestError.denied) { try storage.removeDirectory(directory) }
        #expect(throws: SessionCleanupTestError.denied) { _ = try storage.makeDirectory() }
        #expect(FileManager.default.fileExists(atPath: file.path))
        manager.failingPath = nil
        _ = try storage.makeDirectory()
        #expect(!FileManager.default.fileExists(atPath: file.path))
        try storage.removeDirectory(directory)
    }

    @Test func interruptedRecursiveCleanupKeepsACompletionMarkerForRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var old: ReaderSessionStorageService? = ReaderSessionStorageService(rootDirectory: root)
        let directory = try #require(old).makeDirectory()
        try Data("abandoned text".utf8).write(to: directory.appendingPathComponent("book.epub"))
        old = nil
        let manager = FailingSessionCleanupFileManager()
        manager.failDiscarded = true
        let cleanup = ReaderSessionStorageService(rootDirectory: root, fileManager: manager)
        #expect(throws: SessionCleanupTestError.denied) { try cleanup.cleanupStaleSessions() }
        let discarded = try #require(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix(".discarded-") })
        try FileManager.default.removeItem(at: discarded.appendingPathComponent("lease.lock"))
        try ReaderSessionStorageService(rootDirectory: root).cleanupStaleSessions()
        #expect(!FileManager.default.fileExists(atPath: discarded.path))
    }

    @Test(arguments: ["unknown.epub", ".discarded-00000000-0000-0000-0000-000000000000"])
    func unknownEntriesAndLegacyFoldersArePreserved(name: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("ReaderSessions")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let unknown = root.appendingPathComponent(name)
        let legacy = directory.appendingPathComponent(UUID().uuidString)
        let text = Data("do not infer ownership".utf8)
        try text.write(to: unknown)
        try text.write(to: legacy)
        #expect(throws: ReaderSessionStorageError.unrecognizedSession) {
            try ReaderSessionStorageService(rootDirectory: root).cleanupStaleSessions()
        }
        #expect(try Data(contentsOf: unknown) == text)
        #expect(try Data(contentsOf: legacy) == text)
    }

    @Test func leaseSymlinksNeverExposeTheirTargetsToCleanup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("ReaderSessions")
        var old: ReaderSessionStorageService? = ReaderSessionStorageService(rootDirectory: sessions)
        let directory = try #require(old).makeDirectory()
        old = nil
        let lease = directory.deletingLastPathComponent().appendingPathComponent("lease.lock")
        let target = root.appendingPathComponent("original.epub")
        let text = Data("original book, not a lease".utf8)
        try text.write(to: target)
        try FileManager.default.removeItem(at: lease)
        try FileManager.default.createSymbolicLink(at: lease, withDestinationURL: target)
        #expect(throws: ReaderSessionStorageError.unsafePath) {
            try ReaderSessionStorageService(rootDirectory: sessions).cleanupStaleSessions()
        }
        #expect(try Data(contentsOf: target) == text)
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func allocatedDirectoriesHaveOwnerOnlyPermissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = ReaderSessionStorageService(rootDirectory: root)
        let directory = try storage.makeDirectory()
        for path in [root, directory.deletingLastPathComponent(), directory] {
            let mode = try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? NSNumber
            #expect(mode?.intValue == 0o700)
        }
        let lease = directory.deletingLastPathComponent().appendingPathComponent("lease.lock")
        let mode = try FileManager.default.attributesOfItem(atPath: lease.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }

    @Test func releasingAnOwnedDirectoryIsIdempotentButNeverDeletesUnownedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = ReaderSessionStorageService(rootDirectory: root.appendingPathComponent("ReaderSessions"))
        let directory = try storage.makeDirectory()
        try storage.removeDirectory(directory)
        try storage.removeDirectory(directory)
        let unrelated = root.appendingPathComponent("original.epub")
        let original = Data("preserve original".utf8)
        try original.write(to: unrelated)
        #expect(throws: ReaderSessionStorageError.unsafePath) {
            try storage.removeDirectory(unrelated)
        }
        #expect(try Data(contentsOf: unrelated) == original)
    }

    @Test(arguments: ["ReaderSessions", "missing/ReaderSessions"])
    func refusesASymlinkedStorageParentWithoutWritingIntoItsTarget(subpath: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let linkedParent = directory.appendingPathComponent("linked-parent")
        try FileManager.default.createSymbolicLink(at: linkedParent, withDestinationURL: target)
        let storage = ReaderSessionStorageService(rootDirectory: linkedParent.appendingPathComponent(subpath))

        #expect(throws: ReaderSessionStorageError.unsafePath) {
            _ = try storage.makeDirectory()
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
    }

    @Test func restartRemovesAbandonedPlaintextButPreservesActiveReaderFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var abandoned: ReaderSessionStorageService? = ReaderSessionStorageService(rootDirectory: root)
        let staleDirectory = try #require(abandoned).makeDirectory()
        let staleFile = staleDirectory.appendingPathComponent("book.epub")
        try Data("abandoned private book".utf8).write(to: staleFile)
        let active = ReaderSessionStorageService(rootDirectory: root)
        let liveDirectory = try active.makeDirectory()
        let liveFile = liveDirectory.appendingPathComponent("book.pdf")
        let liveText = Data("active reader, preserve me".utf8)
        try liveText.write(to: liveFile)
        abandoned = nil // Release the process lease, as process termination does.
        #expect(FileManager.default.fileExists(atPath: staleFile.path))
        let restarted = ReaderSessionStorageService(rootDirectory: root)

        try withExtendedLifetime(active) {
            try restarted.cleanupStaleSessions()
            #expect(!FileManager.default.fileExists(atPath: staleFile.path))
            #expect(try Data(contentsOf: liveFile) == liveText)
        }
    }
}
