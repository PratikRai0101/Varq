import AppKit
import Foundation
import PDFKit

struct PDFMetadata: Equatable, Sendable {
    let title: String
    let author: String
    let coverImageData: Data?
}

actor PDFParserService {
    func parse(at fileURL: URL, fallbackTitle: String? = nil) throws -> PDFMetadata {
        guard let document = PDFDocument(url: fileURL) else {
            throw PDFParserError.invalidDocument
        }
        let attributes = document.documentAttributes
        return PDFMetadata(
            title: sanitize(
                attributes?[PDFDocumentAttribute.titleAttribute] as? String,
                fallback: fallbackTitle ?? fileURL.deletingPathExtension().lastPathComponent
            ),
            author: sanitize(attributes?[PDFDocumentAttribute.authorAttribute] as? String, fallback: "Unknown Author"),
            coverImageData: coverImageData(from: document)
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

    // Keep import and refresh consistent with the existing PDF import policy.
    private func sanitize(_ value: String?, fallback: String) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return fallback
        }
        let lowercased = value.lowercased()
        let garbagePatterns = [
            "microsoft word", "untitled", "document", "preferred customer",
            "unknown", "user", "admin", "author", "no author",
            "created by", "pdf creator", "acrobat", "pdf generator"
        ]
        for pattern in garbagePatterns {
            if lowercased.contains(pattern) { return fallback }
        }
        if value.count > 80, lowercased.contains(" - ") || lowercased.contains("_") {
            return fallback
        }
        return value
    }
}

enum PDFParserError: LocalizedError {
    case invalidDocument

    var errorDescription: String? { "Varq could not read this PDF's metadata." }
}
