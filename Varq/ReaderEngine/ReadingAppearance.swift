import Foundation

enum ReadingFontFamily: String, CaseIterable, Codable, Sendable {
    case georgia
    case newYork

    var displayName: String {
        switch self {
        case .georgia: "Georgia"
        case .newYork: "New York"
        }
    }

    var cssFamily: String {
        switch self {
        case .georgia: "Georgia, serif"
        case .newYork: "'New York', Georgia, serif"
        }
    }
}

struct ReadingAppearance: Codable, Equatable, Sendable {
    static let defaultFontSize = 17.0
    static let minimumFontSize = 14.0
    static let maximumFontSize = 28.0
    static let fontSizeStep = 1.0
    static let defaultLineHeight = 1.5
    static let lineHeights = [1.3, 1.5, 1.7, 1.9]
    static let defaultHorizontalMargin = 24.0
    static let minimumHorizontalMargin = 0.0
    static let maximumHorizontalMargin = 72.0
    static let horizontalMarginStep = 8.0

    var fontFamily: ReadingFontFamily
    var fontSize: Double
    var lineHeight: Double
    var horizontalMargin: Double

    init(
        fontFamily: ReadingFontFamily = .georgia,
        fontSize: Double = Self.defaultFontSize,
        lineHeight: Double = Self.defaultLineHeight,
        horizontalMargin: Double = Self.defaultHorizontalMargin
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.horizontalMargin = horizontalMargin
    }
}
