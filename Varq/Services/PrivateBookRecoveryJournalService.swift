import CryptoKit
import Foundation

struct PrivateBookRecoveryRecord: Codable, Equatable {
    let version: Int
    let bookID: UUID
    let fileName: String
    let originalIsPrivate: Bool
    let originalHash: String
    let changedHash: String
}

/// The unkeyed checksum detects accidental metadata damage; it is not an
/// authentication mechanism against an attacker who can rewrite the app sandbox.
private struct PrivateBookRecoveryEnvelope: Codable {
    let record: PrivateBookRecoveryRecord
    let checksum: String
}

struct PrivateBookRecoveryState {
    let record: PrivateBookRecoveryRecord
    let isPrivate: Bool
    let contentHash: String
}

enum PrivateBookRecoveryError: LocalizedError, Equatable {
    case pendingChange
    case invalidJournal
    case unrecognizedContent
    case missingBook
    case unsafePath

    var errorDescription: String? {
        switch self {
        case .pendingChange: "An earlier book protection change needs recovery first."
        case .invalidJournal: "The book protection recovery record is damaged or unsupported. Varq will not use it to change book files."
        case .unrecognizedContent: "The managed file does not match either recorded protection state. Varq has kept the recovery record and will not guess."
        case .missingBook: "A book protection recovery record has no matching library entry. The record has been kept."
        case .unsafePath: "The book protection recovery path is unsafe. Varq will not follow it."
        }
    }
}

