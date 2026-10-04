import CryptoKit
import Foundation
import Security
import SwiftData

/// Verification-only executable, signed into the isolated UI app's container.
/// No production target includes this file. Never retrieves a biometric key.
@main
struct ProtectionRecoveryProbe {
    struct Evidence: Codable {
        let bookID: UUID
        let expectedHash: String
        let expectedPrivate: Bool
        let expectedKey: Bool
    }

    @MainActor
    static func main() async {
        do {
            let args = CommandLine.arguments
            guard args.count >= 4, UUID(uuidString: args[2]) != nil else {
                throw Failure.failed("Expected mode, run UUID, and outside-container canary.")
            }
            try assertSandbox(URL(fileURLWithPath: args[3]))
            let support = try required(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
            let library = support.appendingPathComponent("Varq/Library", isDirectory: true)
            let run = support.appendingPathComponent("ProtectionVerification/" + args[2], isDirectory: true)
            try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
            let evidenceURL = run.appendingPathComponent("evidence.json")
            let container = try ModelContainer(for: Schema([
                Item.self, Book.self, ReadingProgress.self, Highlight.self, ReadingNote.self, BookCollection.self
            ]), configurations: [ModelConfiguration(isStoredInMemoryOnly: false)])
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let keyStore = PrivateBookKeyStore()
            let protection = PrivateBookProtectionService(keyStore: keyStore)
            switch args[1] {
            case "hold":
                guard args.count == 5 else { throw Failure.failed("Expected interruption boundary.") }
                try prepare(args[4], library: library, run: run, context: context, keyStore: keyStore)
                print("READY")
                fflush(stdout)
                while true { try await Task.sleep(for: .seconds(1)) }
            case "recover":
                let model = PrivateBookViewModel(protectionService: protection)
                model.recoverInterruptedChanges(using: context, managedLibraryDirectory: library)
                try check(model.isRecoveryComplete, model.errorMessage ?? "Recovery gate stayed closed")
                try verify(evidenceURL, library: library, context: context, protection: protection)
                print("PASS: recovered file, committed flag, Keychain metadata, and journal")
            case "verify":
                try verify(evidenceURL, library: library, context: context, protection: protection)
                print("PASS: UI recovery persisted the expected state")
            case "blocked":
                let model = PrivateBookViewModel(protectionService: protection)
                model.recoverInterruptedChanges(using: context, managedLibraryDirectory: library)
                try check(!model.isRecoveryComplete, "Unknown content incorrectly opened the library")
                let diagnosis = try required(model.errorMessage)
                model.clearError()
                try check(model.errorMessage == diagnosis, "Dismissing error erased recovery diagnosis")
                let evidence = try JSONDecoder().decode(Evidence.self, from: Data(contentsOf: evidenceURL))
                try check(try keyExists(evidence.bookID), "Blocking recovery removed the key")
                try check(try Data(contentsOf: library.appendingPathComponent("book.epub")) == Data("unknown-content-preserve-me".utf8), "Blocking recovery changed unknown content")
                try check(try context.fetch(FetchDescriptor<Book>()).first?.isPrivate == false, "Blocking recovery guessed a database flag")
                print("PASS: unknown content, flag, key, and blocking diagnosis preserved")
            case "repair":
                let evidence = try JSONDecoder().decode(Evidence.self, from: Data(contentsOf: evidenceURL))
                let ciphertext = try Data(contentsOf: run.appendingPathComponent("verified-ciphertext"))
                try check(digest(ciphertext) == evidence.expectedHash, "Repair evidence changed")
                // Restore only this fixture's recorded ciphertext, never user data.
                try ciphertext.write(to: library.appendingPathComponent("book.epub"), options: .atomic)
                print("PASS: restored known fixture ciphertext for UI Retry")
            case "reset":
                if FileManager.default.fileExists(atPath: evidenceURL.path) {
                    let evidence = try JSONDecoder().decode(Evidence.self, from: Data(contentsOf: evidenceURL))
                    try keyStore.removeKey(for: evidence.bookID)
                }
                for book in try context.fetch(FetchDescriptor<Book>()) {
                    // This identifier/container is reserved exclusively for this probe.
                    try keyStore.removeKey(for: book.id)
                    context.delete(book)
                }
                try context.save()
                if FileManager.default.fileExists(atPath: library.path) { try FileManager.default.removeItem(at: library) }
                try FileManager.default.removeItem(at: run)
            default: throw Failure.failed("Unknown mode")
            }
        } catch {
            FileHandle.standardError.write(Data("Verification failed: \(error)\n".utf8))
            exit(1)
        }
    }

    @MainActor
    private static func prepare(_ boundary: String, library: URL, run: URL, context: ModelContext, keyStore: PrivateBookKeyStore) throws {
        let boundaries = ["protect-before-key", "protect-after-key", "protect-after-replace", "protect-after-save", "unprotect-before-replace", "unprotect-staged", "unprotect-after-replace", "unprotect-after-save", "unprotect-after-key-delete", "unknown-content"]
        try check(boundaries.contains(boundary), "Unknown interruption boundary")
        try check(try context.fetch(FetchDescriptor<Book>()).isEmpty, "Verification container is not empty; reset it first")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let fixture = try required(Bundle.main.url(forResource: "minimal", withExtension: "epub", subdirectory: "Fixtures"))
        let plaintext = try Data(contentsOf: fixture)
        let file = library.appendingPathComponent("book.epub")
        try plaintext.write(to: file)
        let book = Book(title: "Protection recovery fixture", author: "Varq", libraryRelativePath: "book.epub", contentHash: digest(plaintext), format: .epub)
        context.insert(book)
        try context.save()
        let key = SymmetricKey(size: .bits256)
        let ciphertext = try PrivateBookCryptoService().encrypt(plaintext, using: key)
        let journal = PrivateBookRecoveryJournalService()
        let removingProtection = boundary.hasPrefix("unprotect-")
        if removingProtection {
            try keyStore.store(key, for: book.id)
            try ciphertext.write(to: file, options: .atomic)
            book.isPrivate = true
            try context.save()
        }
        let record = try journal.begin(bookID: book.id, managedFileURL: file, originalIsPrivate: removingProtection,
                                       originalData: removingProtection ? ciphertext : plaintext,
                                       changedData: removingProtection ? plaintext : ciphertext)
        if !removingProtection && boundary != "protect-before-key" { try keyStore.store(key, for: book.id) }
        let replaced = ["protect-after-replace", "protect-after-save", "unprotect-after-replace", "unprotect-after-save", "unprotect-after-key-delete", "unknown-content"].contains(boundary)
        if replaced { try journal.replaceManagedFile(record, in: library, with: removingProtection ? plaintext : ciphertext) }
        if boundary == "unprotect-staged" {
            let staged = library.appendingPathComponent(".private-book-recovery/\(book.id.uuidString)/replacement")
            try plaintext.write(to: staged)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staged.path)
        }
        if ["protect-after-save", "unprotect-after-save", "unprotect-after-key-delete"].contains(boundary) {
            book.isPrivate = !removingProtection
            try context.save()
        }
        if boundary == "unprotect-after-key-delete" { try keyStore.removeKey(for: book.id) }
        let keyShouldExist = boundary != "protect-before-key" && boundary != "unprotect-after-key-delete"
        try check(try keyExists(book.id) == keyShouldExist, "Keychain state incorrect before interruption")
        try check(try !keyExists(UUID()), "Keychain probe treats nonexistent items as present")
        let expectedPrivate = removingProtection ? !replaced : replaced
        let evidence = Evidence(bookID: book.id, expectedHash: digest(expectedPrivate ? ciphertext : plaintext), expectedPrivate: expectedPrivate, expectedKey: expectedPrivate)
        try JSONEncoder().encode(evidence).write(to: run.appendingPathComponent("evidence.json"), options: .atomic)
        if boundary == "unknown-content" {
            try ciphertext.write(to: run.appendingPathComponent("verified-ciphertext"), options: .atomic)
            try Data("unknown-content-preserve-me".utf8).write(to: file, options: .atomic)
        }
    }

