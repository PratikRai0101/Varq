import AppKit
import Foundation

@MainActor
protocol BookRenderer: AnyObject {
    var view: NSView { get }
    var currentLocator: BookLocator? { get }
    var readingProgressFraction: Double { get }
    var supportedFormat: BookFormat { get }

    func open(bookURL: URL, at locator: BookLocator?) async throws
    func updateReadingAppearance(_ appearance: ReadingAppearance) async throws
    func close() async
    func goForward() async throws -> Bool
    func goBackward() async throws -> Bool
    func go(to locator: BookLocator) async throws
    func navigate(to highlightAnchor: TextHighlightAnchor) async throws
    func renderHighlights(_ highlights: [Highlight]) async
    func renderNotes(_ notes: [ReadingNote]) async
}

extension BookRenderer {
    var readingProgressFraction: Double {
        currentLocator?.progression ?? 0
    }

    func navigate(to highlightAnchor: TextHighlightAnchor) async throws {
        try await go(to: highlightAnchor.locator)
    }

    func renderHighlights(_ highlights: [Highlight]) async {}

    func renderNotes(_ notes: [ReadingNote]) async {}
}

enum BookRendererError: Error, Equatable {
    case cannotOpenDocument
    case incompatibleLocatorFormat(BookFormat)
    case invalidLocator
}
