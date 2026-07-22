import AppKit
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ReaderViewModel {
    private let renderer: any BookRenderer
    private let book: Book
    private let bookURL: URL
    private let privateBookSessionService: PrivateBookSessionService
    private var modelContext: ModelContext?

    private(set) var currentLocator: BookLocator?
    private(set) var readingAppearance = ReadingAppearance()
    private(set) var noteEditorState: NoteEditorState?
    private(set) var errorMessage: String?
    var rendererView: NSView { renderer.view }
    var highlightedBook: Book { book }
    var supportsComicControls: Bool { renderer.supportedFormat == .cbz }
    var supportsEpubLayoutControls: Bool { renderer.supportedFormat == .epub }
    var supportsTextHighlights: Bool { renderer is any TextSelectionProviding }

    init(
        book: Book,
        bookURL: URL,
        renderer: some BookRenderer,
        privateBookSessionService: PrivateBookSessionService = PrivateBookSessionService()
    ) {
        self.book = book
        self.bookURL = bookURL
        self.renderer = renderer
        self.privateBookSessionService = privateBookSessionService

        if let interactionRenderer = renderer as? any ReaderAnnotationInteractionProviding {
            interactionRenderer.setAnnotationActionHandler { [weak self] action in
                self?.handleAnnotationAction(action)
            }
            interactionRenderer.setNoteActivationHandler { [weak self] noteID in
                self?.openNote(id: noteID)
            }
        }
    }

    func configurePersistence(using modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func open(at locator: BookLocator? = nil) async {
        do {
            let initialLocator = locator ?? storedLocator()
            let readerURL = try privateBookSessionService.readerURL(for: book, managedFileURL: bookURL)
            try await renderer.open(bookURL: readerURL, at: initialLocator)
            currentLocator = renderer.currentLocator
            persistCurrentLocator()
            await renderer.renderHighlights(book.highlights)
            await renderer.renderNotes(book.notes)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func goForward() async -> Bool {
        await navigate { try await renderer.goForward() }
    }

    func goBackward() async -> Bool {
        await navigate { try await renderer.goBackward() }
    }

    func setEpubPageLayout(_ pageLayout: EpubPageLayout) async {
        var appearance = readingAppearance
        appearance.epubPageLayout = pageLayout
        await updateReadingAppearance(appearance)
    }

    func setComicReadingDirection(_ readingDirection: ComicReadingDirection) async {
        var appearance = readingAppearance
        appearance.comicReadingDirection = readingDirection
        await updateReadingAppearance(appearance)
    }

    func setComicPageLayout(_ pageLayout: ComicPageLayout) async {
        var appearance = readingAppearance
        appearance.comicPageLayout = pageLayout
        await updateReadingAppearance(appearance)
    }

    func setComicPageFit(_ pageFit: ComicPageFit) async {
        var appearance = readingAppearance
        appearance.comicPageFit = pageFit
        await updateReadingAppearance(appearance)
    }

    func setPageTone(_ pageTone: ReaderPageTone) async {
        var appearance = readingAppearance
        appearance.pageTone = pageTone
        await updateReadingAppearance(appearance)
    }

    func setFontFamily(_ fontFamily: ReadingFontFamily) async {
        var appearance = readingAppearance
        appearance.fontFamily = fontFamily
        await updateReadingAppearance(appearance)
    }

    func setFontSize(_ fontSize: Double) async {
        var appearance = readingAppearance
        appearance.fontSize = min(max(fontSize, ReadingAppearance.minimumFontSize), ReadingAppearance.maximumFontSize)
        await updateReadingAppearance(appearance)
    }

    func setLineHeight(_ lineHeight: Double) async {
        guard ReadingAppearance.lineHeights.contains(lineHeight) else {
            return
        }
        var appearance = readingAppearance
        appearance.lineHeight = lineHeight
        await updateReadingAppearance(appearance)
    }

    func setHorizontalMargin(_ horizontalMargin: Double) async {
        var appearance = readingAppearance
        appearance.horizontalMargin = min(
            max(horizontalMargin, ReadingAppearance.minimumHorizontalMargin),
            ReadingAppearance.maximumHorizontalMargin
        )
        await updateReadingAppearance(appearance)
    }

    func createHighlight(color: HighlightColorTag) async -> Highlight? {
        guard let selectionRenderer = renderer as? any TextSelectionProviding else {
            return nil
        }
        do {
            guard let anchor = try await selectionRenderer.selectedTextHighlightAnchor() else {
                return nil
            }
            return await createHighlight(anchor: anchor, color: color)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func beginPageNote() {
        guard let locator = renderer.currentLocator else {
            return
        }
        noteEditorState = NoteEditorState(anchor: ReadingNoteAnchor(pageLocator: locator))
    }

    func saveNote(body: String, color: HighlightColorTag) async {
        guard let noteEditorState,
              let modelContext else {
            return
        }
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            errorMessage = "A note cannot be empty."
            return
        }

        do {
            if let note = noteEditorState.existingNote {
                note.body = trimmedBody
                note.colorTag = color.rawValue
                note.dateModified = .now
            } else {
                let note = ReadingNote(
                    anchorData: try JSONEncoder().encode(noteEditorState.anchor),
                    selectedText: noteEditorState.selectedText,
                    body: trimmedBody,
                    colorTag: color.rawValue,
                    book: book
                )
                modelContext.insert(note)
            }
            try modelContext.save()
            self.noteEditorState = nil
            await renderer.renderNotes(book.notes)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelNoteEditing() {
        noteEditorState = nil
    }

    func navigateToHighlight(_ highlight: Highlight) async {
        do {
            let anchor = try JSONDecoder().decode(TextHighlightAnchor.self, from: highlight.locatorData)
            try await renderer.navigate(to: anchor)
            currentLocator = renderer.currentLocator
            persistCurrentLocator()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func close() async {
        noteEditorState = nil
        persistCurrentLocator()
        await renderer.close()
        privateBookSessionService.closeSession()
        currentLocator = nil
    }

    private func updateReadingAppearance(_ appearance: ReadingAppearance) async {
        do {
            try await renderer.updateReadingAppearance(appearance)
            readingAppearance = appearance
            currentLocator = renderer.currentLocator
            persistCurrentLocator()
            await renderer.renderHighlights(book.highlights)
            await renderer.renderNotes(book.notes)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func navigate(_ operation: () async throws -> Bool) async -> Bool {
        do {
            let didNavigate = try await operation()
            currentLocator = renderer.currentLocator
            if didNavigate {
                persistCurrentLocator()
                await renderer.renderNotes(book.notes)
            }
            errorMessage = nil
            return didNavigate
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func createHighlight(
        anchor: TextHighlightAnchor,
        color: HighlightColorTag
    ) async -> Highlight? {
        guard let modelContext else {
            return nil
        }
        do {
            let highlight = Highlight(
                locatorData: try JSONEncoder().encode(anchor),
                selectedText: anchor.quote.exact,
                colorTag: color.rawValue,
                book: book
            )
            modelContext.insert(highlight)
            try modelContext.save()
            await renderer.renderHighlights(book.highlights)
            errorMessage = nil
            return highlight
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func handleAnnotationAction(_ action: ReaderAnnotationAction) {
        switch action {
        case let .createHighlight(anchor, color):
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                _ = await self.createHighlight(anchor: anchor, color: color)
            }
        case let .createNote(anchor):
            noteEditorState = NoteEditorState(anchor: ReadingNoteAnchor(textSelection: anchor))
        case let .createPageNote(locator):
            noteEditorState = NoteEditorState(anchor: ReadingNoteAnchor(pageLocator: locator))
        }
    }

    private func openNote(id: UUID) {
        guard let note = book.notes.first(where: { $0.id == id }),
              let anchor = try? JSONDecoder().decode(ReadingNoteAnchor.self, from: note.anchorData) else {
            return
        }
        noteEditorState = NoteEditorState(note: note, anchor: anchor)
    }

    private func storedLocator() -> BookLocator? {
        guard let locatorData = book.readingProgress?.locatorData,
              let locator = try? JSONDecoder().decode(BookLocator.self, from: locatorData),
              locator.format == renderer.supportedFormat else {
            return nil
        }
        return locator
    }

    private func persistCurrentLocator() {
        guard let currentLocator, let modelContext else {
            return
        }

        do {
            let locatorData = try JSONEncoder().encode(currentLocator)
            let percentComplete = max(0, min(1, renderer.readingProgressFraction))
            if let readingProgress = book.readingProgress {
                readingProgress.locatorData = locatorData
                readingProgress.lastReadDate = .now
                readingProgress.percentComplete = percentComplete
            } else {
                let readingProgress = ReadingProgress(
                    locatorData: locatorData,
                    lastReadDate: .now,
                    percentComplete: percentComplete,
                    book: book
                )
                modelContext.insert(readingProgress)
            }
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
