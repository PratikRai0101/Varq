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

        var symbolName: String {
            switch self {
            case .title: "textformat"
            case .author: "person"
            case .dateAdded: "calendar"
            case .recentlyRead: "clock.arrow.circlepath"
            }
        }
    }

    private(set) var books: [Book] = []
    private(set) var allBooks: [Book] = []
    private(set) var collections: [BookCollection] = []
    var sortOrder: SortOrder = .title {
        didSet { sortBooks() }
    }
    var selectedCollection: BookCollection? = nil {
        didSet { applyFilter() }
    }

    func load(using context: ModelContext) throws {
        ensureDefaultCollections(in: context)
        allBooks = try context.fetch(FetchDescriptor<Book>())
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

    func createCollection(named name: String, symbolName: String = "folder", using context: ModelContext) {
        let collection = BookCollection(name: name, symbolName: symbolName)
        context.insert(collection)
        try? context.save()
        try? load(using: context)
    }

    func updateCollection(_ collection: BookCollection, name: String, symbolName: String, using context: ModelContext) {
        collection.name = name
        collection.symbolName = symbolName
        try? context.save()
        try? load(using: context)
    }

    private func ensureDefaultCollections(in context: ModelContext) {
        let existing = try? context.fetch(FetchDescriptor<BookCollection>())
        let defaultNames = ["All", "Currently Reading", "Recently Read", "Want to Read", "Finished", "Favorites"]
        let defaultIcons: [String: String] = [
            "All": "books.vertical",
            "Currently Reading": "book.closed",
            "Recently Read": "clock",
            "Want to Read": "bookmark",
            "Finished": "checkmark.circle",
            "Favorites": "heart",
        ]
        let existingNames = Set(existing?.map(\.name) ?? [])
        for name in defaultNames where !existingNames.contains(name) {
            let collection = BookCollection(name: name, isDefault: true)
            collection.symbolName = defaultIcons[name] ?? "folder"
            context.insert(collection)
        }
        for collection in existing ?? [] where collection.isDefault {
            if let icon = defaultIcons[collection.name],
               collection.symbolName == nil || collection.symbolName == "folder" || collection.symbolName == "book.open" {
                collection.symbolName = icon
            }
        }
        try? context.save()
    }

    private func applyFilter() {
        guard let selected = selectedCollection, selected.name != "All" else {
            books = allBooks
            sortBooks()
            return
        }
        let filtered = allBooks.filter { book in
            switch selected.name {
            case "Currently Reading":
                guard let progress = book.readingProgress else { return false }
                return progress.percentComplete < 1
            case "Finished":
                guard let progress = book.readingProgress else { return false }
                return progress.percentComplete >= 1
            case "Recently Read":
                return book.readingProgress != nil
            case "Favorites", "Want to Read":
                return book.collections?.contains(where: { $0.id == selected.id }) ?? false
            default:
                return book.collections?.contains(where: { $0.id == selected.id }) ?? false
            }
        }
        books = filtered.sorted { lhs, rhs in
            if selected.name == "Recently Read" {
                return (lhs.readingProgress?.lastReadDate ?? .distantPast) > (rhs.readingProgress?.lastReadDate ?? .distantPast)
            }
            switch sortOrder {
            case .title: return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .author: return lhs.author.localizedCaseInsensitiveCompare(rhs.author) == .orderedAscending
            case .dateAdded: return lhs.dateAdded > rhs.dateAdded
            case .recentlyRead: return (lhs.readingProgress?.lastReadDate ?? .distantPast) > (rhs.readingProgress?.lastReadDate ?? .distantPast)
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
