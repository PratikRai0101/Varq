import Foundation

/// Content destinations with privacy requirements distinct from local book storage.
enum PrivateContentDestination: Sendable {
    case localIntelligence
    case searchIndex
    case privateCloudCompute
    case export
}

/// The action a caller must take before a destination may receive a book's content.
enum PrivateContentAccess: Equatable, Sendable {
    case allowed
    case excludedForPrivateBook
    case requiresPrivateBookLocalIntelligenceConsent
    case requiresPrivateCloudComputeConsent
    case requiresPrivateBookPrivateCloudComputeConsent
    case requiresPrivateBookExportConfirmation
}

@MainActor
protocol PrivateCloudComputeConsentStoring {
    func hasPrivateCloudComputeConsent() -> Bool
    func grantPrivateCloudComputeConsent()
    func revokePrivateCloudComputeConsent()
    func hasPrivateBookPrivateCloudComputeConsent(for bookID: UUID) -> Bool
    func grantPrivateBookPrivateCloudComputeConsent(for bookID: UUID)
    func revokePrivateBookPrivateCloudComputeConsent(for bookID: UUID)
}

@MainActor
final class UserDefaultsPrivateCloudComputeConsentStore: PrivateCloudComputeConsentStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasPrivateCloudComputeConsent() -> Bool {
        defaults.bool(forKey: "privateCloudComputeConsent")
    }

    func grantPrivateCloudComputeConsent() {
        defaults.set(true, forKey: "privateCloudComputeConsent")
    }

    func revokePrivateCloudComputeConsent() {
        defaults.removeObject(forKey: "privateCloudComputeConsent")
    }

    func hasPrivateBookPrivateCloudComputeConsent(for bookID: UUID) -> Bool {
        defaults.bool(forKey: privateBookKey(for: bookID))
    }

    func grantPrivateBookPrivateCloudComputeConsent(for bookID: UUID) {
        defaults.set(true, forKey: privateBookKey(for: bookID))
    }

    func revokePrivateBookPrivateCloudComputeConsent(for bookID: UUID) {
        defaults.removeObject(forKey: privateBookKey(for: bookID))
    }

    private func privateBookKey(for bookID: UUID) -> String {
        "privateBookPrivateCloudComputeConsent.\(bookID.uuidString)"
    }
}

/// Applies ADR 0009 consistently before content is sent to a destination outside
/// the private shelf's encrypted storage.
@MainActor
final class PrivateContentPolicyService {
    private let localIntelligenceConsentService: ReadingIntelligenceConsentService
    private let privateCloudComputeConsentStore: any PrivateCloudComputeConsentStoring

    convenience init() {
        self.init(
            localIntelligenceConsentService: ReadingIntelligenceConsentService(),
            privateCloudComputeConsentStore: UserDefaultsPrivateCloudComputeConsentStore()
        )
    }

    init(
        localIntelligenceConsentService: ReadingIntelligenceConsentService,
        privateCloudComputeConsentStore: any PrivateCloudComputeConsentStoring
    ) {
        self.localIntelligenceConsentService = localIntelligenceConsentService
        self.privateCloudComputeConsentStore = privateCloudComputeConsentStore
    }

    func access(for book: Book, to destination: PrivateContentDestination) -> PrivateContentAccess {
        switch destination {
        case .localIntelligence:
            switch localIntelligenceConsentService.access(for: book) {
            case .allowed:
                return .allowed
            case .requiresPrivateBookConsent:
                return .requiresPrivateBookLocalIntelligenceConsent
            }
        case .searchIndex:
            return book.isPrivate ? .excludedForPrivateBook : .allowed
        case .export:
            return book.isPrivate ? .requiresPrivateBookExportConfirmation : .allowed
        case .privateCloudCompute:
            guard privateCloudComputeConsentStore.hasPrivateCloudComputeConsent() else {
                return .requiresPrivateCloudComputeConsent
            }
            guard !book.isPrivate || privateCloudComputeConsentStore.hasPrivateBookPrivateCloudComputeConsent(for: book.id) else {
                return .requiresPrivateBookPrivateCloudComputeConsent
            }
            return .allowed
        }
    }

    func grantLocalIntelligenceConsent(for book: Book) {
        localIntelligenceConsentService.grantLocalIntelligenceConsent(for: book)
    }

    func grantPrivateCloudComputeConsent() {
        privateCloudComputeConsentStore.grantPrivateCloudComputeConsent()
    }

    func grantPrivateBookPrivateCloudComputeConsent(for book: Book) {
        guard book.isPrivate else { return }
        privateCloudComputeConsentStore.grantPrivateBookPrivateCloudComputeConsent(for: book.id)
    }
}
