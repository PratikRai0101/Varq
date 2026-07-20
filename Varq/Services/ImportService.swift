import Foundation

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
}
