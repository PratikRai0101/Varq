import Foundation

nonisolated enum ObsidianVaultExportError: Error, Equatable, Sendable {
    case destinationIsNotDirectory
    case unmanagedFileConflict(String)
}

nonisolated struct ObsidianVaultExportReport: Equatable, Sendable {
    let exportedBookCount: Int
    let skippedPrivateBookCount: Int
}

/// Writes only Varq-owned Markdown below `Varq/` in a user-selected Obsidian vault.
nonisolated struct ObsidianVaultExportService {
    private static let managedMarker = "<!-- Varq-managed -->"

    func export(books: [Book], to vaultURL: URL) throws -> ObsidianVaultExportReport {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: vaultURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ObsidianVaultExportError.destinationIsNotDirectory
        }
        let publicBooks = books.filter { !$0.isPrivate }.sorted { $0.id.uuidString < $1.id.uuidString }
        let root = vaultURL.appendingPathComponent("Varq", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for book in publicBooks {
            let bookPath = "Books/\(book.id.uuidString).md"
            let artifactPath = "Reading Artifacts/\(book.id.uuidString).md"
            let authorPath = "Authors/\(stableID(for: book.author)).md"
            let collections = (book.collections ?? []).sorted { $0.id.uuidString < $1.id.uuidString }
            let collectionLinks = collections.map { "[[Collections/\($0.id.uuidString)|\($0.name)]]" }
            let bookMarkdown = """
            \(Self.managedMarker)
            ---
            varq_id: "\(book.id.uuidString)"
            varq_kind: "book"
            title: "\(yamlEscaped(book.title))"
            author: "[[\(authorPath.dropLast(3))|\(book.author)]]"
            collections: [\(collectionLinks.map { "\"\($0)\"" }.joined(separator: ", "))]
            reading_artifacts: "[[\(artifactPath.dropLast(3))|Reading Artifacts]]"
            ---

            # \(book.title)

            [[\(authorPath.dropLast(3))|\(book.author)]] · [[\(artifactPath.dropLast(3))|Reading Artifacts]]
            """
            try writeManaged(bookMarkdown, relativePath: bookPath, under: root)
            try writeManaged(artifactsMarkdown(for: book), relativePath: artifactPath, under: root)
        }

        let authors = Dictionary(grouping: publicBooks, by: \Book.author)
        for (author, authorBooks) in authors {
            let path = "Authors/\(stableID(for: author)).md"
            let links = authorBooks.sorted { $0.id.uuidString < $1.id.uuidString }.map { "- [[Books/\($0.id.uuidString)|\($0.title)]]" }.joined(separator: "\n")
            try writeManaged("\(Self.managedMarker)\n---\nvarq_id: \"author-\(stableID(for: author))\"\nvarq_kind: \"author\"\n---\n\n# \(author)\n\n\(links)\n", relativePath: path, under: root)
        }
        let collections = Dictionary(
            uniqueKeysWithValues: publicBooks.flatMap { $0.collections ?? [] }.map { ($0.id, $0) }
        )
        for collection in collections.values {
            let links = publicBooks.filter { book in
                (book.collections ?? []).contains { $0.id == collection.id }
            }.map { "- [[Books/\($0.id.uuidString)|\($0.title)]]" }.joined(separator: "\n")
            try writeManaged("\(Self.managedMarker)\n---\nvarq_id: \"collection-\(collection.id.uuidString)\"\nvarq_kind: \"collection\"\n---\n\n# \(collection.name)\n\n\(links)\n", relativePath: "Collections/\(collection.id.uuidString).md", under: root)
        }
        return ObsidianVaultExportReport(exportedBookCount: publicBooks.count, skippedPrivateBookCount: books.count - publicBooks.count)
    }

    private func artifactsMarkdown(for book: Book) -> String {
        let highlights = book.highlights.sorted { $0.dateCreated < $1.dateCreated }.map { "> \($0.selectedText)\n\n\($0.note ?? "")" }.joined(separator: "\n\n")
        let notes = book.notes.sorted { $0.dateCreated < $1.dateCreated }.map { "## Note\n\n\($0.body)" }.joined(separator: "\n\n")
        return "\(Self.managedMarker)\n---\nvarq_id: \"artifacts-\(book.id.uuidString)\"\nvarq_kind: \"reading_artifacts\"\nbook: \"[[Books/\(book.id.uuidString)|\(book.title)]]\"\n---\n\n# Reading Artifacts\n\n\(highlights)\n\n\(notes)\n"
    }

    private func writeManaged(_ text: String, relativePath: String, under root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: url.path), !(try String(contentsOf: url, encoding: .utf8)).hasPrefix(Self.managedMarker) {
            throw ObsidianVaultExportError.unmanagedFileConflict(relativePath)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func stableID(for value: String) -> String {
        let value = value.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }.joined()
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func yamlEscaped(_ value: String) -> String { value.replacingOccurrences(of: "\"", with: "\\\"") }
}
