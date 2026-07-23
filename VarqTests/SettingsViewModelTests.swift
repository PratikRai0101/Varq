import Testing
@testable import Varq

@MainActor
struct SettingsViewModelTests {
    @Test func persistsSettingsAndAppliesAppearanceImmediately() {
        let store = InMemoryAppSettingsStore(settings: AppSettings())
        var appliedAppearances: [AppAppearance] = []
        let viewModel = SettingsViewModel(
            store: store,
            applyAppearance: { appearance in
                appliedAppearances.append(appearance)
            }
        )
        var readingAppearance = ReadingAppearance()
        readingAppearance.pageTone = .dark
        readingAppearance.fontFamily = .newYork
        readingAppearance.fontSize = 21

        viewModel.setAppearance(.black)
        viewModel.setShowsReadingProgress(false)
        viewModel.setShowsPrivateBookBadges(false)
        viewModel.setDefaultReadingAppearance(readingAppearance)

        #expect(viewModel.settings.appearance == .black)
        #expect(viewModel.settings.showsReadingProgress == false)
        #expect(viewModel.settings.showsPrivateBookBadges == false)
        #expect(viewModel.settings.defaultReadingAppearance == readingAppearance)
        #expect(store.settings == viewModel.settings)
        #expect(appliedAppearances == [.black])
    }

    @Test func restoresDefaultsWithoutChangingBookData() {
        let initialSettings = AppSettings(
            appearance: .light,
            showsReadingProgress: false,
            showsPrivateBookBadges: false,
            defaultReadingAppearance: ReadingAppearance(pageTone: .dark)
        )
        let store = InMemoryAppSettingsStore(settings: initialSettings)
        var appliedAppearances: [AppAppearance] = []
        let viewModel = SettingsViewModel(
            store: store,
            applyAppearance: { appearance in
                appliedAppearances.append(appearance)
            }
        )

        viewModel.restoreDefaults()

        #expect(viewModel.settings == AppSettings())
        #expect(store.settings == AppSettings())
        #expect(appliedAppearances == [.system])
    }
}

@MainActor
private final class InMemoryAppSettingsStore: AppSettingsStoring {
    var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func load() -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) {
        self.settings = settings
    }

    func reset() {
        settings = AppSettings()
    }
}
