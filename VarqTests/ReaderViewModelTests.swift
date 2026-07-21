import AppKit
import Foundation
import Testing
@testable import Varq

@MainActor
struct ReaderViewModelTests {
    @Test func opensAndPublishesTheRendererLocator() async throws {
        let initialLocator = try BookLocator(
            format: .epub,
            spineIndex: 0,
            resourceHref: "chapter-1.xhtml",
            progression: 0
        )
        let renderer = FakeBookRenderer(locator: initialLocator)
        let viewModel = ReaderViewModel(bookURL: URL(fileURLWithPath: "/tmp/book.epub"), renderer: renderer)

        await viewModel.open()

        #expect(viewModel.currentLocator == initialLocator)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func refreshesTheLocatorAfterNavigation() async throws {
        let initialLocator = try BookLocator(
            format: .epub,
            spineIndex: 0,
            resourceHref: "chapter-1.xhtml",
            progression: 0
        )
        let advancedLocator = try BookLocator(
            format: .epub,
            spineIndex: 0,
            resourceHref: "chapter-1.xhtml",
            progression: 0.5
        )
        let renderer = FakeBookRenderer(locator: initialLocator, advancedLocator: advancedLocator)
        let viewModel = ReaderViewModel(bookURL: URL(fileURLWithPath: "/tmp/book.epub"), renderer: renderer)

        await viewModel.open()
        await viewModel.goForward()

        #expect(viewModel.currentLocator == advancedLocator)
    }

    @Test func clearsTheLocatorWhenClosing() async throws {
        let locator = try BookLocator(
            format: .epub,
            spineIndex: 0,
            resourceHref: "chapter-1.xhtml",
            progression: 0
        )
        let renderer = FakeBookRenderer(locator: locator)
        let viewModel = ReaderViewModel(bookURL: URL(fileURLWithPath: "/tmp/book.epub"), renderer: renderer)

        await viewModel.open()
        await viewModel.close()

        #expect(viewModel.currentLocator == nil)
        #expect(renderer.didClose)
    }
}

@MainActor
private final class FakeBookRenderer: BookRenderer {
    let view = NSView()
    let supportedFormat: BookFormat = .epub
    private let initialLocator: BookLocator
    private let advancedLocator: BookLocator?

    private(set) var currentLocator: BookLocator?
    private(set) var didClose = false

    init(locator: BookLocator, advancedLocator: BookLocator? = nil) {
        initialLocator = locator
        self.advancedLocator = advancedLocator
    }

    func open(bookURL: URL, at locator: BookLocator?) async throws {
        currentLocator = locator ?? initialLocator
    }

    func close() async {
        didClose = true
        currentLocator = nil
    }

    func goForward() async throws -> Bool {
        guard let advancedLocator else {
            return false
        }
        currentLocator = advancedLocator
        return true
    }

    func goBackward() async throws -> Bool {
        false
    }

    func go(to locator: BookLocator) async throws {
        currentLocator = locator
    }
}
