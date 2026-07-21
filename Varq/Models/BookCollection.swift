import Foundation
import SwiftData

@Model
final class BookCollection {
    var id: UUID
    var name: String
    var isDefault: Bool
    var dateCreated: Date

    @Relationship(deleteRule: .nullify, inverse: \Book.collections)
    var books: [Book]?

    init(
        id: UUID = UUID(),
        name: String,
        isDefault: Bool = false,
        dateCreated: Date = .now,
        books: [Book]? = nil
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.dateCreated = dateCreated
        self.books = books
    }
}
