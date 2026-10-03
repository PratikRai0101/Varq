import CryptoKit
import Foundation

struct BookDeletionRecord: Codable, Equatable, Sendable {
    let version: Int
    let bookID: UUID
    let fileName: String
    let isPrivate: Bool
    let contentHash: String
    let checksum: String

    fileprivate var checksumInput: Data {
        Data("\(version)\n\(bookID.uuidString)\n\(fileName)\n\(isPrivate)\n\(contentHash)".utf8)
    }
}

@MainActor
final class BookDeletionService {
    private let fileManager: FileManager
    private let keyStore: any PrivateBookKeyStoring

    init(fileManager: FileManager = .default, keyStore: (any PrivateBookKeyStoring)? = nil) {
        self.fileManager = fileManager
        self.keyStore = keyStore ?? PrivateBookKeyStore()
    }

    func stage(bookID: UUID, fileName: String, isPrivate: Bool, in library: URL) throws -> BookDeletionRecord {
        try validateFileName(fileName)
        let root = journalRoot(in: library)
        try validatePath(root)
        if fileManager.fileExists(atPath: root.path), !(try fileManager.contentsOfDirectory(atPath: root.path)).isEmpty {
            throw BookDeletionError.pendingChange
        }
        let protectionRecord = library.appendingPathComponent(".private-book-recovery").appendingPathComponent(bookID.uuidString)
        try validatePath(protectionRecord)
        guard !fileManager.fileExists(atPath: protectionRecord.path) else { throw BookDeletionError.pendingChange }
        let source = library.appendingPathComponent(fileName)
        try validatePath(source)
        guard try fileManager.attributesOfItem(atPath: source.path)[.type] as? FileAttributeType == .typeRegular else {
            throw BookDeletionError.unsafePath
        }
        let hash = try contentHash(at: source)
        let unsigned = BookDeletionRecord(version: 1, bookID: bookID, fileName: fileName, isPrivate: isPrivate, contentHash: hash, checksum: "")
        let record = BookDeletionRecord(version: 1, bookID: bookID, fileName: fileName, isPrivate: isPrivate, contentHash: hash, checksum: digest(unsigned.checksumInput))
        let directory = transactionDirectory(record, in: library)
        try validatePath(directory)
        guard !fileManager.fileExists(atPath: directory.path) else { throw BookDeletionError.pendingChange }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: journalRoot(in: library).path)
        try JSONEncoder().encode(record).write(to: directory.appendingPathComponent("record.json"), options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: directory.appendingPathComponent("record.json").path)
        do {
            try fileManager.moveItem(at: source, to: directory.appendingPathComponent("payload"))
        } catch {
            let stagingError = error
            do { try restore(record, in: library) }
            catch { throw BookDeletionError.rollbackFailed(operation: stagingError, rollback: error) }
            throw stagingError
        }
        return record
    }

    func recover(in library: URL, survivingBooks: [Book]) throws {
        let records = try pendingRecords(in: library, preservingBookIDs: Set(survivingBooks.map(\.id)))
        for record in records {
            let matching = survivingBooks.filter { $0.id == record.bookID }
            if let book = matching.first {
                guard matching.count == 1, book.libraryRelativePath == record.fileName,
                      book.isPrivate == record.isPrivate,
                      !survivingBooks.contains(where: { $0.id != book.id && $0.libraryRelativePath == record.fileName }) else {
                    throw BookDeletionError.invalidJournal
                }
                try restore(record, in: library)
            } else {
                guard !survivingBooks.contains(where: { $0.libraryRelativePath == record.fileName }) else {
                    throw BookDeletionError.invalidJournal
                }
                try complete(record, in: library)
            }
        }
    }

    /// Call only after a committed database deletion (or recovery verified row absence).
    func complete(_ record: BookDeletionRecord, in library: URL) throws {
        try validate(record)
        let source = library.appendingPathComponent(record.fileName)
        let payload = transactionDirectory(record, in: library).appendingPathComponent("payload")
        try validatePath(source)
        try validatePath(payload)
        guard !fileManager.fileExists(atPath: source.path),
              try contentHash(at: payload) == record.contentHash else {
            throw BookDeletionError.unrecognizedContent
        }
        if record.isPrivate { try keyStore.removeKey(for: record.bookID) }
        try finish(record, in: library)
    }

    func restore(_ record: BookDeletionRecord, in library: URL) throws {
        try validate(record)
        let source = library.appendingPathComponent(record.fileName)
        let payload = transactionDirectory(record, in: library).appendingPathComponent("payload")
        try validatePath(source)
        try validatePath(payload)
        let sourceExists = fileManager.fileExists(atPath: source.path)
        let payloadExists = fileManager.fileExists(atPath: payload.path)
        guard sourceExists != payloadExists else { throw BookDeletionError.unrecognizedContent }
        if payloadExists {
            guard try contentHash(at: payload) == record.contentHash else { throw BookDeletionError.unrecognizedContent }
            try fileManager.moveItem(at: payload, to: source)
        } else {
            guard try contentHash(at: source) == record.contentHash else { throw BookDeletionError.unrecognizedContent }
        }
        try finish(record, in: library)
    }

    func pendingRecords(in library: URL, preservingBookIDs: Set<UUID> = []) throws -> [BookDeletionRecord] {
        let root = journalRoot(in: library)
        try validatePath(root)
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        var records: [BookDeletionRecord] = []
        for directory in try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) {
            try validatePath(directory)
            guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw BookDeletionError.invalidJournal
            }
            if directory.lastPathComponent.hasPrefix(".completed-"),
               let completedID = UUID(uuidString: String(directory.lastPathComponent.dropFirst(".completed-".count))) {
                if preservingBookIDs.contains(completedID), fileManager.fileExists(atPath: directory.appendingPathComponent("payload").path) {
                    throw BookDeletionError.invalidJournal
                }
                try fileManager.removeItem(at: directory)
                continue
            }
            guard let bookID = UUID(uuidString: directory.lastPathComponent) else { throw BookDeletionError.invalidJournal }
            if try fileManager.contentsOfDirectory(atPath: directory.path).isEmpty {
                try fileManager.removeItem(at: directory)
                continue
            }
            let recordURL = directory.appendingPathComponent("record.json")
            try validatePath(recordURL)
            let record = try JSONDecoder().decode(BookDeletionRecord.self, from: Data(contentsOf: recordURL))
            try validate(record)
            guard record.bookID == bookID else { throw BookDeletionError.invalidJournal }
            let entries = Set(try fileManager.contentsOfDirectory(atPath: directory.path))
            guard entries.isSubset(of: ["record.json", "payload"]) else { throw BookDeletionError.invalidJournal }
            records.append(record)
        }
        return records
    }

    private func finish(_ record: BookDeletionRecord, in library: URL) throws {
        let directory = transactionDirectory(record, in: library)
        let completed = journalRoot(in: library).appendingPathComponent(".completed-" + record.bookID.uuidString)
        try validatePath(directory)
        try validatePath(completed)
        let entries = Set(try fileManager.contentsOfDirectory(atPath: directory.path))
        guard entries.isSubset(of: ["record.json", "payload"]) else { throw BookDeletionError.invalidJournal }
        try fileManager.moveItem(at: directory, to: completed)
        try fileManager.removeItem(at: completed)
    }

    private func journalRoot(in library: URL) -> URL {
        library.appendingPathComponent(".book-deletions", isDirectory: true)
    }

    private func transactionDirectory(_ record: BookDeletionRecord, in library: URL) -> URL {
        journalRoot(in: library).appendingPathComponent(record.bookID.uuidString, isDirectory: true)
    }

    private func validate(_ record: BookDeletionRecord) throws {
        try validateFileName(record.fileName)
        guard record.version == 1, record.contentHash.count == 64,
              record.checksum == digest(record.checksumInput) else { throw BookDeletionError.invalidJournal }
    }

    private func validateFileName(_ fileName: String) throws {
        guard !fileName.isEmpty, !fileName.hasPrefix("."), !fileName.contains("\n"),
              URL(fileURLWithPath: fileName).lastPathComponent == fileName,
              !fileName.contains("\\") else { throw BookDeletionError.unsafePath }
    }

    private func validatePath(_ url: URL) throws {
        guard url.isFileURL else { throw BookDeletionError.unsafePath }
        var component = url
        while component.path != "/" {
            guard component.standardizedFileURL.path == component.resolvingSymlinksInPath().standardizedFileURL.path else {
                throw BookDeletionError.unsafePath
            }
            component = component.deletingLastPathComponent()
        }
    }

    private func contentHash(at url: URL) throws -> String {
        try validatePath(url)
        return digest(try Data(contentsOf: url))
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum BookDeletionError: LocalizedError {
    case unsafePath
    case invalidJournal
    case pendingChange
    case unrecognizedContent
    case rollbackFailed(operation: any Error, rollback: any Error)
    case cleanupFailed(any Error)

    var errorDescription: String? {
        switch self {
        case .unsafePath: "The book deletion contains an unsafe path. No unverified file will be removed."
        case .invalidJournal: "The book deletion journal is damaged or unrecognized. Recovery artifacts have been preserved."
        case .pendingChange: "A deletion or protection change is pending. Finish library recovery before trying again."
        case .unrecognizedContent: "The book deletion's files do not match its recorded state. Recovery artifacts have been preserved."
        case let .cleanupFailed(error):
            "The book was removed from the database, but file/key cleanup is incomplete: \(error.localizedDescription) Recovery must finish before using the library."
        case let .rollbackFailed(operation, rollback):
            "Deletion failed: \(operation.localizedDescription) File restoration also failed: \(rollback.localizedDescription)"
        }
    }
}
