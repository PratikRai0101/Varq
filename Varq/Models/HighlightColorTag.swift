import Foundation

enum HighlightColorTag: String, CaseIterable, Codable, Sendable {
    case saffron
    case terracotta
    case maroon
    case highlightGreen
    case highlightYellow
    case highlightRed
    case highlightPink

    var displayName: String {
        switch self {
        case .saffron: "Saffron"
        case .terracotta: "Terracotta"
        case .maroon: "Maroon"
        case .highlightGreen: "Neon green"
        case .highlightYellow: "Neon yellow"
        case .highlightRed: "Neon red"
        case .highlightPink: "Neon pink"
        }
    }
}
