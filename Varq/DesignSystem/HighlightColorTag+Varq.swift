import SwiftUI

extension HighlightColorTag {
    var varqColor: Color {
        switch self {
        case .saffron: .varqSaffron
        case .terracotta: .varqTerracotta
        case .maroon: .varqMaroon
        case .highlightGreen: .varqHighlightGreen
        case .highlightYellow: .varqHighlightYellow
        case .highlightRed: .varqHighlightRed
        case .highlightPink: .varqHighlightPink
        }
    }

    var webHighlightColor: String {
        switch self {
        case .saffron: VarqWebColor.saffron
        case .terracotta: VarqWebColor.terracotta
        case .maroon: VarqWebColor.maroon
        case .highlightGreen: VarqWebColor.highlightGreen
        case .highlightYellow: VarqWebColor.highlightYellow
        case .highlightRed: VarqWebColor.highlightRed
        case .highlightPink: VarqWebColor.highlightPink
        }
    }
}
