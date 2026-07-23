import Observation

@MainActor
@Observable
final class SettingsViewModel {
    enum Tab: String, CaseIterable, Identifiable {
        case general
        case reading
        case library
        case advanced

        var id: Self { self }

        var title: String {
            switch self {
            case .general: "General"
            case .reading: "Reading"
            case .library: "Library"
            case .advanced: "Advanced"
            }
        }

        var symbolName: String {
            switch self {
            case .general: "gearshape"
            case .reading: "book"
            case .library: "rectangle.grid.2x2"
            case .advanced: "slider.horizontal.3"
            }
        }
    }

    private let store: any AppSettingsStoring
    private let applyAppearance: (AppAppearance) -> Void

    var selectedTab: Tab = .general
    private(set) var settings: AppSettings

    convenience init() {
        self.init(
            store: UserDefaultsAppSettingsStore(),
            applyAppearance: { appearance in
                AppAppearance.apply(appearance)
            }
        )
    }

    init(
        store: any AppSettingsStoring,
        applyAppearance: @escaping (AppAppearance) -> Void
    ) {
        self.store = store
        self.applyAppearance = applyAppearance
        settings = store.load()
    }

    func setAppearance(_ appearance: AppAppearance) {
        update { $0.appearance = appearance }
        applyAppearance(appearance)
    }

    func setShowsReadingProgress(_ showsReadingProgress: Bool) {
        update { $0.showsReadingProgress = showsReadingProgress }
    }

    func setShowsPrivateBookBadges(_ showsPrivateBookBadges: Bool) {
        update { $0.showsPrivateBookBadges = showsPrivateBookBadges }
    }

    func setDefaultReadingAppearance(_ readingAppearance: ReadingAppearance) {
        update { $0.defaultReadingAppearance = readingAppearance }
    }

    func restoreDefaults() {
        store.reset()
        settings = store.load()
        applyAppearance(settings.appearance)
    }

    private func update(_ transform: (inout AppSettings) -> Void) {
        var updatedSettings = settings
        transform(&updatedSettings)
        settings = updatedSettings
        store.save(updatedSettings)
    }
}
