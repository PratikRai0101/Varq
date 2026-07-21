import SwiftUI

enum VarqSpacing {
    static let compact: CGFloat = 8
    static let regular: CGFloat = 16
    static let large: CGFloat = 24
}

enum VarqLayout {
    static let coverGridMinimumWidth: CGFloat = 180
    static let pageTurnSwipeDistance: CGFloat = 48
    static let pageTurnShadowRadius: CGFloat = 16
    static let noteEditorMinimumWidth: CGFloat = 360
    static let noteEditorMinimumHeight: CGFloat = 260
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
