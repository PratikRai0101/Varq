import Foundation
import Observation

@MainActor
@Observable
final class HighlightsViewModel {
    private(set) var highlights: [Highlight] = []

    func load(for book: Book) {
        highlights = book.highlights.sorted { $0.dateCreated > $1.dateCreated }
    }

    func remove(_ highlight: Highlight) {
        highlights.removeAll { $0.id == highlight.id }
    }
}
