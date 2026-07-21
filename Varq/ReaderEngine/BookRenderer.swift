import AppKit
import Foundation

@MainActor
protocol BookRenderer: AnyObject {
    var view: NSView { get }
    var currentLocator: BookLocator? { get }
    var supportedFormat: BookFormat { get }

    func open(bookURL: URL, at locator: BookLocator?) async throws
    func updateReadingAppearance(_ appearance: ReadingAppearance) async throws
    func close() async
    func goForward() async throws -> Bool
    func goBackward() async throws -> Bool
    func go(to locator: BookLocator) async throws
}

enum BookRendererError: Error, Equatable {
    case cannotOpenDocument
    case incompatibleLocatorFormat(BookFormat)
    case invalidLocator
}
