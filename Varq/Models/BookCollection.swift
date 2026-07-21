import Foundation
import SwiftData

@Model
final class BookCollection {
    var id: UUID
    var name: String
    var isDefault: Bool
    var dateCreated: Date
    var symbolName: String?

    @Relationship(deleteRule: .nullify, inverse: \Book.collections)
    var books: [Book]?

    init(
        id: UUID = UUID(),
        name: String,
        isDefault: Bool = false,
        dateCreated: Date = .now,
        symbolName: String? = "folder",
        books: [Book]? = nil
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.dateCreated = dateCreated
        self.symbolName = symbolName
        self.books = books
    }
}
