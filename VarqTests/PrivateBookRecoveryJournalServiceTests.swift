import CryptoKit
import Foundation
import Testing
@testable import Varq

@MainActor
struct PrivateBookRecoveryJournalServiceTests {
    @Test func reloadsBothRecordedStatesAndClearsOnlyAFinishedChange() throws {
        let fixture = try JournalFixture()
        defer { fixture.cleanup() }
        let journal = PrivateBookRecoveryJournalService()
        let record = try fixture.begin(using: journal)
        let reloaded = PrivateBookRecoveryJournalService()
        #expect(try reloaded.pendingStates(in: fixture.directory).first?.isPrivate == false)
        #expect(try Data(contentsOf: fixture.recordURL).range(of: fixture.original) == nil)

        try journal.replaceManagedFile(record, in: fixture.directory, with: fixture.changed)

        let state = try #require(reloaded.pendingStates(in: fixture.directory).first)
        #expect(state.isPrivate)
        #expect(try Data(contentsOf: fixture.fileURL) == fixture.changed)
        let permissions = try FileManager.default.attributesOfItem(atPath: fixture.fileURL.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        try reloaded.finish(state, in: fixture.directory)
        #expect(try reloaded.pendingStates(in: fixture.directory).isEmpty)
    }

    @Test func restartFinishesInterruptedJournalCleanupWithoutReclassifyingTheBook() throws {
        let fixture = try JournalFixture()
        defer { fixture.cleanup() }
        let journal = PrivateBookRecoveryJournalService(fileManager: CleanupFailingFileManager())
        let record = try fixture.begin(using: journal)
        try journal.replaceManagedFile(record, in: fixture.directory, with: fixture.changed)
        let state = try journal.state(for: record, in: fixture.directory)

        #expect(throws: JournalTestError.cleanupFailed) {
            try journal.finish(state, in: fixture.directory)
        }
        let completionDirectory = fixture.recordURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".completed-" + fixture.bookID.uuidString)
        #expect(FileManager.default.fileExists(atPath: completionDirectory.path))
        // Simulate termination partway through cleanup, after metadata removal.
        try FileManager.default.removeItem(at: completionDirectory.appendingPathComponent("record.json"))
        try Data("leftover staging".utf8).write(to: completionDirectory.appendingPathComponent("replacement"))
        let restarted = PrivateBookRecoveryJournalService()
        #expect(try restarted.pendingStates(in: fixture.directory).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: completionDirectory.path))
        #expect(try Data(contentsOf: fixture.fileURL) == fixture.changed)
    }

    @Test func refusesANewOperationUntilTheExistingRecordIsResolved() throws {
        let fixture = try JournalFixture()
        defer { fixture.cleanup() }
        let journal = PrivateBookRecoveryJournalService()
        _ = try fixture.begin(using: journal)
        let originalRecord = try Data(contentsOf: fixture.recordURL)

        #expect(throws: PrivateBookRecoveryError.pendingChange) {
            _ = try fixture.begin(using: journal)
        }
        #expect(try Data(contentsOf: fixture.recordURL) == originalRecord)
        #expect(try Data(contentsOf: fixture.fileURL) == fixture.original)
    }

    @Test(arguments: [0, 2])
    func rejectsUnsupportedJournalVersions(version: Int) throws {
        let fixture = try JournalFixture()
        defer { fixture.cleanup() }
        let journal = PrivateBookRecoveryJournalService()
        let record = try fixture.begin(using: journal)
        let unsupported = PrivateBookRecoveryRecord(
            version: version, bookID: record.bookID, fileName: record.fileName,
            originalIsPrivate: record.originalIsPrivate, originalHash: record.originalHash, changedHash: record.changedHash
        )
        try fixture.writeRecord(unsupported)

        #expect(throws: PrivateBookRecoveryError.invalidJournal) {
            _ = try journal.pendingStates(in: fixture.directory)
        }
        #expect(try Data(contentsOf: fixture.fileURL) == fixture.original)
        #expect(FileManager.default.fileExists(atPath: fixture.recordURL.path))
    }

    @Test(arguments: ["../outside.epub", "/outside.epub", "subfolder/book.epub", "..", ""])
    func rejectsJournalPathTraversal(fileName: String) throws {
        let fixture = try JournalFixture()
        defer { fixture.cleanup() }
        let journal = PrivateBookRecoveryJournalService()
        let record = try fixture.begin(using: journal)
        let unsafe = PrivateBookRecoveryRecord(
            version: 1, bookID: record.bookID, fileName: fileName,
            originalIsPrivate: record.originalIsPrivate, originalHash: record.originalHash, changedHash: record.changedHash
        )
        try fixture.writeRecord(unsafe)

        #expect(throws: PrivateBookRecoveryError.invalidJournal) {
            _ = try journal.pendingStates(in: fixture.directory)
        }
        #expect(try Data(contentsOf: fixture.fileURL) == fixture.original)
    }

    @Test func detectsAChangedPrivacyFlagInOtherwiseValidJSON() throws {
        let fixture = try JournalFixture()
        defer { fixture.cleanup() }
        let journal = PrivateBookRecoveryJournalService()
        _ = try fixture.begin(using: journal)
        var document = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.recordURL)) as? [String: Any])
        var record = try #require(document["record"] as? [String: Any])
        record["originalIsPrivate"] = true
        document["record"] = record
        try JSONSerialization.data(withJSONObject: document).write(to: fixture.recordURL)

        #expect(throws: PrivateBookRecoveryError.invalidJournal) {
            _ = try journal.pendingStates(in: fixture.directory)
        }
        #expect(try Data(contentsOf: fixture.fileURL) == fixture.original)
        #expect(FileManager.default.fileExists(atPath: fixture.recordURL.path))
    }

    @Test func preservesMalformedRecordsForManualRecovery() throws {
        let fixture = try JournalFixture()
        defer { fixture.cleanup() }
        let journal = PrivateBookRecoveryJournalService()
        _ = try fixture.begin(using: journal)
        let malformed = Data("{broken record".utf8)
        try malformed.write(to: fixture.recordURL)

        #expect(throws: PrivateBookRecoveryError.invalidJournal) {
            _ = try journal.pendingStates(in: fixture.directory)
        }
        #expect(try Data(contentsOf: fixture.recordURL) == malformed)
        #expect(try Data(contentsOf: fixture.fileURL) == fixture.original)
    }

    @Test func missingManagedFilePreservesBothTheRecordAndStaging() throws {
        let fixture = try JournalFixture()
        defer { fixture.cleanup() }
        let journal = PrivateBookRecoveryJournalService()
        _ = try fixture.begin(using: journal)
        try fixture.changed.write(to: fixture.replacementURL)
        try FileManager.default.removeItem(at: fixture.fileURL)

        #expect(throws: (any Error).self) {
            _ = try journal.pendingStates(in: fixture.directory)
        }
        #expect(FileManager.default.fileExists(atPath: fixture.recordURL.path))
        #expect(try Data(contentsOf: fixture.replacementURL) == fixture.changed)
    }

    @Test func unknownManagedContentIsNotOverwrittenOrDiscarded() throws {
        let fixture = try JournalFixture()
        defer { fixture.cleanup() }
        let journal = PrivateBookRecoveryJournalService()
        let record = try fixture.begin(using: journal)
        let unknown = Data("unexpected content, preserve me".utf8)
        try unknown.write(to: fixture.fileURL)
        try fixture.changed.write(to: fixture.replacementURL)

        #expect(throws: PrivateBookRecoveryError.unrecognizedContent) {
            try journal.replaceManagedFile(record, in: fixture.directory, with: fixture.changed)
        }
        #expect(throws: PrivateBookRecoveryError.unrecognizedContent) {
            _ = try journal.pendingStates(in: fixture.directory)
        }
        #expect(try Data(contentsOf: fixture.fileURL) == unknown)
        #expect(try Data(contentsOf: fixture.replacementURL) == fixture.changed)
    }

    @Test func discardsUncommittedStagingOnlyWhenTheManagedCopyIsVerified() throws {
        let fixture = try JournalFixture()
        defer { fixture.cleanup() }
        let journal = PrivateBookRecoveryJournalService()
        _ = try fixture.begin(using: journal)
        try fixture.changed.write(to: fixture.replacementURL)

        let state = try #require(journal.pendingStates(in: fixture.directory).first)

        #expect(!state.isPrivate)
        #expect(try Data(contentsOf: fixture.fileURL) == fixture.original)
        #expect(!FileManager.default.fileExists(atPath: fixture.replacementURL.path))
        #expect(FileManager.default.fileExists(atPath: fixture.recordURL.path))
    }

    @Test func refusesManagedFileSymlinksWithoutChangingTheTarget() throws {
        let fixture = try JournalFixture()
        defer { fixture.cleanup() }
        let journal = PrivateBookRecoveryJournalService()
        let record = try fixture.begin(using: journal)
        let otherFile = fixture.directory.appendingPathComponent("other.epub")
        try fixture.original.write(to: otherFile)
        try FileManager.default.removeItem(at: fixture.fileURL)
        try FileManager.default.createSymbolicLink(at: fixture.fileURL, withDestinationURL: otherFile)

        #expect(throws: PrivateBookRecoveryError.unsafePath) {
            try journal.replaceManagedFile(record, in: fixture.directory, with: fixture.changed)
        }
        #expect(try Data(contentsOf: otherFile) == fixture.original)
        #expect(FileManager.default.fileExists(atPath: fixture.recordURL.path))
    }

    @Test func rejectsIndistinguishableStatesBeforeWritingARecord() throws {
        let fixture = try JournalFixture()
        defer { fixture.cleanup() }
        let journal = PrivateBookRecoveryJournalService()

        #expect(throws: PrivateBookRecoveryError.invalidJournal) {
            _ = try journal.begin(
                bookID: fixture.bookID, managedFileURL: fixture.fileURL,
                originalIsPrivate: false, originalData: fixture.original, changedData: fixture.original
            )
        }
        #expect(try Data(contentsOf: fixture.fileURL) == fixture.original)
        #expect(!FileManager.default.fileExists(atPath: fixture.recordURL.path))
    }
}

