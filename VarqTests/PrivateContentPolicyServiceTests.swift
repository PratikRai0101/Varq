import Foundation
import Testing
@testable import Varq

@MainActor
struct PrivateContentPolicyServiceTests {
    @Test func excludesPrivateBooksFromSearchIndexes() {
        let service = makeService()

        #expect(service.access(for: book(isPrivate: true), to: .searchIndex) == .excludedForPrivateBook)
        #expect(service.access(for: book(isPrivate: false), to: .searchIndex) == .allowed)
    }

    @Test func requiresConfirmationForEveryPrivateBookExport() {
        let service = makeService()

        #expect(service.access(for: book(isPrivate: true), to: .export) == .requiresPrivateBookExportConfirmation)
        #expect(service.access(for: book(isPrivate: false), to: .export) == .allowed)
    }

    @Test func requiresGlobalAndPerBookConsentForPrivateCloudCompute() {
        let cloudStore = InMemoryPrivateCloudComputeConsentStore()
        let service = makeService(cloudStore: cloudStore)
        let privateBook = book(isPrivate: true)
        let publicBook = book(isPrivate: false)

        #expect(service.access(for: publicBook, to: .privateCloudCompute) == .requiresPrivateCloudComputeConsent)
        #expect(service.access(for: privateBook, to: .privateCloudCompute) == .requiresPrivateCloudComputeConsent)

        service.grantPrivateCloudComputeConsent()
        #expect(service.access(for: publicBook, to: .privateCloudCompute) == .allowed)
        #expect(service.access(for: privateBook, to: .privateCloudCompute) == .requiresPrivateBookPrivateCloudComputeConsent)

        service.grantPrivateBookPrivateCloudComputeConsent(for: privateBook)
        #expect(service.access(for: privateBook, to: .privateCloudCompute) == .allowed)
    }

    @Test func preservesPerBookConsentForLocalIntelligence() {
        let localStore = InMemoryLocalIntelligenceConsentStore()
        let service = makeService(localStore: localStore)
        let privateBook = book(isPrivate: true)

        #expect(service.access(for: privateBook, to: .localIntelligence) == .requiresPrivateBookLocalIntelligenceConsent)
        service.grantLocalIntelligenceConsent(for: privateBook)
        #expect(service.access(for: privateBook, to: .localIntelligence) == .allowed)
    }

    private func makeService(
        localStore: InMemoryLocalIntelligenceConsentStore? = nil,
        cloudStore: InMemoryPrivateCloudComputeConsentStore? = nil
    ) -> PrivateContentPolicyService {
        PrivateContentPolicyService(
            localIntelligenceConsentService: ReadingIntelligenceConsentService(
                store: localStore ?? InMemoryLocalIntelligenceConsentStore()
            ),
            privateCloudComputeConsentStore: cloudStore ?? InMemoryPrivateCloudComputeConsentStore()
        )
    }

    private func book(isPrivate: Bool) -> Book {
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
    private var bookIDs: Set<UUID> = []

    func hasConsent(for bookID: UUID) -> Bool { bookIDs.contains(bookID) }
    func grantConsent(for bookID: UUID) { bookIDs.insert(bookID) }
    func revokeConsent(for bookID: UUID) { bookIDs.remove(bookID) }
}

@MainActor
private final class InMemoryPrivateCloudComputeConsentStore: PrivateCloudComputeConsentStoring {
    private var hasGlobalConsent = false
    private var privateBookIDs: Set<UUID> = []

    func hasPrivateCloudComputeConsent() -> Bool { hasGlobalConsent }
    func grantPrivateCloudComputeConsent() { hasGlobalConsent = true }
    func revokePrivateCloudComputeConsent() { hasGlobalConsent = false }
    func hasPrivateBookPrivateCloudComputeConsent(for bookID: UUID) -> Bool { privateBookIDs.contains(bookID) }
    func grantPrivateBookPrivateCloudComputeConsent(for bookID: UUID) { privateBookIDs.insert(bookID) }
    func revokePrivateBookPrivateCloudComputeConsent(for bookID: UUID) { privateBookIDs.remove(bookID) }
}
