import Foundation
import ZIPFoundation

struct ImportedBook: Equatable, Sendable {
    let title: String
    let author: String
    let coverImageData: Data?
    let libraryRelativePath: String
    let contentHash: String
    let format: BookFormat
}

enum ImportServiceError: Error {
    case unsupportedFormat
}

actor ImportService {
    private let libraryDirectory: URL
    private let epubParser: EpubParserService
    private let pdfParser: PDFParserService
    private let fileManager: FileManager
    private let contentHashService: ContentHashService

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
    }

    func importEpub(at sourceURL: URL) async throws -> ImportedBook {
        guard sourceURL.pathExtension.lowercased() == BookFormat.epub.rawValue else {
            throw ImportServiceError.unsupportedFormat
        }

        let accessedSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let metadata = try await epubParser.parse(at: sourceURL)
        let contentHash = try await contentHashService.hash(of: sourceURL)
        try fileManager.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)

        let fileName = UUID().uuidString + "." + BookFormat.epub.rawValue
        let destinationURL = libraryDirectory.appendingPathComponent(fileName)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        return ImportedBook(
            title: metadata.title,
            author: metadata.author,
            coverImageData: metadata.coverImageData,
            libraryRelativePath: fileName,
            contentHash: contentHash,
            format: .epub
        )
    }

    func importPDF(at sourceURL: URL) async throws -> ImportedBook {
        guard sourceURL.pathExtension.lowercased() == BookFormat.pdf.rawValue else {
            throw ImportServiceError.unsupportedFormat
        }

        let accessedSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let metadata: PDFMetadata
        do {
            metadata = try await pdfParser.parse(at: sourceURL)
        } catch PDFParserError.invalidDocument {
            throw ImportServiceError.unsupportedFormat
        }
        try fileManager.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)

        let fileName = UUID().uuidString + "." + BookFormat.pdf.rawValue
        let destinationURL = libraryDirectory.appendingPathComponent(fileName)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let contentHash = try await contentHashService.hash(of: sourceURL)
        return ImportedBook(
            title: metadata.title,
            author: metadata.author,
            coverImageData: metadata.coverImageData,
            libraryRelativePath: fileName,
            contentHash: contentHash,
            format: .pdf
        )
    }

    func discardImportedBook(at relativePath: String) throws {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        guard fileName == relativePath else {
            throw ImportServiceError.unsupportedFormat
        }

        let importedFileURL = libraryDirectory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: importedFileURL.path) else {
            return
        }
        try fileManager.removeItem(at: importedFileURL)
    }

    func importCBZ(at sourceURL: URL) async throws -> ImportedBook {
        guard sourceURL.pathExtension.lowercased() == BookFormat.cbz.rawValue else {
            throw ImportServiceError.unsupportedFormat
        }
        let accessedSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let archive = try Archive(url: sourceURL, accessMode: .read)
        let imageExtensions: Set<String> = ["avif", "gif", "jpeg", "jpg", "png", "webp"]
        guard let coverEntry = archive.sorted(by: { $0.path < $1.path }).first(where: {
            imageExtensions.contains(URL(fileURLWithPath: $0.path).pathExtension.lowercased())
        }) else {
            throw ImportServiceError.unsupportedFormat
        }
        var coverImageData = Data()
        try archive.extract(coverEntry) { coverImageData.append($0) }

        let contentHash = try await contentHashService.hash(of: sourceURL)
        try fileManager.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        let fileName = UUID().uuidString + "." + BookFormat.cbz.rawValue
        try fileManager.copyItem(at: sourceURL, to: libraryDirectory.appendingPathComponent(fileName))

        return ImportedBook(
            title: sourceURL.deletingPathExtension().lastPathComponent,
            author: "Unknown Author",
            coverImageData: coverImageData,
            libraryRelativePath: fileName,
            contentHash: contentHash,
            format: .cbz
        )
    }

}
