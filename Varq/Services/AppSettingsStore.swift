import Foundation

/// Persistent preferences shared by the library, reader, and settings screen.
struct AppSettings: Equatable, Sendable {
    var appearance: AppAppearance
    var showsReadingProgress: Bool
    var showsPrivateBookBadges: Bool
    var defaultReadingAppearance: ReadingAppearance

    init(
        appearance: AppAppearance = .system,
        showsReadingProgress: Bool = true,
        showsPrivateBookBadges: Bool = true,
        defaultReadingAppearance: ReadingAppearance = ReadingAppearance()
    ) {
        self.appearance = appearance
        self.showsReadingProgress = showsReadingProgress
        self.showsPrivateBookBadges = showsPrivateBookBadges
        self.defaultReadingAppearance = defaultReadingAppearance
    }
}

enum AppAppearance: String, CaseIterable, Sendable {
    case system
    case light
    case indigo = "dark"
    case black
    case monochrome

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .indigo: "Indigo"
        case .black: "Black"
        case .monochrome: "Mono"
        }
    }
}

@MainActor
protocol AppSettingsStoring {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
    func reset()
}

@MainActor
final class UserDefaultsAppSettingsStore: AppSettingsStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        AppSettings(
            appearance: stringValue(forKey: AppSettingsKey.appearance, default: .system),
            showsReadingProgress: boolValue(forKey: AppSettingsKey.showsReadingProgress, default: true),
            showsPrivateBookBadges: boolValue(forKey: AppSettingsKey.showsPrivateBookBadges, default: true),
            defaultReadingAppearance: ReadingAppearance(
                pageTone: stringValue(forKey: AppSettingsKey.defaultPageTone, default: .sepia),
                comicReadingDirection: stringValue(forKey: AppSettingsKey.defaultComicReadingDirection, default: .leftToRight),
                comicPageLayout: stringValue(forKey: AppSettingsKey.defaultComicPageLayout, default: .singlePage),
                comicPageFit: stringValue(forKey: AppSettingsKey.defaultComicPageFit, default: .fitWidth),
                epubPageLayout: stringValue(forKey: AppSettingsKey.defaultEpubPageLayout, default: .singlePage),
                fontFamily: stringValue(forKey: AppSettingsKey.defaultFontFamily, default: .georgia),
                fontSize: doubleValue(forKey: AppSettingsKey.defaultFontSize, default: ReadingAppearance.defaultFontSize),
                lineHeight: doubleValue(forKey: AppSettingsKey.defaultLineHeight, default: ReadingAppearance.defaultLineHeight),
                horizontalMargin: doubleValue(forKey: AppSettingsKey.defaultHorizontalMargin, default: ReadingAppearance.defaultHorizontalMargin)
            )
        )
    }

    func save(_ settings: AppSettings) {
        defaults.set(settings.appearance.rawValue, forKey: AppSettingsKey.appearance)
        defaults.set(settings.showsReadingProgress, forKey: AppSettingsKey.showsReadingProgress)
        defaults.set(settings.showsPrivateBookBadges, forKey: AppSettingsKey.showsPrivateBookBadges)

        let readingAppearance = settings.defaultReadingAppearance
        defaults.set(readingAppearance.pageTone.rawValue, forKey: AppSettingsKey.defaultPageTone)
        defaults.set(readingAppearance.comicReadingDirection.rawValue, forKey: AppSettingsKey.defaultComicReadingDirection)
        defaults.set(readingAppearance.comicPageLayout.rawValue, forKey: AppSettingsKey.defaultComicPageLayout)
        defaults.set(readingAppearance.comicPageFit.rawValue, forKey: AppSettingsKey.defaultComicPageFit)
        defaults.set(readingAppearance.epubPageLayout.rawValue, forKey: AppSettingsKey.defaultEpubPageLayout)
        defaults.set(readingAppearance.fontFamily.rawValue, forKey: AppSettingsKey.defaultFontFamily)
        defaults.set(readingAppearance.fontSize, forKey: AppSettingsKey.defaultFontSize)
        defaults.set(readingAppearance.lineHeight, forKey: AppSettingsKey.defaultLineHeight)
        defaults.set(readingAppearance.horizontalMargin, forKey: AppSettingsKey.defaultHorizontalMargin)
    }

    func reset() {
        AppSettingsKey.all.forEach(defaults.removeObject(forKey:))
    }

    private func stringValue<Value: RawRepresentable>(
        forKey key: String,
        default defaultValue: Value
    ) -> Value where Value.RawValue == String {
        guard let rawValue = defaults.string(forKey: key),
              let value = Value(rawValue: rawValue) else {
            return defaultValue
        }
        return value
    }

    private func boolValue(forKey key: String, default defaultValue: Bool) -> Bool {
        guard let value = defaults.object(forKey: key) as? Bool else {
            return defaultValue
        }
        return value
    }

    private func doubleValue(forKey key: String, default defaultValue: Double) -> Double {
        guard let value = defaults.object(forKey: key) as? Double else {
            return defaultValue
        }
        return value
    }
}

enum AppSettingsKey {
    static let appearance = "appAppearanceOverride"
    static let showsReadingProgress = "showsReadingProgress"
    static let showsPrivateBookBadges = "showsPrivateBookBadges"
    static let defaultPageTone = "defaultReaderPageTone"
    static let defaultComicReadingDirection = "defaultComicReadingDirection"
    static let defaultComicPageLayout = "defaultComicPageLayout"
    static let defaultComicPageFit = "defaultComicPageFit"
    static let defaultEpubPageLayout = "defaultEpubPageLayout"
    static let defaultFontFamily = "defaultReaderFontFamily"
    static let defaultFontSize = "defaultReaderFontSize"
    static let defaultLineHeight = "defaultReaderLineHeight"
    static let defaultHorizontalMargin = "defaultReaderHorizontalMargin"

    static let all = [
        appearance,
        showsReadingProgress,
        showsPrivateBookBadges,
        defaultPageTone,
        defaultComicReadingDirection,
        defaultComicPageLayout,
        defaultComicPageFit,
        defaultEpubPageLayout,
        defaultFontFamily,
        defaultFontSize,
        defaultLineHeight,
        defaultHorizontalMargin,
    ]
}
