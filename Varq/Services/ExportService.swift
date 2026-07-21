import Foundation

struct ExportService {
    func markdown(for book: Book, highlights: [Highlight]) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = [
            "---",
            "title: \(yamlString(book.title))",
            "author: \(yamlString(book.author))",
            "exported_at: \(formatter.string(from: .now))",
            "---",
            ""
        ]

        for highlight in highlights.sorted(by: { $0.dateCreated < $1.dateCreated }) {
            lines.append("> \(highlight.selectedText.replacingOccurrences(of: "\n", with: "\n> "))")
            if let note = highlight.note, !note.isEmpty {
                lines.append("")
                lines.append("Note: \(note)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    func jsonData(for book: Book, highlights: [Highlight]) throws -> Data {
        let document = HighlightExportDocument(
            title: book.title,
            author: book.author,
            highlights: highlights.sorted(by: { $0.dateCreated < $1.dateCreated }).map {
                HighlightExportItem(text: $0.selectedText, note: $0.note, color: $0.colorTag, createdAt: $0.dateCreated)
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    private func yamlString(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private struct HighlightExportDocument: Encodable {
        let title: String
        let author: String
        let highlights: [HighlightExportItem]
    }

    private struct HighlightExportItem: Encodable {
        let text: String
        let note: String?
        let color: String
        let createdAt: Date
    }
}
