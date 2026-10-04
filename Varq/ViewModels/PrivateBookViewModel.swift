import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class PrivateBookViewModel {
    private let protectionService: any PrivateBookProtecting
    private let saveChanges: (ModelContext) throws -> Void
    private let readerSessionStorage: ReaderSessionStorageService
    private let deletionService: BookDeletionService
    private let importJournal: ImportRecoveryJournalService
    private var isImporting: () -> Bool = { false }
    private(set) var errorMessage: String?
    private(set) var isRecoveryComplete = false

    init(
        protectionService: (any PrivateBookProtecting)? = nil,
        readerSessionStorage: ReaderSessionStorageService? = nil,
        deletionService: BookDeletionService? = nil,
        importJournal: ImportRecoveryJournalService = ImportRecoveryJournalService(),
        saveChanges: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.protectionService = protectionService ?? PrivateBookProtectionService()
        self.saveChanges = saveChanges
        self.readerSessionStorage = readerSessionStorage ?? .shared
        self.deletionService = deletionService ?? BookDeletionService()
        self.importJournal = importJournal
    }

    func setImportActivityCheck(_ check: @escaping () -> Bool) {
        isImporting = check
    }

    func recoverInterruptedChanges(using modelContext: ModelContext, managedLibraryDirectory: URL) {
        // A new window or Retry must not reconcile an in-flight import as a crash.
        guard !isImporting() else { return }
        isRecoveryComplete = false
        do {
            try readerSessionStorage.cleanupStaleSessions()
            // Reconcile against committed rows, never stale objects from a failed
            // deletion or unrelated unsaved edits in a window's context.
            let persistedContext = ModelContext(modelContext.container)
            persistedContext.autosaveEnabled = false
            let committedBooks = try persistedContext.fetch(FetchDescriptor<Book>())
            try importJournal.recover(in: managedLibraryDirectory, committedBooks: committedBooks.map {
                CommittedImportBook(id: $0.id, fileName: $0.libraryRelativePath, contentHash: $0.contentHash, isPrivate: $0.isPrivate)
            })
            try deletionService.recover(in: managedLibraryDirectory, survivingBooks: committedBooks)
            let states = try protectionService.recoverableChanges(in: managedLibraryDirectory)
            let books = try modelContext.fetch(FetchDescriptor<Book>())
            for state in states {
                guard let book = books.first(where: { $0.id == state.record.bookID }),
                      book.libraryRelativePath == state.record.fileName else {
                    throw PrivateBookRecoveryError.missingBook
                }
                let previousFlag = book.isPrivate
                book.isPrivate = state.isPrivate
                do {
                    try saveChanges(modelContext)
                } catch {
                    book.isPrivate = previousFlag
                    throw error
                }
                try protectionService.completeRecovery(state, in: managedLibraryDirectory)
            }
            errorMessage = nil
            isRecoveryComplete = true
        } catch {
            errorMessage = "Varq could not finish library recovery. " + error.localizedDescription
        }
    }

    func markPrivate(book: Book, managedFileURL: URL, using modelContext: ModelContext) {
        guard !book.isPrivate else { return }
        do {
            let handle = try protectionService.protect(bookID: book.id, managedFileURL: managedFileURL)
            book.isPrivate = true
            do {
                try saveChanges(modelContext)
                errorMessage = nil
            } catch {
                let persistenceError = error
                do {
                    try protectionService.rollbackProtection(handle, bookID: book.id, managedFileURL: managedFileURL)
                    book.isPrivate = false
                } catch {
                    // Cleanup errors occur after restoring the public file.
                    // Other failures may have left the file encrypted.
                    switch error {
                    case PrivateBookProtectionError.keyCleanupFailed,
                         PrivateBookProtectionError.rollbackCleanupFailed:
                        book.isPrivate = false
                    default:
                        break
                    }
                    throw PrivateBookProtectionError.rollbackFailed(
                        operationError: persistenceError,
                        rollbackError: error
                    )
                }
                throw persistenceError
            }
            // Journal cleanup is outside the save/rollback block: a cleanup
            // failure must never roll back an already committed private flag.
            try protectionService.completeProtection(bookID: book.id, managedFileURL: managedFileURL)
        } catch {
            isRecoveryComplete = false
            errorMessage = error.localizedDescription
        }
    }

    func unmarkPrivate(book: Book, managedFileURL: URL, using modelContext: ModelContext) {
        guard book.isPrivate else { return }
        do {
            try protectionService.unprotect(bookID: book.id, managedFileURL: managedFileURL) {
                book.isPrivate = false
                do {
                    try saveChanges(modelContext)
                } catch {
                    book.isPrivate = true
                    throw error
                }
            }
            errorMessage = nil
        } catch {
            isRecoveryComplete = false
            errorMessage = error.localizedDescription
        }
    }

    func requireImportRecovery(_ message: String) {
        isRecoveryComplete = false
        errorMessage = message
    }

    func requireDeletionRecovery(_ message: String) {
        isRecoveryComplete = false
        errorMessage = message
    }

    func clearError() {
        // Dismissing an alert must not erase the blocking recovery diagnosis.
        guard isRecoveryComplete else { return }
        errorMessage = nil
    }
}
