import Foundation
import PDFKit
import Testing
@testable import Varq

struct PDFParserServiceTests {
    @Test(arguments: [false, true])
    func readsEmbeddedMetadataAndRetainsTheExistingImportSanitizationPolicy(garbage: Bool) async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/minimal.pdf")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let document = try #require(PDFDocument(url: fixture))
        document.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: garbage ? "Microsoft Word - draft" : "  Warm Pages  ",
            PDFDocumentAttribute.authorAttribute: garbage ? "Admin" : "  Varq Tests  "
        ]
        let source = directory.appendingPathComponent("source.pdf")
        #expect(document.write(to: source))

        let metadata = try await PDFParserService().parse(at: source, fallbackTitle: "Saved title")

        #expect(metadata.title == (garbage ? "Saved title" : "Warm Pages"))
        #expect(metadata.author == (garbage ? "Unknown Author" : "Varq Tests"))
        #expect(metadata.coverImageData?.isEmpty == false)
    }

    @Test func rejectsInvalidPdfData() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: source) }
        try Data("not a PDF".utf8).write(to: source)
        await #expect(throws: PDFParserError.self) {
            _ = try await PDFParserService().parse(at: source)
        }
    }

    @Test func parsesARealPdfAndUsesTheSuppliedTitleWhenMetadataIsAbsent() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/minimal.pdf")

        let metadata = try await PDFParserService().parse(at: fixture, fallbackTitle: "My saved title")

        #expect(metadata.title == "My saved title")
        #expect(metadata.author == "Unknown Author")
        #expect(metadata.coverImageData?.isEmpty == false)
    }
}
