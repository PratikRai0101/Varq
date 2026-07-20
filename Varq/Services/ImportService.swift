import AppKit
import Foundation
import PDFKit

struct ImportedBook: Equatable, Sendable {
    let title: String
    let author: String
    let coverImageData: Data?
    let libraryRelativePath: String
    let format: BookFormat
}

enum ImportServiceError: Error {
    case unsupportedFormat
}

actor ImportService {
    private let libraryDirectory: URL
    private let epubParser: EpubParserService
    private let fileManager: FileManager

    init(
        libraryDirectory: URL,
        epubParser: EpubParserService = EpubParserService(),
        fileManager: FileManager = .default
    ) {
        self.libraryDirectory = libraryDirectory
        self.epubParser = epubParser
        self.fileManager = fileManager
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
        try fileManager.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)

        let fileName = UUID().uuidString + "." + BookFormat.epub.rawValue
        let destinationURL = libraryDirectory.appendingPathComponent(fileName)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        return ImportedBook(
            title: metadata.title,
            author: metadata.author,
            coverImageData: metadata.coverImageData,
            libraryRelativePath: fileName,
            format: .epub
        )
    }

    func importPDF(at sourceURL: URL) throws -> ImportedBook {
        guard sourceURL.pathExtension.lowercased() == BookFormat.pdf.rawValue else {
            throw ImportServiceError.unsupportedFormat
        }

        let accessedSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let document = PDFDocument(url: sourceURL) else {
            throw ImportServiceError.unsupportedFormat
        }
        try fileManager.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)

        let fileName = UUID().uuidString + "." + BookFormat.pdf.rawValue
        let destinationURL = libraryDirectory.appendingPathComponent(fileName)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let attributes = document.documentAttributes
        return ImportedBook(
            title: attributes?[PDFDocumentAttribute.titleAttribute] as? String ?? sourceURL.deletingPathExtension().lastPathComponent,
            author: attributes?[PDFDocumentAttribute.authorAttribute] as? String ?? "Unknown Author",
            coverImageData: coverImageData(from: document),
            libraryRelativePath: fileName,
            format: .pdf
        )
    }

    private func coverImageData(from document: PDFDocument) -> Data? {
        guard let page = document.page(at: 0),
              let tiffData = page.thumbnail(of: CGSize(width: 300, height: 400), for: .mediaBox).tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