private enum JournalTestError: Error {
    case cleanupFailed
}

// Stateless system-boundary fault injection; FileManager is itself unchecked Sendable.
private final class CleanupFailingFileManager: FileManager, @unchecked Sendable {
    override func removeItem(at URL: URL) throws {
        if URL.lastPathComponent.hasPrefix(".completed-") {
            throw JournalTestError.cleanupFailed
        }
        try super.removeItem(at: URL)
    }
}

private struct JournalFixture {
    let directory: URL
    let fileURL: URL
    let bookID = UUID()
    let original = Data("original plaintext fixture, never store this in the journal".utf8)
    let changed = Data("different protected fixture bytes".utf8)

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        fileURL = directory.appendingPathComponent("book.epub")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try original.write(to: fileURL)
    }

    @MainActor
    func begin(using journal: PrivateBookRecoveryJournalService) throws -> PrivateBookRecoveryRecord {
        try journal.begin(
            bookID: bookID, managedFileURL: fileURL,
            originalIsPrivate: false, originalData: original, changedData: changed
        )
    }

    /// Create a syntactically intact on-disk envelope with deliberately invalid
    /// record semantics. This separates schema/path checks from checksum checks.
    @MainActor
    func writeRecord(_ record: PrivateBookRecoveryRecord) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        let fields = try JSONSerialization.jsonObject(with: data)
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try JSONSerialization.data(withJSONObject: ["record": fields, "checksum": checksum]).write(to: recordURL)
    }

    var recordURL: URL {
        directory.appendingPathComponent(".private-book-recovery")
            .appendingPathComponent(bookID.uuidString).appendingPathComponent("record.json")
    }

    var replacementURL: URL { recordURL.deletingLastPathComponent().appendingPathComponent("replacement") }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
