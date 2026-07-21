import SwiftUI

enum VarqSpacing {
    static let compact: CGFloat = 8
    static let regular: CGFloat = 16
    static let large: CGFloat = 24
}

enum VarqLayout {
    static let coverGridMinimumWidth: CGFloat = 152
    static let pageTurnSwipeDistance: CGFloat = 48
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
