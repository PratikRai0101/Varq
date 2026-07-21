import Foundation

@MainActor
protocol TextSelectionProviding: AnyObject {
    func selectedTextHighlightAnchor() async throws -> TextHighlightAnchor?
}
