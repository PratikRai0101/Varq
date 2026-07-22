import Foundation

struct ExportService {
    func markdown(for book: Book, highlights: [Highlight]) -> String {
        markdown(for: book, highlights: highlights, notes: book.notes)
    }

    func markdown(for book: Book, highlights: [Highlight], notes: [ReadingNote]) -> String {
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

        for note in notes.sorted(by: { $0.dateCreated < $1.dateCreated }) {
            lines.append("## Note")
            if let selectedText = note.selectedText, !selectedText.isEmpty {
                lines.append("> \(selectedText.replacingOccurrences(of: "\n", with: "\n> "))")
            } else {
                lines.append("> Page note")
            }
            lines.append("")
            lines.append(note.body)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    func jsonData(for book: Book, highlights: [Highlight]) throws -> Data {
        try jsonData(for: book, highlights: highlights, notes: book.notes)
    }

    func jsonData(for book: Book, highlights: [Highlight], notes: [ReadingNote]) throws -> Data {
        let document = HighlightExportDocument(
            title: book.title,
            author: book.author,
            highlights: highlights.sorted(by: { $0.dateCreated < $1.dateCreated }).map {
                HighlightExportItem(text: $0.selectedText, note: $0.note, color: $0.colorTag, createdAt: $0.dateCreated)
            },
            notes: notes.sorted(by: { $0.dateCreated < $1.dateCreated }).map {
                ReadingNoteExportItem(
                    text: $0.selectedText,
                    body: $0.body,
                    color: $0.colorTag,
                    createdAt: $0.dateCreated,
                    modifiedAt: $0.dateModified
                )
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
        let notes: [ReadingNoteExportItem]
    }

    private struct HighlightExportItem: Encodable {
        let text: String
        let note: String?
        let color: String
        let createdAt: Date
    }

    private struct ReadingNoteExportItem: Encodable {
        let text: String?
        let body: String
        let color: String
        let createdAt: Date
        let modifiedAt: Date
    }
}
