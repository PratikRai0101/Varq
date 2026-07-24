import Foundation

enum ExportServiceError: Error, Equatable {
    case privateBookExportConfirmationRequired
}

enum MarkdownExportProfile: Equatable, Sendable {
    case obsidian
    case notion
}

struct ExportService {
    func markdown(
        for book: Book,
        highlights: [Highlight],
        privateBookExportConfirmed: Bool = false
    ) throws -> String {
        try markdown(
            for: book,
            highlights: highlights,
            notes: book.notes,
            privateBookExportConfirmed: privateBookExportConfirmed
        )
    }

    func markdown(
        for book: Book,
        highlights: [Highlight],
        notes: [ReadingNote],
        profile: MarkdownExportProfile,
        privateBookExportConfirmed: Bool = false
    ) throws -> String {
        switch profile {
        case .obsidian:
            try markdown(for: book, highlights: highlights, notes: notes, privateBookExportConfirmed: privateBookExportConfirmed)
        case .notion:
            try notionMarkdown(for: book, highlights: highlights, notes: notes, privateBookExportConfirmed: privateBookExportConfirmed)
        }
    }

    func markdown(
        for book: Book,
        highlights: [Highlight],
        notes: [ReadingNote],
        privateBookExportConfirmed: Bool = false
    ) throws -> String {
        try requirePrivateBookExportConfirmation(for: book, confirmed: privateBookExportConfirmed)
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

    /// Portable Markdown intended for Notion's Markdown importer. It deliberately omits YAML and wikilinks.
    private func notionMarkdown(
        for book: Book,
        highlights: [Highlight],
        notes: [ReadingNote],
        privateBookExportConfirmed: Bool
    ) throws -> String {
        try requirePrivateBookExportConfirmation(for: book, confirmed: privateBookExportConfirmed)
        var lines = ["# \(book.title)", "", "**Author:** \(book.author)", "", "## Highlights", ""]
        for highlight in highlights.sorted(by: { $0.dateCreated < $1.dateCreated }) {
            lines.append("> \(highlight.selectedText.replacingOccurrences(of: "\n", with: "\n> "))")
            if let note = highlight.note, !note.isEmpty {
                lines.append("")
                lines.append("**Note:** \(note)")
            }
            lines.append("")
        }
        if !notes.isEmpty {
            lines.append("## Notes")
            lines.append("")
            for note in notes.sorted(by: { $0.dateCreated < $1.dateCreated }) {
                lines.append("### Note")
                if let selectedText = note.selectedText, !selectedText.isEmpty {
                    lines.append("")
                    lines.append("> \(selectedText.replacingOccurrences(of: "\n", with: "\n> "))")
                }
                lines.append("")
                lines.append(note.body)
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    func jsonData(
        for book: Book,
        highlights: [Highlight],
        privateBookExportConfirmed: Bool = false
    ) throws -> Data {
        try jsonData(
            for: book,
            highlights: highlights,
            notes: book.notes,
            privateBookExportConfirmed: privateBookExportConfirmed
        )
    }

    func jsonData(
        for book: Book,
        highlights: [Highlight],
        notes: [ReadingNote],
        privateBookExportConfirmed: Bool = false
    ) throws -> Data {
        try requirePrivateBookExportConfirmation(for: book, confirmed: privateBookExportConfirmed)
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

    private func requirePrivateBookExportConfirmation(for book: Book, confirmed: Bool) throws {
        guard !book.isPrivate || confirmed else {
            throw ExportServiceError.privateBookExportConfirmationRequired
        }
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
