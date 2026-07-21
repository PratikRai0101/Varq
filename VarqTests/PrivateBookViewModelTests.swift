import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import Varq

@MainActor
struct PrivateBookViewModelTests {
    @Test func marksTheBookPrivateAfterProtectionSucceeds() throws {
        let container = try ModelContainer(for: Book.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let book = Book(title: "Private", author: "Varq", libraryRelativePath: "book.epub", contentHash: "hash", format: .epub)
        context.insert(book)
        let protector = FakePrivateBookProtector()
        let viewModel = PrivateBookViewModel(protectionService: protector)

        viewModel.markPrivate(book: book, managedFileURL: URL(fileURLWithPath: "/tmp/book.epub"), using: context)

        #expect(book.isPrivate)
        #expect(protector.protectedBookID == book.id)
    }
}

private final class FakePrivateBookProtector: PrivateBookProtecting {
    private(set) var protectedBookID: UUID?
    func protect(bookID: UUID, managedFileURL: URL) throws -> PrivateBookProtectionHandle {
        protectedBookID = bookID
        return PrivateBookProtectionHandle(key: SymmetricKey(size: .bits256))
    }
    func rollbackProtection(_ handle: PrivateBookProtectionHandle, bookID: UUID, managedFileURL: URL) throws { }
    func unprotect(bookID: UUID, managedFileURL: URL) throws { }
}
