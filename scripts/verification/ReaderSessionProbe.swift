import CryptoKit
import Foundation
import PDFKit

/// Verification-only executable; never linked into Varq or its shipping targets.
@main
struct ReaderSessionProbe {
    @MainActor
    static func main() async {
        do {
            let arguments = CommandLine.arguments
            guard arguments.count >= 4, UUID(uuidString: arguments[2]) != nil else {
                throw ProbeError.failed("Expected mode, run UUID, and outside-container canary path.")
            }
            try assertSandboxDeniesCanary(at: URL(fileURLWithPath: arguments[3]))
            let runDirectory = try managedRunDirectory(arguments[2])
            let storage = ReaderSessionStorageService.shared
            switch arguments[1] {
            case "hold":
                guard arguments.count == 5, ["abandoned", "active"].contains(arguments[4]) else {
                    throw ProbeError.failed("Expected a known reader role.")
                }
                try await prepareReader(role: arguments[4], in: runDirectory, storage: storage)
                print("READY")
                fflush(stdout)
                // The production singleton retains its process lease until SIGKILL.
                while true { try await Task.sleep(nanoseconds: 1_000_000_000) }
            case "verify-live":
                try storage.cleanupStaleSessions()
                try verify(role: "abandoned", in: runDirectory, plaintextExists: true)
                try verify(role: "active", in: runDirectory, plaintextExists: true)
                print("PASS: both live readers retain their plaintext and unchanged ciphertext")
            case "verify-abandoned":
                try storage.cleanupStaleSessions()
                try verify(role: "abandoned", in: runDirectory, plaintextExists: false)
                try verify(role: "active", in: runDirectory, plaintextExists: true)
                print("PASS: forced-quit plaintext removed; live reader and both managed copies preserved")
            case "verify-final":
                try storage.cleanupStaleSessions()
                for role in ["abandoned", "active"] {
                    try verify(role: role, in: runDirectory, plaintextExists: false)
                }
                try FileManager.default.removeItem(at: runDirectory)
                print("PASS: all abandoned EPUB/PDF/CBZ copies and extraction trees removed")
            case "reset":
                try storage.cleanupStaleSessions()
                if FileManager.default.fileExists(atPath: runDirectory.path) {
                    try FileManager.default.removeItem(at: runDirectory)
                }
            default:
                throw ProbeError.failed("Unknown verification mode.")
            }
        } catch {
            FileHandle.standardError.write(Data("Verification failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func assertSandboxDeniesCanary(at url: URL) throws {
        do {
            _ = try Data(contentsOf: url)
        } catch {
            let failure = error as NSError
            guard failure.domain == NSCocoaErrorDomain, failure.code == NSFileReadNoPermissionError else {
                throw ProbeError.failed("Canary failed for a reason other than sandbox read denial: \(failure.localizedDescription)")
            }
            return
        }
        throw ProbeError.failed("The verification process can read outside its container; sandbox proof failed.")
    }

    private static func managedRunDirectory(_ runID: String) throws -> URL {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ProbeError.failed("Application Support is unavailable.")
        }
        return support.appendingPathComponent("ReaderSessionVerification", isDirectory: true)
            .appendingPathComponent(runID, isDirectory: true)
    }

    @MainActor
    private static func prepareReader(role: String, in runDirectory: URL, storage: ReaderSessionStorageService) async throws {
        let managedDirectory = runDirectory.appendingPathComponent(role, isDirectory: true)
        try FileManager.default.createDirectory(at: managedDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let crypto = PrivateBookCryptoService()
        var ciphertext: [FileEvidence] = []
        var plaintext: [FileEvidence] = []
        var directories: [URL] = []
        for format in ["epub", "pdf", "cbz"] {
            guard let fixture = Bundle.main.url(forResource: "minimal", withExtension: format, subdirectory: "Fixtures") else {
                throw ProbeError.failed("Missing bundled \(format) fixture.")
            }
            let original = try Data(contentsOf: fixture)
            let key = SymmetricKey(size: .bits256)
            let managed = managedDirectory.appendingPathComponent("book.\(format)")
            try crypto.encrypt(original, using: key).write(to: managed, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: managed.path)
            ciphertext.append(try evidence(for: managed))
            let directory = try storage.makeDirectory()
            directories.append(directory)
            let decrypted = directory.appendingPathComponent("book.\(format)")
            try crypto.decryptManagedFile(at: managed, to: decrypted, using: key)
            guard try Data(contentsOf: decrypted) == original else {
                throw ProbeError.failed("Decrypted \(format) differs from the fixture.")
            }
            plaintext.append(try evidence(for: decrypted))
            switch format {
            case "epub":
                let extraction = try storage.makeDirectory()
                directories.append(extraction)
                let publication = try await EpubPublicationService().extract(at: decrypted, into: extraction)
                for resource in publication.spine { plaintext.append(try evidence(for: resource.fileURL)) }
            case "cbz":
                let extraction = try storage.makeDirectory()
                directories.append(extraction)
                let publication = try await CbzPublicationService().extract(at: decrypted, into: extraction)
                for page in publication.pages { plaintext.append(try evidence(for: page.fileURL)) }
            default:
                guard let document = PDFDocument(url: decrypted), document.pageCount > 0 else {
                    throw ProbeError.failed("The decrypted PDF cannot be opened by PDFKit.")
                }
            }
        }
        let snapshot = Snapshot(ciphertext: ciphertext, plaintext: plaintext, directories: directories)
        try JSONEncoder().encode(snapshot).write(to: managedDirectory.appendingPathComponent("state.json"), options: .atomic)
    }

    private static func verify(role: String, in runDirectory: URL, plaintextExists: Bool) throws {
        let stateURL = runDirectory.appendingPathComponent(role).appendingPathComponent("state.json")
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: stateURL))
        for file in snapshot.ciphertext {
            guard try evidence(for: file.url) == file else {
                throw ProbeError.failed("Managed ciphertext changed for \(role).")
            }
        }
        for directory in snapshot.directories {
            guard FileManager.default.fileExists(atPath: directory.path) == plaintextExists else {
                throw ProbeError.failed("Unexpected extraction/decryption directory state for \(role).")
            }
        }
        for file in snapshot.plaintext {
            if plaintextExists {
                guard try evidence(for: file.url) == file else {
                    throw ProbeError.failed("A live reader's plaintext changed for \(role).")
                }
            } else if FileManager.default.fileExists(atPath: file.url.path) {
                throw ProbeError.failed("Abandoned plaintext remains for \(role).")
            }
        }
    }

    private static func evidence(for url: URL) throws -> FileEvidence {
        let data = try Data(contentsOf: url)
        return FileEvidence(url: url, hash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }
}

private struct Snapshot: Codable {
    let ciphertext: [FileEvidence]
    let plaintext: [FileEvidence]
    let directories: [URL]
}

private struct FileEvidence: Codable, Equatable {
    let url: URL
    let hash: String
}

private enum ProbeError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message): message
        }
    }
}