    @MainActor
    private static func verify(_ evidenceURL: URL, library: URL, context: ModelContext, protection: PrivateBookProtectionService) throws {
        let evidence = try JSONDecoder().decode(Evidence.self, from: Data(contentsOf: evidenceURL))
        let books = try context.fetch(FetchDescriptor<Book>())
        let book = try required(books.first)
        try check(books.count == 1 && book.id == evidence.bookID, "Unexpected library rows")
        try check(book.isPrivate == evidence.expectedPrivate, "Committed private flag disagrees with file")
        try check(digest(Data(contentsOf: library.appendingPathComponent("book.epub"))) == evidence.expectedHash, "Managed file bytes changed")
        try check(try keyExists(book.id) == evidence.expectedKey, "Unexpected Keychain retention/removal")
        try check(try protection.recoverableChanges(in: library).isEmpty, "Recovery journal remains")
        let root = library.appendingPathComponent(".private-book-recovery")
        if FileManager.default.fileExists(atPath: root.path) {
            try check(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty, "Staging or completed cleanup remains")
        }
    }

    private static func keyExists(_ id: UUID) throws -> Bool {
        // Attributes only: never request secret data or initiate authentication.
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword,
            kSecAttrService: "dev.pratikrai.Varq.private-book-key", kSecAttrAccount: id.uuidString,
            kSecReturnAttributes: true, kSecUseDataProtectionKeychain: true,
            kSecUseAuthenticationUI: kSecUseAuthenticationUIFail]
        var attributes: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &attributes)
        if status == errSecItemNotFound { return false }
        // A matched ACL-protected item may refuse even attribute access without
        // authentication. A missing UUID returns errSecItemNotFound instead.
        try check(status == errSecSuccess || status == errSecInteractionNotAllowed, "Keychain metadata query failed: \(status)")
        return true
    }

    private static func assertSandbox(_ url: URL) throws {
        do { _ = try Data(contentsOf: url) }
        catch {
            let error = error as NSError
            try check(error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError, "Canary failed for a reason other than sandbox denial")
            return
        }
        throw Failure.failed("Outside-container canary readable; probe is not sandboxed")
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func required<T>(_ value: T?) throws -> T { guard let value else { throw Failure.failed("Missing required value") }; return value }
    private static func check(_ condition: Bool, _ message: String) throws { if !condition { throw Failure.failed(message) } }
    enum Failure: Error { case failed(String) }
}
