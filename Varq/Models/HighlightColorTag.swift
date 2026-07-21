import Foundation

enum HighlightColorTag: String, CaseIterable, Codable, Sendable {
    case saffron
    case terracotta
    case maroon

    var displayName: String { rawValue.capitalized }
}
