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

    @Test func recordsTheInitialLocatorWhenOpening() async throws {
        let initialLocator = try epubLocator(progression: 0)
        let renderer = FakeBookRenderer(locator: initialLocator)
        let context = try modelContext()
        let book = book()
        context.insert(book)
        try context.save()
        let viewModel = ReaderViewModel(book: book, bookURL: bookURL, renderer: renderer)
        viewModel.configurePersistence(using: context)

        await viewModel.open()

        let locatorData = try #require(book.readingProgress?.locatorData)
        #expect(try JSONDecoder().decode(BookLocator.self, from: locatorData) == initialLocator)
        #expect(book.readingProgress?.percentComplete == 0)
    }

    @Test func persistsTheRendererOverallProgress() async throws {
        let initialLocator = try epubLocator(progression: 0)
        let renderer = FakeBookRenderer(locator: initialLocator, reportedProgressFraction: 0.4)
        let context = try modelContext()
        let book = book()
        context.insert(book)
        try context.save()
        let viewModel = ReaderViewModel(book: book, bookURL: bookURL, renderer: renderer)
        viewModel.configurePersistence(using: context)

        await viewModel.open()

        #expect(book.readingProgress?.percentComplete == 0.4)
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
        await viewModel.setComicReadingDirection(.rightToLeft)
        await viewModel.setComicPageLayout(.dualPage)
        await viewModel.setComicPageFit(.fitHeight)
        await viewModel.setFontSize(ReadingAppearance.maximumFontSize)
        await viewModel.setLineHeight(1.9)
        await viewModel.setHorizontalMargin(ReadingAppearance.maximumHorizontalMargin)
        await viewModel.setFontFamily(.newYork)

        #expect(viewModel.readingAppearance.pageTone == .dark)
        #expect(viewModel.readingAppearance.comicReadingDirection == .rightToLeft)
        #expect(viewModel.readingAppearance.comicPageLayout == .dualPage)
        #expect(viewModel.readingAppearance.comicPageFit == .fitHeight)
        #expect(viewModel.readingAppearance.fontSize == ReadingAppearance.maximumFontSize)
        #expect(viewModel.readingAppearance.lineHeight == 1.9)
        #expect(viewModel.readingAppearance.horizontalMargin == ReadingAppearance.maximumHorizontalMargin)
        #expect(viewModel.readingAppearance.fontFamily == .newYork)
        #expect(renderer.updatedAppearance == viewModel.readingAppearance)
    }

    @Test func createsAPersistedHighlightFromTheRendererSelection() async throws {
        let locator = try epubLocator(progression: 0)
        let anchor = try TextHighlightAnchor(
            locator: locator,
            startOffset: 3,
            endOffset: 11,
            quote: TextQuoteSelector(exact: "selected")
        )
        let renderer = FakeBookRenderer(locator: locator, selectedAnchor: anchor)
        let context = try modelContext()
        let book = book()
        context.insert(book)
        try context.save()
        let viewModel = ReaderViewModel(book: book, bookURL: bookURL, renderer: renderer)
        viewModel.configurePersistence(using: context)

        let createdHighlight = await viewModel.createHighlight(color: .saffron)

        let highlight = try #require(createdHighlight)
        #expect(book.highlights.first === highlight)
        #expect(highlight.selectedText == "selected")
        #expect(highlight.colorTag == HighlightColorTag.saffron.rawValue)
        #expect(try JSONDecoder().decode(TextHighlightAnchor.self, from: highlight.locatorData) == anchor)
        #expect(renderer.renderedHighlightIDs == [[highlight.id]])
    }

    @Test func createsAndRendersAPageNote() async throws {
        let locator = try epubLocator(progression: 0)
        let renderer = FakeBookRenderer(locator: locator)
        let context = try modelContext()
        let book = book()
        context.insert(book)
        try context.save()
        let viewModel = ReaderViewModel(book: book, bookURL: bookURL, renderer: renderer)
        viewModel.configurePersistence(using: context)
        await viewModel.open()

        viewModel.beginPageNote()
        let state = try #require(viewModel.noteEditorState)
        #expect(state.anchor.kind == .pageLocation)
        await viewModel.saveNote(body: "A personal page note", color: .highlightGreen)

        let note = try #require(book.notes.first)
        #expect(note.body == "A personal page note")
        #expect(note.colorTag == HighlightColorTag.highlightGreen.rawValue)
        #expect(try JSONDecoder().decode(ReadingNoteAnchor.self, from: note.anchorData) == state.anchor)
        #expect(renderer.renderedNoteIDs.last == [note.id])
        #expect(viewModel.noteEditorState == nil)
    }

    @Test func opensANoteEditorFromASelectedTextContextAction() async throws {
        let locator = try epubLocator(progression: 0)
        let selectionAnchor = try TextHighlightAnchor(
            locator: locator,
            startOffset: 3,
            endOffset: 11,
            quote: TextQuoteSelector(exact: "selected")
        )
        let renderer = FakeBookRenderer(locator: locator)
        let viewModel = ReaderViewModel(book: book(), bookURL: bookURL, renderer: renderer)

        renderer.sendAnnotationAction(.createNote(anchor: selectionAnchor))

        let state = try #require(viewModel.noteEditorState)
        #expect(state.anchor.kind == .textSelection)
        #expect(state.selectedText == "selected")
    }

    @Test func opensAnExistingNoteFromAMarkerActivation() throws {
        let locator = try epubLocator(progression: 0)
        let anchor = ReadingNoteAnchor(pageLocator: locator)
        let note = ReadingNote(
            anchorData: try JSONEncoder().encode(anchor),
            body: "A saved note",
            colorTag: HighlightColorTag.terracotta.rawValue
        )
        let book = book()
        book.notes = [note]
        let renderer = FakeBookRenderer(locator: locator)
        let viewModel = ReaderViewModel(book: book, bookURL: bookURL, renderer: renderer)

        renderer.sendNoteActivation(note.id)

        let state = try #require(viewModel.noteEditorState)
        #expect(state.existingNote === note)
        #expect(state.initialBody == "A saved note")
        #expect(state.initialColor == .terracotta)
    }

    @Test func deletesANoteAndRemovesItsMarker() async throws {
        let locator = try epubLocator(progression: 0)
        let context = try modelContext()
        let book = book()
        let note = ReadingNote(
            anchorData: try JSONEncoder().encode(ReadingNoteAnchor(pageLocator: locator)),
            body: "A note to remove",
            colorTag: HighlightColorTag.maroon.rawValue,
            book: book
        )
        context.insert(book)
        context.insert(note)
        try context.save()
        let renderer = FakeBookRenderer(locator: locator)
        let viewModel = ReaderViewModel(book: book, bookURL: bookURL, renderer: renderer)
        viewModel.configurePersistence(using: context)

        await viewModel.deleteNote(note)

        #expect(book.notes.isEmpty)
        #expect(renderer.renderedNoteIDs.last == [])
    }

    @Test func deletesAHighlightAndRemovesItsRendering() async throws {
        let locator = try epubLocator(progression: 0)
        let anchor = try TextHighlightAnchor(
            locator: locator,
            startOffset: 3,
            endOffset: 11,
            quote: TextQuoteSelector(exact: "selected")
        )
        let context = try modelContext()
        let book = book()
        let highlight = Highlight(
            locatorData: try JSONEncoder().encode(anchor),
            selectedText: anchor.quote.exact,
            colorTag: HighlightColorTag.highlightYellow.rawValue,
            book: book
        )
        context.insert(book)
        context.insert(highlight)
        try context.save()
        let renderer = FakeBookRenderer(locator: locator)
        let viewModel = ReaderViewModel(book: book, bookURL: bookURL, renderer: renderer)
        viewModel.configurePersistence(using: context)

        #expect(await viewModel.deleteHighlight(highlight))

        #expect(book.highlights.isEmpty)
        #expect(renderer.renderedHighlightIDs.last == [])
    }

    @Test func removesAnOverlappingHighlightFromTheContextAction() async throws {
        let savedLocator = try epubLocator(progression: 0.1)
        let selectedLocator = try epubLocator(progression: 0.8)
        let savedAnchor = try TextHighlightAnchor(
            locator: savedLocator,
            startOffset: 3,
            endOffset: 11,
            quote: TextQuoteSelector(exact: "selected")
        )
        let selectedAnchor = try TextHighlightAnchor(
            locator: selectedLocator,
            startOffset: 5,
            endOffset: 9,
            quote: TextQuoteSelector(exact: "lect")
        )
        let context = try modelContext()
        let book = book()
        let highlight = Highlight(
            locatorData: try JSONEncoder().encode(savedAnchor),
            selectedText: savedAnchor.quote.exact,
            colorTag: HighlightColorTag.highlightGreen.rawValue,
            book: book
        )
        context.insert(book)
        context.insert(highlight)
        try context.save()
        let renderer = FakeBookRenderer(locator: selectedLocator)
        let viewModel = ReaderViewModel(book: book, bookURL: bookURL, renderer: renderer)
        viewModel.configurePersistence(using: context)

        renderer.sendAnnotationAction(.removeHighlight(anchor: selectedAnchor))
        for _ in 0..<10 where !book.highlights.isEmpty {
            await Task.yield()
        }

        #expect(book.highlights.isEmpty)
        #expect(renderer.renderedHighlightIDs.last == [])
    }

    @Test func rendersPersistedHighlightsThroughTheRendererInterface() async throws {
        let locator = try epubLocator(progression: 0)
        let anchor = try TextHighlightAnchor(
            locator: locator,
            startOffset: 3,
            endOffset: 11,
            quote: TextQuoteSelector(exact: "selected")
        )
        let renderer = FakeBookRenderer(locator: locator)
        let book = book()
        let highlight = Highlight(
            locatorData: try JSONEncoder().encode(anchor),
            selectedText: anchor.quote.exact,
            colorTag: HighlightColorTag.saffron.rawValue
        )
        book.highlights = [highlight]
        let viewModel = ReaderViewModel(book: book, bookURL: bookURL, renderer: renderer)

        await viewModel.open()

        #expect(renderer.renderedHighlightIDs == [[highlight.id]])
    }

    @Test func navigatesToAHighlightThroughTheRendererInterface() async throws {
        let initialLocator = try epubLocator(progression: 0)
        let highlightLocator = try epubLocator(progression: 0.75)
        let anchor = try TextHighlightAnchor(
            locator: highlightLocator,
            startOffset: 3,
            endOffset: 11,
            quote: TextQuoteSelector(exact: "selected")
        )
        let highlight = Highlight(
            locatorData: try JSONEncoder().encode(anchor),
            selectedText: anchor.quote.exact,
            colorTag: HighlightColorTag.saffron.rawValue
        )
        let renderer = FakeBookRenderer(locator: initialLocator)
        let viewModel = ReaderViewModel(book: book(), bookURL: bookURL, renderer: renderer)

        await viewModel.navigateToHighlight(highlight)

        #expect(renderer.navigatedHighlightAnchor == anchor)
        #expect(viewModel.currentLocator == highlightLocator)
        #expect(viewModel.errorMessage == nil)
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
            ReadingNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}

