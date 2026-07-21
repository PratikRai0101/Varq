import AppKit
import Observation
import SwiftData
import UniformTypeIdentifiers

struct ImportFileError: Identifiable, Equatable {
    let id = UUID()
    let fileName: String
    let message: String
}

private enum ImportViewModelError: LocalizedError {
    case duplicateBook

    var errorDescription: String? {
        switch self {
        case .duplicateBook:
            "This book is already in your library."
        }
    }
}

@MainActor
@Observable
final class ImportViewModel {
    static let supportedContentTypes = [UTType.pdf] + ["epub", "cbz"].compactMap { UTType(filenameExtension: $0) }
    static let supportedContentTypeIdentifiers = supportedContentTypes.map(\.identifier)

    private(set) var importErrors: [ImportFileError] = []
    private let importer: ImportService
    private let duplicateDetectionService: DuplicateDetectionService

    init(
        importer: ImportService,
        duplicateDetectionService: DuplicateDetectionService? = nil
    ) {
        self.importer = importer
        self.duplicateDetectionService = duplicateDetectionService ?? DuplicateDetectionService()
    }

    func dismissImportErrors() {
        importErrors = []
    }

    func chooseFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = Self.supportedContentTypes
        return panel.runModal() == .OK ? panel.urls : []
    }

    func importDroppedFiles(_ providers: [NSItemProvider], into context: ModelContext) async {
        var urls: [URL] = []
        for provider in providers {
            if let url = await provider.fileURL() {
                urls.append(url)
            }
        }
        await importFiles(urls, into: context)
    }

    func importFiles(_ urls: [URL], into context: ModelContext) async {
        importErrors = []

        for url in urls {
            do {
                let imported = try await importFile(at: url)
                let books = try context.fetch(FetchDescriptor<Book>())
                guard !duplicateDetectionService.hasDuplicate(contentHash: imported.contentHash, among: books) else {
                    try await importer.discardImportedBook(at: imported.libraryRelativePath)
                    throw ImportViewModelError.duplicateBook
                }

                let book = Book(
                    title: imported.title,
                    author: imported.author,
                    coverImageData: imported.coverImageData,
                    libraryRelativePath: imported.libraryRelativePath,
                    contentHash: imported.contentHash,
                    format: imported.format
                )
                context.insert(book)

                do {
                    try context.save()
                } catch {
                    context.delete(book)
                    try? context.save()
                    try? await importer.discardImportedBook(at: imported.libraryRelativePath)
                    throw error
                }
            } catch {
                importErrors.append(ImportFileError(fileName: url.lastPathComponent, message: error.localizedDescription))
            }
        }
    }

    private func importFile(at url: URL) async throws -> ImportedBook {
        switch url.pathExtension.lowercased() {
        case BookFormat.epub.rawValue: try await importer.importEpub(at: url)
        case BookFormat.pdf.rawValue: try await importer.importPDF(at: url)
        case BookFormat.cbz.rawValue: try await importer.importCBZ(at: url)
        default: throw ImportServiceError.unsupportedFormat
        }
    }
}

private extension NSItemProvider {
    func fileURL() async -> URL? {
        await withCheckedContinuation { continuation in
            loadObject(ofClass: NSURL.self) { object, _ in
                let url = (object as? NSURL).map { $0 as URL }
                continuation.resume(returning: url)
            }
        }
    }
}
