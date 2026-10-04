import Foundation
import ZIPFoundation

nonisolated struct ImportedBook: Equatable, Sendable {
    let id: UUID
    let title: String
    let author: String
    let coverImageData: Data?
    let libraryRelativePath: String
    let contentHash: String
    let format: BookFormat
}

enum ImportServiceError: LocalizedError {
    case unsupportedFormat
    var errorDescription: String? { "This file is not a readable EPUB, PDF, or CBZ book. Unsupported formats cannot be imported." }
}

actor ImportService {
    private let libraryDirectory: URL
    private let epubParser: EpubParserService
    private let pdfParser: PDFParserService
    private let fileManager: FileManager
    private let contentHashService: ContentHashService
    private let journal: ImportRecoveryJournalService

    init(
        libraryDirectory: URL,
        epubParser: EpubParserService = EpubParserService(),
        pdfParser: PDFParserService = PDFParserService(),
        contentHashService: ContentHashService = ContentHashService(),
        fileManager: FileManager = .default
    ) {
        self.libraryDirectory = libraryDirectory
        self.epubParser = epubParser
        self.pdfParser = pdfParser
        self.fileManager = fileManager
        self.contentHashService = contentHashService
        self.journal = ImportRecoveryJournalService(fileManager: fileManager)
    }

    func importEpub(at sourceURL: URL) async throws -> ImportedBook { try await importBook(at: sourceURL, format: .epub) }
    func importPDF(at sourceURL: URL) async throws -> ImportedBook { try await importBook(at: sourceURL, format: .pdf) }
    func importCBZ(at sourceURL: URL) async throws -> ImportedBook { try await importBook(at: sourceURL, format: .cbz) }

    /// Only after the caller's database insertion committed.
    func completeImportedBook(_ book: ImportedBook) throws {
        let record = try journal.record(for: book.libraryRelativePath, in: libraryDirectory)
        guard record.bookID == book.id, record.contentHash == book.contentHash else { throw ImportRecoveryError.invalidJournal }
        try journal.settle(record, keepingFile: true, in: libraryDirectory)
    }

    /// Only for a duplicate or a failed, isolated database insertion.
    func discardImportedBook(at relativePath: String) throws {
        let record = try journal.record(for: relativePath, in: libraryDirectory)
        try journal.settle(record, keepingFile: false, in: libraryDirectory)
    }

    func hasPendingImports() throws -> Bool { try journal.hasPendingImports(in: libraryDirectory) }

    private func importBook(at sourceURL: URL, format: BookFormat) async throws -> ImportedBook {
        guard sourceURL.pathExtension.lowercased() == format.rawValue, [.epub, .pdf, .cbz].contains(format) else {
            throw ImportServiceError.unsupportedFormat
        }
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
        let hash = try await contentHashService.hash(of: sourceURL)
        // Write-ahead ownership metadata precedes the first managed-file byte.
        let record = try journal.begin(format: format, contentHash: hash, in: libraryDirectory)
        let destination = libraryDirectory.appendingPathComponent(record.fileName)
        do {
            try fileManager.copyItem(at: sourceURL, to: destination)
            try journal.verifyCopy(record, in: libraryDirectory)
            let title: String
            let author: String
            let cover: Data?
            let fallbackTitle = sourceURL.deletingPathExtension().lastPathComponent
            // Parse only the verified managed snapshot, never a separately changing original.
            switch format {
            case .epub:
                let metadata = try await epubParser.parse(at: destination, fallbackTitle: fallbackTitle)
                title = metadata.title; author = metadata.author; cover = metadata.coverImageData
            case .pdf:
                let metadata: PDFMetadata
                do { metadata = try await pdfParser.parse(at: destination, fallbackTitle: fallbackTitle) }
                catch PDFParserError.invalidDocument { throw ImportServiceError.unsupportedFormat }
                title = metadata.title; author = metadata.author; cover = metadata.coverImageData
            case .cbz:
                let archive = try Archive(url: destination, accessMode: .read)
                let extensions: Set<String> = ["avif", "gif", "jpeg", "jpg", "png", "webp"]
                guard let entry = archive.sorted(by: { $0.path < $1.path }).first(where: {
                    extensions.contains(URL(fileURLWithPath: $0.path).pathExtension.lowercased())
                }) else { throw ImportServiceError.unsupportedFormat }
                var data = Data()
                try archive.extract(entry) { data.append($0) }
                title = fallbackTitle; author = "Unknown Author"; cover = data
            case .cbr: throw ImportServiceError.unsupportedFormat
            }
            return ImportedBook(id: record.bookID, title: title, author: author, coverImageData: cover,
                                libraryRelativePath: record.fileName, contentHash: hash, format: format)
        } catch {
            let operation = error
            do { try journal.settle(record, keepingFile: false, in: libraryDirectory) }
            catch { throw ImportRecoveryError.cleanupFailed(operation: operation, cleanup: error) }
            throw operation
        }
    }
}