@MainActor
private final class FakeBookRenderer: BookRenderer, TextSelectionProviding, ReaderAnnotationInteractionProviding {
    let view = NSView()
    let supportedFormat: BookFormat = .epub
    private let initialLocator: BookLocator
    private let reportedProgressFraction: Double?
    private let advancedLocator: BookLocator?
    private let selectedAnchor: TextHighlightAnchor?
    private var annotationActionHandler: ((ReaderAnnotationAction) -> Void)?
    private var noteActivationHandler: ((UUID) -> Void)?

    private(set) var currentLocator: BookLocator?
    var readingProgressFraction: Double { reportedProgressFraction ?? currentLocator?.progression ?? 0 }
    private(set) var openedLocator: BookLocator?
    private(set) var updatedAppearance: ReadingAppearance?
    private(set) var renderedHighlightIDs: [[UUID]] = []
    private(set) var renderedNoteIDs: [[UUID]] = []
    private(set) var navigatedHighlightAnchor: TextHighlightAnchor?
    private(set) var didClose = false

    init(
        locator: BookLocator,
        advancedLocator: BookLocator? = nil,
        selectedAnchor: TextHighlightAnchor? = nil,
        reportedProgressFraction: Double? = nil
    ) {
        initialLocator = locator
        self.advancedLocator = advancedLocator
        self.selectedAnchor = selectedAnchor
        self.reportedProgressFraction = reportedProgressFraction
    }

