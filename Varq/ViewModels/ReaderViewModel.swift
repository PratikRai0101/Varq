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
    private var modelContext: ModelContext?

    private(set) var currentLocator: BookLocator?
    private(set) var readingAppearance = ReadingAppearance()
    private(set) var errorMessage: String?
    var rendererView: NSView { renderer.view }

    init(book: Book, bookURL: URL, renderer: some BookRenderer) {
        self.book = book
        self.bookURL = bookURL
        self.renderer = renderer
    }

    func configurePersistence(using modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func open(at locator: BookLocator? = nil) async {
        do {
            let initialLocator = locator ?? storedLocator()
            try await renderer.open(bookURL: bookURL, at: initialLocator)
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

    func close() async {
        persistCurrentLocator()
        await renderer.close()
        currentLocator = nil
    }

    private func updateReadingAppearance(_ appearance: ReadingAppearance) async {
        do {
            try await renderer.updateReadingAppearance(appearance)
            readingAppearance = appearance
            currentLocator = renderer.currentLocator
            persistCurrentLocator()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func navigate(_ operation: () async throws -> Bool) async {
        do {
            _ = try await operation()
            currentLocator = renderer.currentLocator
            persistCurrentLocator()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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
            if let readingProgress = book.readingProgress {
                readingProgress.locatorData = locatorData
                readingProgress.lastReadDate = .now
            } else {
                let readingProgress = ReadingProgress(locatorData: locatorData, book: book)
                modelContext.insert(readingProgress)
            }
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
