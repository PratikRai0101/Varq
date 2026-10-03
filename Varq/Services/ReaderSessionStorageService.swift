import Darwin
import Foundation

enum ReaderSessionStorageError: LocalizedError, Equatable {
    case unsafePath
    case unrecognizedSession
    case busy
    case posixFailure(Int32)

    var errorDescription: String? {
        switch self {
        case .unsafePath:
            "Reader-session storage contains an unsafe path. Varq will not follow it."
        case .unrecognizedSession:
            "Reader-session storage contains an unrecognized entry. Varq has preserved it rather than guessing whether it is safe to delete."
        case .busy:
            "Another Varq instance is preparing reader storage. Try again shortly."
        case let .posixFailure(code):
            "Varq could not prepare or clean reader-session storage: " +
                NSError(domain: NSPOSIXErrorDomain, code: Int(code)).localizedDescription
        }
    }
}

/// All decrypted copies and renderer extraction directories share this storage.
/// A kernel-held lease protects each owner's files until its process terminates.
@MainActor
final class ReaderSessionStorageService {
    static let shared = ReaderSessionStorageService()

    private let rootDirectory: URL
    private let fileManager: FileManager
    private var ownerDirectory: URL?
    private var ownerDescriptor: Int32?
    private var allocatedDirectories: Set<URL> = []
    private var pendingRemovals: Set<URL> = []
    private var releasedDirectories: Set<URL> = []

    init(rootDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory ?? fileManager.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("Varq", isDirectory: true)
            .appendingPathComponent("ReaderSessions", isDirectory: true)
        self.fileManager = fileManager
    }

    deinit {
        if let ownerDescriptor { _ = Darwin.close(ownerDescriptor) }
    }

    func makeDirectory() throws -> URL {
        try withCoordinatorLock { root in
            try removeStaleOwners(in: root)
            try retryPendingRemovals()
            if ownerDirectory == nil {
                let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                let descriptor = try openLock(at: directory.appendingPathComponent("lease.lock"), create: true)
                guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                    let code = errno
                    _ = Darwin.close(descriptor)
                    throw ReaderSessionStorageError.posixFailure(code)
                }
                ownerDirectory = directory
                ownerDescriptor = descriptor
            }
            guard let ownerDirectory else { throw ReaderSessionStorageError.unrecognizedSession }
            let directory = ownerDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try validatePath(directory)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            allocatedDirectories.insert(directory)
            return directory
        }
    }

    func cleanupStaleSessions() throws {
        try withCoordinatorLock { root in
            try removeStaleOwners(in: root)
            try retryPendingRemovals()
        }
    }

    /// Only the creator may release a cache directory. Failed deletions stay
    /// tracked and are retried before allocating any more reader plaintext.
    func removeDirectory(_ directory: URL) throws {
        guard allocatedDirectories.contains(directory) || releasedDirectories.contains(directory) else {
            throw ReaderSessionStorageError.unsafePath
        }
        pendingRemovals.insert(directory)
        try removeAllocatedDirectory(directory)
    }

    private func retryPendingRemovals() throws {
        for directory in pendingRemovals.sorted(by: { $0.path < $1.path }) {
            try removeAllocatedDirectory(directory)
        }
    }

    private func removeAllocatedDirectory(_ directory: URL) throws {
        try validatePath(directory)
        do {
            try fileManager.removeItem(at: directory)
        } catch {
            let error = error as NSError
            guard error.domain == NSCocoaErrorDomain,
                  error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError else {
                throw error
            }
        }
        allocatedDirectories.remove(directory)
        pendingRemovals.remove(directory)
        releasedDirectories.insert(directory)
    }

    private func withCoordinatorLock<T>(_ operation: (URL) throws -> T) throws -> T {
        // Reject symlinks in the configured owned path before canonicalizing its
        // parent. Default storage starts from the canonical sandbox temp URL.
        try validatePath(rootDirectory)
        let root = rootDirectory.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(rootDirectory.lastPathComponent, isDirectory: true)
        try validatePath(root)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let descriptor = try openLock(at: root.appendingPathComponent("coordinator.lock"), create: true)
        defer { _ = Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            if code == EWOULDBLOCK { throw ReaderSessionStorageError.busy }
            throw ReaderSessionStorageError.posixFailure(code)
        }
        return try operation(root)
    }

    private func removeStaleOwners(in root: URL) throws {
        for directory in try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) {
            if directory.lastPathComponent == "coordinator.lock" { continue }
            try validatePath(directory)
            guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw ReaderSessionStorageError.unrecognizedSession
            }
            let name = directory.lastPathComponent
            if name.hasPrefix(".discarded-"), UUID(uuidString: String(name.dropFirst(".discarded-".count))) != nil {
                // A previous cleanup proved this owner inactive before atomically
                // renaming it. Finish even if lease.lock was already deleted.
                try fileManager.removeItem(at: directory)
                continue
            }
            guard UUID(uuidString: name) != nil else { throw ReaderSessionStorageError.unrecognizedSession }
            let contents = try fileManager.contentsOfDirectory(atPath: directory.path)
            if contents.isEmpty {
                // Creation is serialized by coordinator.lock, and no book data
                // is written before the owner lease has been acquired.
                try fileManager.removeItem(at: directory)
                continue
            }
            let leaseURL = directory.appendingPathComponent("lease.lock")
            let descriptor = try openLock(at: leaseURL, create: false)
            defer { _ = Darwin.close(descriptor) }
            if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
                let code = errno
                if code == EWOULDBLOCK { continue } // A live owner, possibly another process.
                throw ReaderSessionStorageError.posixFailure(code)
            }
            let discarded = root.appendingPathComponent(".discarded-" + name, isDirectory: true)
            try validatePath(discarded)
            try fileManager.moveItem(at: directory, to: discarded)
            try fileManager.removeItem(at: discarded)
        }
    }

    private func openLock(at url: URL, create: Bool) throws -> Int32 {
        try validatePath(url)
        let flags = O_RDWR | O_NOFOLLOW | O_CLOEXEC | (create ? O_CREAT : 0)
        let descriptor = url.path.withCString { Darwin.open($0, flags, mode_t(0o600)) }
        guard descriptor >= 0 else { throw ReaderSessionStorageError.posixFailure(errno) }
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0 else {
            let code = errno
            _ = Darwin.close(descriptor)
            throw ReaderSessionStorageError.posixFailure(code)
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else {
            _ = Darwin.close(descriptor)
            throw ReaderSessionStorageError.unsafePath
        }
        return descriptor
    }

    private func validatePath(_ url: URL) throws {
        guard url.isFileURL else { throw ReaderSessionStorageError.unsafePath }
        // Foundation may leave a missing leaf unresolved; inspect each ancestor
        // too, so a symlink above not-yet-created directories cannot redirect I/O.
        var component = url
        while component.path != "/" {
            guard component.standardizedFileURL.path == component.resolvingSymlinksInPath().standardizedFileURL.path else {
                throw ReaderSessionStorageError.unsafePath
            }
            component = component.deletingLastPathComponent()
        }
    }
}
