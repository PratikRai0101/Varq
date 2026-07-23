import SwiftUI

enum VarqSpacing {
    static let compact: CGFloat = 8
    static let regular: CGFloat = 16
    static let large: CGFloat = 24
}

enum VarqLayout {
    static let coverGridMinimumWidth: CGFloat = 180
    static let bookCoverAspectRatio: CGFloat = 0.68
    static let bookCardProgressHeight: CGFloat = 6
    static let bookCardProgressCornerRadius: CGFloat = 3
    static let sidebarMinimumWidth: CGFloat = 220
    static let sidebarIdealWidth: CGFloat = 240
    static let sidebarMaximumWidth: CGFloat = 280
    static let pageTurnSwipeDistance: CGFloat = 48
    static let pageTurnShadowRadius: CGFloat = 16
    static let noteEditorMinimumWidth: CGFloat = 360
    static let noteEditorMinimumHeight: CGFloat = 260
    static let settingsWindowWidth: CGFloat = 720
    static let settingsWindowHeight: CGFloat = 620
    static let settingsTabWidth: CGFloat = 96
    static let settingsTabHeight: CGFloat = 80
    static let settingsControlMaximumWidth: CGFloat = 240
    static let settingsContentMaximumWidth: CGFloat = 640
    static let settingsDividerHeight: CGFloat = 1
}

enum VarqMotion {
    static let pageTurnResponse = 0.32
    static let pageTurnDampingFraction = 0.82
    static let reducedMotionCrossFadeDuration = 0.18
    static let pageTurnSettleMilliseconds = 320
}

enum VarqOpacity {
    static let pageTurnOverlay = 0.22
    static let pageTurnShadow = 0.32
    static let settingsTabBorder = 0.35
    static let settingsSecondaryText = 0.72
    static let settingsDividerLight = 0.24
    static let settingsDividerDark = 0.32
}

enum VarqTypography {
    static let readingFontName = "Georgia"
    static let defaultReadingSize: CGFloat = 17

    static func ui(_ style: Font.TextStyle) -> Font {
        .system(style, design: .default, weight: .regular)
    }

    static func uiMedium(_ style: Font.TextStyle) -> Font {
        .system(style, design: .default, weight: .medium)
    }

    static func reading(size: CGFloat = defaultReadingSize) -> Font {
        .custom(readingFontName, size: size, relativeTo: .body)
    }
}
