import AppKit
import Foundation
import SwiftData
import Testing
@testable import Varq

@MainActor
struct ReaderViewModelTests {
    @Test func opensAndPublishesTheRendererLocator() async throws {
        let initialLocator = try epubLocator(progression: 0)
        let renderer = FakeBookRenderer(locator: initialLocator)
        let viewModel = ReaderViewModel(book: book(), bookURL: bookURL, renderer: renderer)

        await viewModel.open()

        #expect(viewModel.currentLocator == initialLocator)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func persistsTheLocatorAfterNavigation() async throws {
        let initialLocator = try epubLocator(progression: 0)
        let advancedLocator = try epubLocator(progression: 0.5)
        let renderer = FakeBookRenderer(locator: initialLocator, advancedLocator: advancedLocator)
        let context = try modelContext()
        let book = book()
        context.insert(book)
        try context.save()
        let viewModel = ReaderViewModel(book: book, bookURL: bookURL, renderer: renderer)
        viewModel.configurePersistence(using: context)

        await viewModel.open()
        await viewModel.goForward()

        let persistedData = try #require(book.readingProgress?.locatorData)
        #expect(try JSONDecoder().decode(BookLocator.self, from: persistedData) == advancedLocator)
    }

    @Test func updatesTheRendererWithReadingAppearanceChanges() async throws {
        let locator = try epubLocator(progression: 0)
        let renderer = FakeBookRenderer(locator: locator)
        let viewModel = ReaderViewModel(book: book(), bookURL: bookURL, renderer: renderer)

        await viewModel.setPageTone(.dark)
        await viewModel.setFontSize(ReadingAppearance.maximumFontSize)
        await viewModel.setLineHeight(1.9)
        await viewModel.setHorizontalMargin(ReadingAppearance.maximumHorizontalMargin)
        await viewModel.setFontFamily(.newYork)

        #expect(viewModel.readingAppearance.pageTone == .dark)
        #expect(viewModel.readingAppearance.fontSize == ReadingAppearance.maximumFontSize)
        #expect(viewModel.readingAppearance.lineHeight == 1.9)
        #expect(viewModel.readingAppearance.horizontalMargin == ReadingAppearance.maximumHorizontalMargin)
        #expect(viewModel.readingAppearance.fontFamily == .newYork)
        #expect(renderer.updatedAppearance == viewModel.readingAppearance)
    }

    @Test func restoresAndClearsThePersistedLocatorWhenClosing() async throws {
        let storedLocator = try epubLocator(progression: 0.25)
        let renderer = FakeBookRenderer(locator: try epubLocator(progression: 0))
        let context = try modelContext()
        let book = book()
        let progress = ReadingProgress(locatorData: try JSONEncoder().encode(storedLocator), book: book)
        context.insert(book)
        context.insert(progress)
        try context.save()
        let viewModel = ReaderViewModel(book: book, bookURL: bookURL, renderer: renderer)
        viewModel.configurePersistence(using: context)

        await viewModel.open()
        await viewModel.close()

        #expect(renderer.openedLocator == storedLocator)
        #expect(renderer.didClose)
        #expect(viewModel.currentLocator == nil)
    }

    private var bookURL: URL {
        URL(fileURLWithPath: "/tmp/book.epub")
    }

    private func book() -> Book {
        Book(
            title: "Fixture Book",
            author: "Varq Tests",
            libraryRelativePath: "fixture.epub",
            contentHash: UUID().uuidString,
            format: .epub
        )
    }

    private func epubLocator(progression: Double) throws -> BookLocator {
        try BookLocator(
            format: .epub,
            spineIndex: 0,
            resourceHref: "chapter-1.xhtml",
            progression: progression
        )
    }

    private func modelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Book.self,
            ReadingProgress.self,
            Highlight.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}

@MainActor
private final class FakeBookRenderer: BookRenderer {
    let view = NSView()
    let supportedFormat: BookFormat = .epub
    private let initialLocator: BookLocator
    private let advancedLocator: BookLocator?

    private(set) var currentLocator: BookLocator?
    private(set) var openedLocator: BookLocator?
    private(set) var updatedAppearance: ReadingAppearance?
    private(set) var didClose = false

    init(locator: BookLocator, advancedLocator: BookLocator? = nil) {
        initialLocator = locator
        self.advancedLocator = advancedLocator
    }

    func open(bookURL: URL, at locator: BookLocator?) async throws {
        openedLocator = locator
        currentLocator = locator ?? initialLocator
    }

    func updateReadingAppearance(_ appearance: ReadingAppearance) async throws {
        updatedAppearance = appearance
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
