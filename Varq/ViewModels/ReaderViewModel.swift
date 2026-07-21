import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ReaderViewModel {
    private let renderer: any BookRenderer
    private let bookURL: URL

    private(set) var currentLocator: BookLocator?
    private(set) var errorMessage: String?
    var rendererView: NSView { renderer.view }

    init(bookURL: URL, renderer: some BookRenderer) {
        self.bookURL = bookURL
        self.renderer = renderer
    }

    func open(at locator: BookLocator? = nil) async {
        do {
            try await renderer.open(bookURL: bookURL, at: locator)
            currentLocator = renderer.currentLocator
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func goForward() async {
        await navigate { try await renderer.goForward() }
    }

    func goBackward() async {
        await navigate { try await renderer.goBackward() }
    }

    func close() async {
        await renderer.close()
        currentLocator = nil
    }

    private func navigate(_ operation: () async throws -> Bool) async {
        do {
            _ = try await operation()
            currentLocator = renderer.currentLocator
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
