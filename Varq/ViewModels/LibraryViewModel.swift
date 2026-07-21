import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class LibraryViewModel {
    enum SortOrder: String, CaseIterable {
        case title
        case author
        case dateAdded
        case recentlyRead

        var displayName: String {
            switch self {
            case .title: "Title"
            case .author: "Author"
            case .dateAdded: "Date added"
            case .recentlyRead: "Recently read"
            }
        }
    }

    private(set) var books: [Book] = []
    private(set) var collections: [BookCollection] = []
    var sortOrder: SortOrder = .title {
        didSet { sortBooks() }
    }
    var selectedCollection: BookCollection? = nil {
        didSet { applyFilter() }
    }

    func load(using context: ModelContext) throws {
        ensureDefaultCollections(in: context)
        books = try context.fetch(FetchDescriptor<Book>())
        collections = try context.fetch(
            FetchDescriptor<BookCollection>(sortBy: [SortDescriptor(\BookCollection.name)])
        )
        applyFilter()
    }

    func addBook(_ book: Book, to collection: BookCollection, using context: ModelContext) {
        if collection.books == nil {
            collection.books = []
        }
        if !(collection.books?.contains(where: { $0.id == book.id }) ?? false) {
            collection.books?.append(book)
            try? context.save()
            try? load(using: context)
        }
    }

    func removeBook(_ book: Book, from collection: BookCollection, using context: ModelContext) {
        collection.books?.removeAll(where: { $0.id == book.id })
        try? context.save()
        try? load(using: context)
    }

    func deleteCollection(_ collection: BookCollection, using context: ModelContext) {
        guard !collection.isDefault else { return }
        context.delete(collection)
        try? context.save()
        if selectedCollection?.id == collection.id {
            selectedCollection = nil
        }
        try? load(using: context)
    }

    func createCollection(named name: String, using context: ModelContext) {
        let collection = BookCollection(name: name)
        context.insert(collection)
        try? context.save()
        try? load(using: context)
    }

    private func ensureDefaultCollections(in context: ModelContext) {
        let existing = try? context.fetch(FetchDescriptor<BookCollection>())
        let defaultNames = ["All", "Want to Read", "Finished", "Favorites"]
        let existingNames = Set(existing?.map(\.name) ?? [])
        for name in defaultNames where !existingNames.contains(name) {
            context.insert(BookCollection(name: name, isDefault: true))
        }
        try? context.save()
    }

    private func applyFilter() {
        guard let selected = selectedCollection, selected.name != "All" else {
            sortBooks()
            return
        }
        let filtered = books.filter { book in
            book.collections?.contains(where: { $0.id == selected.id }) ?? false
        }
        books = filtered.sorted { lhs, rhs in
            switch sortOrder {
            case .title: lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .author: lhs.author.localizedCaseInsensitiveCompare(rhs.author) == .orderedAscending
            case .dateAdded: lhs.dateAdded > rhs.dateAdded
            case .recentlyRead: (lhs.readingProgress?.lastReadDate ?? .distantPast) > (rhs.readingProgress?.lastReadDate ?? .distantPast)
            }
        }
    }

    private func sortBooks() {
        books = books.sorted { lhs, rhs in
            switch sortOrder {
            case .title: lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .author: lhs.author.localizedCaseInsensitiveCompare(rhs.author) == .orderedAscending
            case .dateAdded: lhs.dateAdded > rhs.dateAdded
            case .recentlyRead: (lhs.readingProgress?.lastReadDate ?? .distantPast) > (rhs.readingProgress?.lastReadDate ?? .distantPast)
            }
        }
    }
}
