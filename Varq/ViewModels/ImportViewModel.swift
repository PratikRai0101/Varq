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
    case busy
    var errorDescription: String? {
        switch self {
        case .duplicateBook: "This book is already in your library."
        case .busy: "Another import is already in progress. Try again when it finishes."
        }
    }
}

@MainActor
@Observable
final class ImportViewModel {
    static let supportedContentTypes = [UTType.pdf] + ["epub", "cbz"].compactMap { UTType(filenameExtension: $0) }
    static let supportedContentTypeIdentifiers = supportedContentTypes.map(\.identifier)

    private(set) var importErrors: [ImportFileError] = []
    private(set) var isImporting = false
    private(set) var recoveryError: String?
    var isImportRecoveryRequired: Bool { recoveryError != nil }
    private let importer: ImportService
    private let duplicateDetectionService: DuplicateDetectionService
    private let folderImportService: FolderImportService
    private let saveChanges: (ModelContext) throws -> Void
    private let onRecoveryRequired: (String) -> Void

    init(
        importer: ImportService,
        duplicateDetectionService: DuplicateDetectionService? = nil,
        folderImportService: FolderImportService? = nil,
        saveChanges: @escaping (ModelContext) throws -> Void = { try $0.save() },
        onRecoveryRequired: @escaping (String) -> Void = { _ in }
    ) {
        self.importer = importer
        self.duplicateDetectionService = duplicateDetectionService ?? DuplicateDetectionService()
        self.folderImportService = folderImportService ?? FolderImportService()
        self.saveChanges = saveChanges
        self.onRecoveryRequired = onRecoveryRequired
    }

    func dismissImportErrors() { importErrors = [] }

    func chooseFiles(allowDirectories: Bool = false) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = !allowDirectories
        panel.canChooseFiles = !allowDirectories
        panel.canChooseDirectories = allowDirectories
        panel.allowedContentTypes = allowDirectories ? [.folder] : Self.supportedContentTypes
        return panel.runModal() == .OK ? panel.urls : []
    }

    func importDirectory(_ directoryURL: URL, into context: ModelContext) async {
        guard await beginBatch(using: context) else { return }
        defer { isImporting = false }
        do {
            try await folderImportService.withBooks(in: directoryURL) { discovery in
                await runImportFiles(discovery.files, into: context)
                importErrors.append(contentsOf: discovery.issues.map {
                    ImportFileError(fileName: $0.url.lastPathComponent, message: $0.message)
                })
            }
        } catch {
            importErrors.append(ImportFileError(fileName: directoryURL.lastPathComponent, message: error.localizedDescription))
        }
    }

    func importDroppedFiles(_ providers: [NSItemProvider], into context: ModelContext) async {
        guard await beginBatch(using: context) else { return }
        defer { isImporting = false }
        var urls: [URL] = []
        for provider in providers {
            if let url = await provider.fileURL() { urls.append(url) }
        }
        await runImportFiles(urls, into: context)
    }

    func importFiles(_ urls: [URL], into context: ModelContext) async {
        guard await beginBatch(using: context) else { return }
        defer { isImporting = false }
        await runImportFiles(urls, into: context)
    }

    private func beginBatch(using context: ModelContext) async -> Bool {
        guard !isImporting else {
            importErrors.append(ImportFileError(fileName: "Import", message: ImportViewModelError.busy.localizedDescription))
            return false
        }
        isImporting = true
        importErrors = []
        do {
            guard try await !importer.hasPendingImports() else { throw ImportRecoveryError.pendingChange }
            recoveryError = nil
            // Preserve edits before filesystem changes; never roll back the caller's context.
            if context.hasChanges { try saveChanges(context) }
            return true
        } catch {
            importErrors.append(ImportFileError(fileName: "Import", message: error.localizedDescription))
            await requireRecoveryIfPending(error.localizedDescription)
            isImporting = false
            return false
        }
    }

    private func runImportFiles(_ urls: [URL], into context: ModelContext) async {
        for url in urls {
            var imported: ImportedBook?
            var committed = false
            do {
                let copy = try await importFile(at: url)
                imported = copy
                let insertionContext = ModelContext(context.container)
                insertionContext.autosaveEnabled = false
                let books = try insertionContext.fetch(FetchDescriptor<Book>())
                guard !duplicateDetectionService.hasDuplicate(contentHash: copy.contentHash, among: books) else {
                    throw ImportViewModelError.duplicateBook
                }
                let book = Book(id: copy.id, title: copy.title, author: copy.author, coverImageData: copy.coverImageData,
                                libraryRelativePath: copy.libraryRelativePath, contentHash: copy.contentHash, format: copy.format)
                insertionContext.insert(book)
                try saveChanges(insertionContext)
                committed = true
                // Cleanup is outside persistence rollback: never abandon a committed copy.
                try await importer.completeImportedBook(copy)
            } catch {
                var message = error.localizedDescription
                if let imported, !committed {
                    do {
                        // A thrown save is not permission to delete a referenced file.
                        // Re-read committed state before abandoning any managed copy.
                        let persisted = ModelContext(context.container)
                        persisted.autosaveEnabled = false
                        let rows = try persisted.fetch(FetchDescriptor<Book>())
                        if rows.contains(where: { $0.id == imported.id || $0.libraryRelativePath == imported.libraryRelativePath }) {
                            message += " The committed database state must be reconciled before cleanup."
                        } else {
                            try await importer.discardImportedBook(at: imported.libraryRelativePath)
                        }
                    } catch { message += " Cleanup also failed: " + error.localizedDescription }
                } else if committed {
                    message = "The book was saved, but import cleanup is incomplete. " + message
                }
                importErrors.append(ImportFileError(fileName: url.lastPathComponent, message: message))
                await requireRecoveryIfPending(message)
                if isImportRecoveryRequired { break }
            }
        }
    }

    private func requireRecoveryIfPending(_ message: String) async {
        let pending: Bool
        do { pending = try await importer.hasPendingImports() }
        catch { pending = true }
        guard pending else { return }
        let diagnosis = "Library recovery is required. " + message
        recoveryError = diagnosis
        onRecoveryRequired(diagnosis)
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
