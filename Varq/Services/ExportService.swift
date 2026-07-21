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

    private func yamlString(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
