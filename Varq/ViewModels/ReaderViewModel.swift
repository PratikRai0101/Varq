import AppKit
import Foundation
import Observation
import SwiftData

struct GeneratedReadingAidResult: Identifiable, Equatable {
    let id = UUID()
    let kind: ReadingAidKind
    let text: String
    let noteAnchor: ReadingNoteAnchor
}

@MainActor
@Observable
final class ReaderViewModel {
    private let renderer: any BookRenderer
    private let book: Book
    private let bookURL: URL
    private let privateBookSessionService: PrivateBookSessionService
    private let aiAssistantService: AIAssistantService
    private let intelligenceConsentService: ReadingIntelligenceConsentService
    private var pendingReadingAidKind: ReadingAidKind?
    private var isChapterRecapPendingConsent = false
    private var modelContext: ModelContext?

    private(set) var currentLocator: BookLocator?
    private(set) var tableOfContents: [ReaderTableOfContentsEntry] = []
    private(set) var readingAppearance: ReadingAppearance
    private(set) var noteEditorState: NoteEditorState?
    private(set) var generatedReadingAid: GeneratedReadingAidResult?
    private(set) var intelligenceUnavailableReason: AIAssistantUnavailableReason?
    private(set) var isPrivateBookIntelligenceConsentPresented = false
    private(set) var isGeneratingReadingAid = false
    private(set) var errorMessage: String?
    var rendererView: NSView { renderer.view }
    var highlightedBook: Book { book }
    var supportsComicControls: Bool { renderer.supportedFormat == .cbz }
    var supportsEpubLayoutControls: Bool { renderer.supportedFormat == .epub }
    var supportsTextHighlights: Bool { renderer is any TextSelectionProviding }

    convenience init(book: Book, bookURL: URL, renderer: some BookRenderer) {
        self.init(
            book: book,
            bookURL: bookURL,
            renderer: renderer,
            settingsStore: UserDefaultsAppSettingsStore(),
            privateBookSessionService: PrivateBookSessionService(),
            aiAssistantService: AIAssistantService(),
            intelligenceConsentService: ReadingIntelligenceConsentService()
        )
    }

    convenience init(
        book: Book,
        bookURL: URL,
        renderer: some BookRenderer,
        settingsStore: any AppSettingsStoring,
        privateBookSessionService: PrivateBookSessionService,
        aiAssistantService: AIAssistantService = AIAssistantService(),
        intelligenceConsentService: ReadingIntelligenceConsentService? = nil
    ) {
        self.init(
            book: book,
            bookURL: bookURL,
            renderer: renderer,
            initialReadingAppearance: settingsStore.load().defaultReadingAppearance,
            privateBookSessionService: privateBookSessionService,
            aiAssistantService: aiAssistantService,
            intelligenceConsentService: intelligenceConsentService ?? ReadingIntelligenceConsentService()
        )
    }

