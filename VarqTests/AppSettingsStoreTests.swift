import Foundation
import Testing
@testable import Varq

@MainActor
struct AppSettingsStoreTests {
    @Test func persistsAllSettings() throws {
        let (defaults, suiteName) = try testDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let readingAppearance = ReadingAppearance(
            pageTone: .dark,
            comicReadingDirection: .rightToLeft,
            comicPageLayout: .dualPage,
            comicPageFit: .actualSize,
            epubPageLayout: .twoPageSpread,
            fontFamily: .newYork,
            fontSize: 22,
            lineHeight: 1.9,
            horizontalMargin: 48
        )
        let expected = AppSettings(
            appearance: .dark,
            showsReadingProgress: false,
            showsPrivateBookBadges: false,
            defaultReadingAppearance: readingAppearance
        )

        store.save(expected)

        #expect(store.load() == expected)
    }

    @Test func restoresFallbacksAfterReset() throws {
        let (defaults, suiteName) = try testDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        store.save(
            AppSettings(
                appearance: .light,
                showsReadingProgress: false,
                showsPrivateBookBadges: false,
                defaultReadingAppearance: ReadingAppearance(pageTone: .dark, fontSize: 24)
            )
        )

        store.reset()

        #expect(store.load() == AppSettings())
    }

    private func testDefaults() throws -> (UserDefaults, String) {
        let suiteName = "AppSettingsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestDefaultsError.unavailable
        }
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private enum TestDefaultsError: Error {
        case unavailable
    }
}
