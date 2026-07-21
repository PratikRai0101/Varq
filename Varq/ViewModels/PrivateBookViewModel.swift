import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class PrivateBookViewModel {
    private let protectionService: any PrivateBookProtecting
    private(set) var errorMessage: String?

    init(protectionService: any PrivateBookProtecting = PrivateBookProtectionService()) {
        self.protectionService = protectionService
    }

    func markPrivate(book: Book, managedFileURL: URL, using modelContext: ModelContext) {
        guard !book.isPrivate else { return }
        do {
            let handle = try protectionService.protect(bookID: book.id, managedFileURL: managedFileURL)
            book.isPrivate = true
            do {
                try modelContext.save()
                errorMessage = nil
            } catch {
                book.isPrivate = false
                try? protectionService.rollbackProtection(handle, bookID: book.id, managedFileURL: managedFileURL)
                throw error
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
