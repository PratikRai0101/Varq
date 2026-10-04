import CryptoKit
import Foundation

struct CommittedImportBook: Sendable {
    let id: UUID
    let fileName: String
    let contentHash: String
    let isPrivate: Bool
}

struct ImportRecoveryRecord: Codable, Equatable, Sendable {
    let version: Int
    let bookID: UUID
    let format: BookFormat
    let contentHash: String
    let checksum: String

    var fileName: String { bookID.uuidString + "." + format.rawValue }
    fileprivate var checksumInput: Data {
        Data("\(version)\n\(bookID.uuidString)\n\(format.rawValue)\n\(contentHash)".utf8)
    }
}

/// Immutable filesystem adapter. The app serializes imports and startup recovery;
/// independent processes mutating the same library are not supported.
struct ImportRecoveryJournalService: Sendable {
    let fileManager: FileManager
    init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    func hasPendingImports(in library: URL) throws -> Bool {
        let root = journalRoot(in: library)
        try validatePath(root)
        guard fileManager.fileExists(atPath: root.path) else { return false }
        return !(try fileManager.contentsOfDirectory(atPath: root.path)).isEmpty
    }

    func begin(format: BookFormat, contentHash: String, in library: URL) throws -> ImportRecoveryRecord {
        guard try !hasPendingImports(in: library) else { throw ImportRecoveryError.pendingChange }
        let id = UUID()
        let unsigned = ImportRecoveryRecord(version: 1, bookID: id, format: format, contentHash: contentHash, checksum: "")
        let record = ImportRecoveryRecord(version: 1, bookID: id, format: format, contentHash: contentHash, checksum: digest(unsigned.checksumInput))
        try validate(record)
        let directory = transactionDirectory(record.bookID, in: library)
        let destination = library.appendingPathComponent(record.fileName)
        try validatePath(directory)
        try validatePath(destination)
        guard !fileManager.fileExists(atPath: destination.path), !fileManager.fileExists(atPath: directory.path) else {
            throw ImportRecoveryError.invalidJournal
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: journalRoot(in: library).path)
        let recordURL = directory.appendingPathComponent("record.json")
        try JSONEncoder().encode(record).write(to: recordURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recordURL.path)
        return record
    }

    func record(for fileName: String, in library: URL) throws -> ImportRecoveryRecord {
        guard URL(fileURLWithPath: fileName).lastPathComponent == fileName,
              let id = UUID(uuidString: URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent) else {
            throw ImportRecoveryError.invalidJournal
        }
        let record = try readRecord(in: transactionDirectory(id, in: library))
        guard record.fileName == fileName else { throw ImportRecoveryError.invalidJournal }
        return record
    }

    func verifyCopy(_ record: ImportRecoveryRecord, in library: URL) throws {
        try validate(record)
        guard try hashFile(library.appendingPathComponent(record.fileName)) == record.contentHash else {
            throw ImportRecoveryError.unrecognizedContent
        }
    }

    /// Keep only after a successful database save. Abandon only with known row absence.
    func settle(_ record: ImportRecoveryRecord, keepingFile: Bool, in library: URL) throws {
        let directory = transactionDirectory(record.bookID, in: library)
        guard try readRecord(in: directory) == record else { throw ImportRecoveryError.invalidJournal }
        try validateEntries(in: directory)
        let source = library.appendingPathComponent(record.fileName)
        let payload = directory.appendingPathComponent("payload")
        try validatePath(source)
        try validatePath(payload)
        let sourceExists = fileManager.fileExists(atPath: source.path)
        let payloadExists = fileManager.fileExists(atPath: payload.path)
        if keepingFile {
            guard sourceExists, !payloadExists else { throw ImportRecoveryError.unrecognizedContent }
            try verifyCopy(record, in: library)
        } else {
            guard !(sourceExists && payloadExists) else { throw ImportRecoveryError.unrecognizedContent }
            if sourceExists {
                try verifyCopy(record, in: library)
                try fileManager.moveItem(at: source, to: payload)
            } else if payloadExists {
                guard try hashFile(payload) == record.contentHash else { throw ImportRecoveryError.unrecognizedContent }
            }
        }
        let completed = journalRoot(in: library).appendingPathComponent(".completed-" + record.bookID.uuidString)
        try validatePath(completed)
        try fileManager.moveItem(at: directory, to: completed)
        try fileManager.removeItem(at: completed)
        try removeEmptyRoot(in: library)
    }