/// A write-ahead journal inside the managed library. It stores hashes and a
/// tracked replacement file, never keys or an additional original plaintext copy.
@MainActor
final class PrivateBookRecoveryJournalService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func begin(
        bookID: UUID,
        managedFileURL: URL,
        originalIsPrivate: Bool,
        originalData: Data,
        changedData: Data
    ) throws -> PrivateBookRecoveryRecord {
        let library = managedFileURL.deletingLastPathComponent().resolvingSymlinksInPath()
        try validateManagedFile(managedFileURL, in: library)
        let record = PrivateBookRecoveryRecord(
            version: 1,
            bookID: bookID,
            fileName: managedFileURL.lastPathComponent,
            originalIsPrivate: originalIsPrivate,
            originalHash: digest(originalData),
            changedHash: digest(changedData)
        )
        try validateRecord(record)
        let root = try journalRoot(in: library)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let directory = root.appendingPathComponent(bookID.uuidString, isDirectory: true)
        guard !fileManager.fileExists(atPath: directory.path) else {
            throw PrivateBookRecoveryError.pendingChange
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let recordURL = directory.appendingPathComponent("record.json")
        let envelope = PrivateBookRecoveryEnvelope(record: record, checksum: digest(try canonicalData(record)))
        try JSONEncoder().encode(envelope).write(to: recordURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recordURL.path)
        return record
    }

    func replaceManagedFile(_ record: PrivateBookRecoveryRecord, in library: URL, with data: Data) throws {
        let hash = digest(data)
        guard hash == record.originalHash || hash == record.changedHash else {
            throw PrivateBookRecoveryError.unrecognizedContent
        }
        let directory = try transactionDirectory(record.bookID, in: library)
        guard try loadRecord(in: directory) == record else { throw PrivateBookRecoveryError.invalidJournal }
        // Do not overwrite content changed since the journal was prepared.
        _ = try state(for: record, in: library)
        let managedFile = library.appendingPathComponent(record.fileName)
        try validateManagedFile(managedFile, in: library)
        let replacement = directory.appendingPathComponent("replacement")
        try validateContainedPath(replacement)
        try data.write(to: replacement, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: replacement.path)
        _ = try fileManager.replaceItemAt(managedFile, withItemAt: replacement, options: .usingNewMetadataOnly)
    }

    func state(for record: PrivateBookRecoveryRecord, in library: URL) throws -> PrivateBookRecoveryState {
        try validateRecord(record)
        let directory = try transactionDirectory(record.bookID, in: library)
        guard try loadRecord(in: directory) == record else { throw PrivateBookRecoveryError.invalidJournal }
        let managedFile = library.appendingPathComponent(record.fileName)
        try validateManagedFile(managedFile, in: library)
        let hash = digest(try Data(contentsOf: managedFile))
        if hash == record.originalHash {
            return PrivateBookRecoveryState(record: record, isPrivate: record.originalIsPrivate, contentHash: hash)
        }
        if hash == record.changedHash {
            return PrivateBookRecoveryState(record: record, isPrivate: !record.originalIsPrivate, contentHash: hash)
        }
        throw PrivateBookRecoveryError.unrecognizedContent
    }

    func pendingStates(in library: URL) throws -> [PrivateBookRecoveryState] {
        let root = try journalRoot(in: library)
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        var states: [PrivateBookRecoveryState] = []
        for directory in try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) {
            try validateContainedPath(directory)
            let name = directory.lastPathComponent
            if name.hasPrefix(".completed-"), UUID(uuidString: String(name.dropFirst(".completed-".count))) != nil {
                // Renaming to this tombstone commits completion after the database
                // and key cleanup. Its remaining files are safe to remove even if
                // an earlier cleanup already deleted record.json.
                try fileManager.removeItem(at: directory)
                continue
            }
            guard let bookID = UUID(uuidString: name) else {
                throw PrivateBookRecoveryError.invalidJournal
            }
            // A crash before writing the record (or after removing it) can leave
            // an empty directory. No file/key mutation precedes the record write.
            if try fileManager.contentsOfDirectory(atPath: directory.path).isEmpty {
                try fileManager.removeItem(at: directory)
                continue
            }
            let record = try loadRecord(in: directory)
            guard record.bookID == bookID else { throw PrivateBookRecoveryError.invalidJournal }
            let state = try state(for: record, in: library)
            // Only discard staging after verifying the managed copy. If that copy
            // is missing or unknown, preserve all artifacts for manual recovery.
            // This also clears staged plaintext from an interrupted unprotect.
            let replacement = directory.appendingPathComponent("replacement")
            try validateContainedPath(replacement)
            if fileManager.fileExists(atPath: replacement.path) {
                try fileManager.removeItem(at: replacement)
            }
            states.append(state)
        }
        return states
    }

    func finish(_ state: PrivateBookRecoveryState, in library: URL) throws {
        let directory = try transactionDirectory(state.record.bookID, in: library)
        guard try loadRecord(in: directory) == state.record,
              try self.state(for: state.record, in: library).contentHash == state.contentHash else {
            throw PrivateBookRecoveryError.unrecognizedContent
        }
        let completed = directory.deletingLastPathComponent()
            .appendingPathComponent(".completed-" + state.record.bookID.uuidString, isDirectory: true)
        try validateContainedPath(completed)
        // Atomic rename preserves an explicit completion marker across a crash
        // during recursive deletion. The persisted flag already matches this state.
        try fileManager.moveItem(at: directory, to: completed)
        try fileManager.removeItem(at: completed)
    }

    private func loadRecord(in directory: URL) throws -> PrivateBookRecoveryRecord {
        let recordURL = directory.appendingPathComponent("record.json")
        try validateContainedPath(recordURL)
        let envelope: PrivateBookRecoveryEnvelope
        do {
            envelope = try JSONDecoder().decode(PrivateBookRecoveryEnvelope.self, from: Data(contentsOf: recordURL))
            guard envelope.checksum == digest(try canonicalData(envelope.record)) else {
                throw PrivateBookRecoveryError.invalidJournal
            }
        } catch {
            throw PrivateBookRecoveryError.invalidJournal
        }
        try validateRecord(envelope.record)
        return envelope.record
    }

    private func validateRecord(_ record: PrivateBookRecoveryRecord) throws {
        guard record.version == 1,
              !record.fileName.isEmpty,
              record.fileName != ".", record.fileName != "..",
              !record.fileName.contains("/"), !record.fileName.contains("\\"),
              record.originalHash.count == 64, record.changedHash.count == 64,
              record.originalHash != record.changedHash else {
            throw PrivateBookRecoveryError.invalidJournal
        }
    }

    private func journalRoot(in library: URL) throws -> URL {
        let root = library.resolvingSymlinksInPath().appendingPathComponent(".private-book-recovery", isDirectory: true)
        try validateContainedPath(root)
        return root
    }

    private func transactionDirectory(_ bookID: UUID, in library: URL) throws -> URL {
        let directory = try journalRoot(in: library).appendingPathComponent(bookID.uuidString, isDirectory: true)
        try validateContainedPath(directory)
        return directory
    }

    private func validateManagedFile(_ url: URL, in library: URL) throws {
        let expected = library.resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).standardizedFileURL
        guard url.resolvingSymlinksInPath().standardizedFileURL.path == expected.path else {
            throw PrivateBookRecoveryError.unsafePath
        }
    }

    private func validateContainedPath(_ url: URL) throws {
        guard url.standardizedFileURL.path == url.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw PrivateBookRecoveryError.unsafePath
        }
    }

    private func canonicalData(_ record: PrivateBookRecoveryRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(record)
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
