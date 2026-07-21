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
    var sortOrder: SortOrder = .title {
        didSet { sortBooks() }
    }

    func load(using context: ModelContext) throws {
        books = try context.fetch(FetchDescriptor<Book>())
        sortBooks()
    }

    private func sortBooks() {
        books.sort { lhs, rhs in
            switch sortOrder {
            case .title: lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .author: lhs.author.localizedCaseInsensitiveCompare(rhs.author) == .orderedAscending
            case .dateAdded: lhs.dateAdded > rhs.dateAdded
            case .recentlyRead: (lhs.readingProgress?.lastReadDate ?? .distantPast) > (rhs.readingProgress?.lastReadDate ?? .distantPast)
            }
        }
    }
}