    init(
        book: Book,
        bookURL: URL,
        renderer: some BookRenderer,
        initialReadingAppearance: ReadingAppearance,
        privateBookSessionService: PrivateBookSessionService,
        aiAssistantService: AIAssistantService = AIAssistantService(),
        intelligenceConsentService: ReadingIntelligenceConsentService? = nil
    ) {
        self.book = book
        self.bookURL = bookURL
        self.renderer = renderer
        self.readingAppearance = initialReadingAppearance
        self.privateBookSessionService = privateBookSessionService
        self.aiAssistantService = aiAssistantService
        self.intelligenceConsentService = intelligenceConsentService ?? ReadingIntelligenceConsentService()

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
            try await renderer.updateReadingAppearance(readingAppearance)
            currentLocator = renderer.currentLocator
            persistCurrentLocator()
            await renderer.renderHighlights(book.highlights)
            await renderer.renderNotes(book.notes)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadTableOfContents() async {
        guard let contentsProvider = renderer as? any TableOfContentsProviding else {
            return
        }
        do {
            tableOfContents = try await contentsProvider.tableOfContents()
        } catch {
            errorMessage = "Varq could not load this book’s contents."
        }
    }

    func navigateToTableOfContentsEntry(_ entry: ReaderTableOfContentsEntry) async {
        do {
            try await renderer.go(to: entry.locator)
            currentLocator = renderer.currentLocator
            persistCurrentLocator()
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

    var localIntelligenceAvailability: AIAssistantAvailability {
        aiAssistantService.availability
    }

    func presentIntelligenceUnavailableMessage() {
        guard case .unavailable(let reason) = localIntelligenceAvailability else {
            return
        }
        intelligenceUnavailableReason = reason
    }

    func dismissIntelligenceUnavailableMessage() {
        intelligenceUnavailableReason = nil
    }

    func requestChapterRecap() async {
        guard case .allowed = intelligenceConsentService.access(for: book) else {
            isChapterRecapPendingConsent = true
            isPrivateBookIntelligenceConsentPresented = true
            return
        }
        await generateChapterRecap()
    }

    func requestReadingAid(_ kind: ReadingAidKind) async {
        guard case .allowed = intelligenceConsentService.access(for: book) else {
            pendingReadingAidKind = kind
            isPrivateBookIntelligenceConsentPresented = true
            return
        }
        await generateReadingAid(kind)
    }

    func grantPrivateBookIntelligenceConsent() async {
        intelligenceConsentService.grantLocalIntelligenceConsent(for: book)
        isPrivateBookIntelligenceConsentPresented = false
        guard let pendingReadingAidKind else {
            return
        }
        self.pendingReadingAidKind = nil
        if isChapterRecapPendingConsent {
            isChapterRecapPendingConsent = false
            await generateChapterRecap()
        } else {
            await generateReadingAid(pendingReadingAidKind)
        }
    }

    func cancelPrivateBookIntelligenceConsent() {
        pendingReadingAidKind = nil
        isChapterRecapPendingConsent = false
        isPrivateBookIntelligenceConsentPresented = false
    }

    func dismissGeneratedReadingAid() {
        generatedReadingAid = nil
    }

    func saveGeneratedReadingAidAsNote() {
        guard let generatedReadingAid else {
            return
        }
        noteEditorState = NoteEditorState(
            anchor: generatedReadingAid.noteAnchor,
            initialBody: generatedReadingAid.text
        )
        self.generatedReadingAid = nil
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

    func deleteNote(_ note: ReadingNote) async {
        guard let modelContext else {
            return
        }
        let remainingNotes = book.notes.filter { $0.id != note.id }
        do {
            modelContext.delete(note)
            try modelContext.save()
            noteEditorState = nil
            await renderer.renderNotes(remainingNotes)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteHighlight(_ highlight: Highlight) async -> Bool {
        guard let modelContext else {
            return false
        }
        let remainingHighlights = book.highlights.filter { $0.id != highlight.id }
        do {
            modelContext.delete(highlight)
            try modelContext.save()
            await renderer.renderHighlights(remainingHighlights)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
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

    private func generateChapterRecap() async {
        guard let chapterProvider = renderer as? any ChapterTextProviding else {
            errorMessage = "Chapter recaps are available for EPUB books."
            return
        }
        do {
            guard let text = try await chapterProvider.currentChapterText() else {
                errorMessage = "Varq could not read this chapter."
                return
            }
            isGeneratingReadingAid = true
            defer { isGeneratingReadingAid = false }
            let aid = try await aiAssistantService.generateChapterRecap(from: text)
            guard let locator = renderer.currentLocator else {
                return
            }
            generatedReadingAid = GeneratedReadingAidResult(
                kind: .chapterRecap,
                text: aid.text,
                noteAnchor: ReadingNoteAnchor(pageLocator: locator)
            )
            errorMessage = nil
        } catch is BoundedReadingContextError {
            errorMessage = "Varq could not prepare this chapter recap."
        } catch let error as AIAssistantServiceError {
            if case .unavailable(let reason) = error {
                intelligenceUnavailableReason = reason
            }
        } catch {
            errorMessage = "Varq could not recap this chapter."
        }
    }

    private func generateReadingAid(_ kind: ReadingAidKind) async {
        guard let selectionRenderer = renderer as? any TextSelectionProviding else {
            errorMessage = "Reading aids are unavailable for this book format."
            return
        }

        do {
            guard let anchor = try await selectionRenderer.selectedTextHighlightAnchor() else {
                errorMessage = "Select text before using a reading aid."
                return
            }
            let context = try BoundedReadingContext(selectedText: anchor.quote.exact)
            isGeneratingReadingAid = true
            defer { isGeneratingReadingAid = false }
            let aid = try await aiAssistantService.generate(kind, using: context)
            generatedReadingAid = GeneratedReadingAidResult(
                kind: kind,
                text: aid.text,
                noteAnchor: ReadingNoteAnchor(textSelection: anchor)
            )
            errorMessage = nil
        } catch let error as AIAssistantServiceError {
            switch error {
            case let .unavailable(reason):
                errorMessage = intelligenceUnavailableMessage(for: reason)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func intelligenceUnavailableMessage(for reason: AIAssistantUnavailableReason) -> String {
        switch reason {
        case .unsupportedOS:
            "Reading aids require macOS 26 or later."
        case .deviceNotEligible:
            "Reading aids require a Mac that supports Apple Intelligence."
        case .appleIntelligenceDisabled:
            "Turn on Apple Intelligence in System Settings to use reading aids."
        case .modelNotReady:
            "Apple Intelligence is still preparing. Try again shortly."
        case .unavailable:
            "Reading aids are unavailable right now."
        }
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
        case let .removeHighlight(anchor):
            Task { @MainActor [weak self] in
                await self?.removeHighlight(matching: anchor)
            }
        case let .createNote(anchor):
            noteEditorState = NoteEditorState(anchor: ReadingNoteAnchor(textSelection: anchor))
        case let .removeNote(anchor):
            Task { @MainActor [weak self] in
                await self?.removeNote(matching: anchor)
            }
        case let .createPageNote(locator):
            noteEditorState = NoteEditorState(anchor: ReadingNoteAnchor(pageLocator: locator))
        case let .removePageNote(locator):
            Task { @MainActor [weak self] in
                await self?.removePageNote(at: locator)
            }
        }
    }

    private func removeNote(matching selection: TextHighlightAnchor) async {
        for note in book.notes {
            guard let noteAnchor = try? JSONDecoder().decode(ReadingNoteAnchor.self, from: note.anchorData),
                  let textSelection = noteAnchor.textSelection,
                  anchorsOverlap(textSelection, selection) else {
                continue
            }
            await deleteNote(note)
            return
        }
    }

    private func removePageNote(at locator: BookLocator) async {
        for note in book.notes {
            guard let noteAnchor = try? JSONDecoder().decode(ReadingNoteAnchor.self, from: note.anchorData),
                  noteAnchor.kind == .pageLocation,
                  sameReaderLocation(noteAnchor.locator, locator) else {
                continue
            }
            await deleteNote(note)
            return
        }
    }

    private func removeHighlight(matching selection: TextHighlightAnchor) async {
        for highlight in book.highlights {
            guard let anchor = try? JSONDecoder().decode(TextHighlightAnchor.self, from: highlight.locatorData),
                  anchorsOverlap(anchor, selection) else {
                continue
            }
            _ = await deleteHighlight(highlight)
            return
        }
    }

    private func anchorsOverlap(_ first: TextHighlightAnchor, _ second: TextHighlightAnchor) -> Bool {
        guard sameResource(first.locator, second.locator) else {
            return false
        }
        if first == second {
            return true
        }
        guard first.precision == .exactTextRange,
              second.precision == .exactTextRange,
              let firstStart = first.startOffset,
              let firstEnd = first.endOffset,
              let secondStart = second.startOffset,
              let secondEnd = second.endOffset else {
            return false
        }
        return firstStart < secondEnd && secondStart < firstEnd
    }

    private func sameReaderLocation(_ first: BookLocator, _ second: BookLocator) -> Bool {
        sameResource(first, second) && abs(first.progression - second.progression) < 0.03
    }

    private func sameResource(_ first: BookLocator, _ second: BookLocator) -> Bool {
        first.format == second.format &&
            first.spineIndex == second.spineIndex &&
            first.resourceHref == second.resourceHref
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
