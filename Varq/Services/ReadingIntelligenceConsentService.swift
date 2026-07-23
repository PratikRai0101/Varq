import Foundation

/// Whether a book's content may be used for an on-device intelligence request.
enum LocalIntelligenceAccess: Equatable {
    case allowed
    case requiresPrivateBookConsent
}

/// Persists a reader's explicit, per-book consent for local intelligence.
@MainActor
protocol LocalIntelligenceConsentStoring {
    func hasConsent(for bookID: UUID) -> Bool
    func grantConsent(for bookID: UUID)
    func revokeConsent(for bookID: UUID)
}

@MainActor
final class UserDefaultsLocalIntelligenceConsentStore: LocalIntelligenceConsentStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasConsent(for bookID: UUID) -> Bool {
        defaults.bool(forKey: key(for: bookID))
    }

    func grantConsent(for bookID: UUID) {
        defaults.set(true, forKey: key(for: bookID))
    }

    func revokeConsent(for bookID: UUID) {
        defaults.removeObject(forKey: key(for: bookID))
    }

    private func key(for bookID: UUID) -> String {
        "privateBookLocalIntelligenceConsent.\(bookID.uuidString)"
    }
}

/// Applies Varq's private-book policy before local intelligence can receive book content.
@MainActor
final class ReadingIntelligenceConsentService {
    private let store: any LocalIntelligenceConsentStoring

    convenience init() {
        self.init(store: UserDefaultsLocalIntelligenceConsentStore())
    }

    init(store: any LocalIntelligenceConsentStoring) {
        self.store = store
    }

    func access(for book: Book) -> LocalIntelligenceAccess {
        guard book.isPrivate else {
            return .allowed
        }
        return store.hasConsent(for: book.id) ? .allowed : .requiresPrivateBookConsent
    }

    func grantLocalIntelligenceConsent(for book: Book) {
        guard book.isPrivate else {
            return
        }
        store.grantConsent(for: book.id)
    }

    func revokeLocalIntelligenceConsent(for book: Book) {
        store.revokeConsent(for: book.id)
    }
}
