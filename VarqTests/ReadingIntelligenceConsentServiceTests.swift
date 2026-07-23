import Foundation
import Testing
@testable import Varq

@MainActor
struct ReadingIntelligenceConsentServiceTests {
    @Test func allowsLocalIntelligenceForPublicBooksWithoutConsent() {
        let store = InMemoryLocalIntelligenceConsentStore()
        let service = ReadingIntelligenceConsentService(store: store)
        let book = makeBook(isPrivate: false)

        #expect(service.access(for: book) == .allowed)
    }

    @Test func requiresConsentForPrivateBooks() {
        let store = InMemoryLocalIntelligenceConsentStore()
        let service = ReadingIntelligenceConsentService(store: store)
        let book = makeBook(isPrivate: true)

        #expect(service.access(for: book) == .requiresPrivateBookConsent)
    }

    @Test func grantsAndRevokesConsentForOnlyTheSelectedPrivateBook() {
        let store = InMemoryLocalIntelligenceConsentStore()
        let service = ReadingIntelligenceConsentService(store: store)
        let approvedBook = makeBook(isPrivate: true)
        let otherBook = makeBook(isPrivate: true)

        service.grantLocalIntelligenceConsent(for: approvedBook)

        #expect(service.access(for: approvedBook) == .allowed)
        #expect(service.access(for: otherBook) == .requiresPrivateBookConsent)

        service.revokeLocalIntelligenceConsent(for: approvedBook)

        #expect(service.access(for: approvedBook) == .requiresPrivateBookConsent)
    }

    private func makeBook(isPrivate: Bool) -> Book {
        Book(
            title: "Test Book",
            author: "Test Author",
            libraryRelativePath: "test.epub",
            contentHash: UUID().uuidString,
            format: .epub,
            isPrivate: isPrivate
        )
    }
}

@MainActor
private final class InMemoryLocalIntelligenceConsentStore: LocalIntelligenceConsentStoring {
    private var approvedBookIDs: Set<UUID> = []

    func hasConsent(for bookID: UUID) -> Bool {
        approvedBookIDs.contains(bookID)
    }

    func grantConsent(for bookID: UUID) {
        approvedBookIDs.insert(bookID)
    }

    func revokeConsent(for bookID: UUID) {
        approvedBookIDs.remove(bookID)
    }
}