    func open(bookURL: URL, at locator: BookLocator?) async throws {
        openedLocator = locator
        currentLocator = locator ?? initialLocator
    }

    func updateReadingAppearance(_ appearance: ReadingAppearance) async throws {
        updatedAppearance = appearance
    }

    func selectedTextHighlightAnchor() async throws -> TextHighlightAnchor? {
        selectedAnchor
    }

    func setAnnotationActionHandler(_ handler: @escaping (ReaderAnnotationAction) -> Void) {
        annotationActionHandler = handler
    }

    func setNoteActivationHandler(_ handler: @escaping (UUID) -> Void) {
        noteActivationHandler = handler
    }

    func sendAnnotationAction(_ action: ReaderAnnotationAction) {
        annotationActionHandler?(action)
    }

    func sendNoteActivation(_ noteID: UUID) {
        noteActivationHandler?(noteID)
    }

    func renderHighlights(_ highlights: [Highlight]) async {
        renderedHighlightIDs.append(highlights.map(\.id))
    }

    func renderNotes(_ notes: [ReadingNote]) async {
        renderedNoteIDs.append(notes.map(\.id))
    }

    func navigate(to highlightAnchor: TextHighlightAnchor) async throws {
        navigatedHighlightAnchor = highlightAnchor
        try await go(to: highlightAnchor.locator)
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
