import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class PrivateBookViewModel {
    private let protectionService: any PrivateBookProtecting
    private let saveChanges: (ModelContext) throws -> Void
    private(set) var errorMessage: String?

    init(
        protectionService: (any PrivateBookProtecting)? = nil,
        saveChanges: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.protectionService = protectionService ?? PrivateBookProtectionService()
        self.saveChanges = saveChanges
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
                    // A cleanup failure means decryption succeeded. Otherwise keep the
                    // private flag rather than presenting an encrypted file as public.
                    if case PrivateBookProtectionError.keyCleanupFailed = error {
                        book.isPrivate = false
                    }
                    throw PrivateBookProtectionError.rollbackFailed(
                        operationError: persistenceError,
                        rollbackError: error
                    )
                }
                throw persistenceError
            }
        } catch {
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
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