    func recover(in library: URL, committedBooks: [CommittedImportBook]) throws {
        let root = journalRoot(in: library)
        try validatePath(root)
        guard fileManager.fileExists(atPath: root.path) else { return }
        let entries = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
        for directory in entries {
            try validatePath(directory)
            guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw ImportRecoveryError.invalidJournal
            }
            let name = directory.lastPathComponent
            if name.hasPrefix(".completed-"), let id = UUID(uuidString: String(name.dropFirst(".completed-".count))) {
                try validateEntries(in: directory)
                if committedBooks.contains(where: { $0.id == id }), fileManager.fileExists(atPath: directory.appendingPathComponent("payload").path) {
                    throw ImportRecoveryError.invalidJournal
                }
                try fileManager.removeItem(at: directory)
                continue
            }
            guard let id = UUID(uuidString: name) else { throw ImportRecoveryError.invalidJournal }
            if try fileManager.contentsOfDirectory(atPath: directory.path).isEmpty {
                guard !committedBooks.contains(where: { $0.id == id }) else { throw ImportRecoveryError.invalidJournal }
                try fileManager.removeItem(at: directory)
                continue
            }
            let record = try readRecord(in: directory)
            guard record.bookID == id else { throw ImportRecoveryError.invalidJournal }
            let matching = committedBooks.filter { $0.id == id }
            let owners = committedBooks.filter { $0.fileName == record.fileName }
            if let book = matching.first {
                guard matching.count == 1, owners.count == 1, book.fileName == record.fileName,
                      book.contentHash == record.contentHash, !book.isPrivate else {
                    throw ImportRecoveryError.invalidJournal
                }
                try settle(record, keepingFile: true, in: library)
            } else {
                guard owners.isEmpty else { throw ImportRecoveryError.invalidJournal }
                try settle(record, keepingFile: false, in: library)
            }
        }
        try removeEmptyRoot(in: library)
    }

    private func readRecord(in directory: URL) throws -> ImportRecoveryRecord {
        let url = directory.appendingPathComponent("record.json")
        try validatePath(url)
        let record = try JSONDecoder().decode(ImportRecoveryRecord.self, from: Data(contentsOf: url))
        try validate(record)
        return record
    }

    private func validate(_ record: ImportRecoveryRecord) throws {
        guard record.version == 1, [.epub, .pdf, .cbz].contains(record.format),
              record.contentHash.count == 64, record.contentHash.allSatisfy({ "0123456789abcdef".contains($0) }),
              record.checksum == digest(record.checksumInput) else { throw ImportRecoveryError.invalidJournal }
    }

    private func validateEntries(in directory: URL) throws {
        let entries = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard Set(entries.map(\.lastPathComponent)).isSubset(of: ["record.json", "payload"]) else {
            throw ImportRecoveryError.invalidJournal
        }
        for entry in entries {
            try validatePath(entry)
            guard try fileManager.attributesOfItem(atPath: entry.path)[.type] as? FileAttributeType == .typeRegular else {
                throw ImportRecoveryError.invalidJournal
            }
        }
    }

    private func removeEmptyRoot(in library: URL) throws {
        let root = journalRoot(in: library)
        if fileManager.fileExists(atPath: root.path), try fileManager.contentsOfDirectory(atPath: root.path).isEmpty {
            try fileManager.removeItem(at: root)
        }
    }

    private func journalRoot(in library: URL) -> URL { library.appendingPathComponent(".book-imports", isDirectory: true) }
    private func transactionDirectory(_ id: UUID, in library: URL) -> URL { journalRoot(in: library).appendingPathComponent(id.uuidString, isDirectory: true) }

    private func validatePath(_ url: URL) throws {
        guard url.isFileURL else { throw ImportRecoveryError.invalidJournal }
        var component = url
        while component.path != "/" {
            guard component.standardizedFileURL.path == component.resolvingSymlinksInPath().standardizedFileURL.path else {
                throw ImportRecoveryError.invalidJournal
            }
            component = component.deletingLastPathComponent()
        }
    }

    private func hashFile(_ url: URL) throws -> String {
        try validatePath(url)
        guard try fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeRegular else {
            throw ImportRecoveryError.unrecognizedContent
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

enum ImportRecoveryError: LocalizedError {
    case invalidJournal
    case unrecognizedContent
    case pendingChange
    case cleanupFailed(operation: any Error, cleanup: any Error)

    var errorDescription: String? {
        switch self {
        case .invalidJournal: "The import recovery record or path is damaged or unrecognized. Artifacts have been preserved."
        case .unrecognizedContent: "An interrupted import contains unrecognized file content. Artifacts have been preserved."
        case .pendingChange: "An import needs recovery before another book can be imported."
        case let .cleanupFailed(operation, cleanup): "Import failed: \(operation.localizedDescription) Cleanup also failed: \(cleanup.localizedDescription)"
        }
    }
}
