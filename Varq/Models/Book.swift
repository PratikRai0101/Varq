import Foundation
import SwiftData

@Model
final class Book {
    var id: UUID
    var title: String
    var author: String
    var coverImageData: Data?
    var libraryRelativePath: String
    var contentHash: String
    var formatRawValue: String
    var dateAdded: Date
    var isPrivate: Bool

    @Relationship(deleteRule: .cascade, inverse: \ReadingProgress.book)
    var readingProgress: ReadingProgress?

    @Relationship(deleteRule: .cascade, inverse: \Highlight.book)
    var highlights: [Highlight]

    @Relationship(deleteRule: .cascade, inverse: \ReadingNote.book)
    var notes: [ReadingNote]

    var collections: [BookCollection]?

    var format: BookFormat {
        get { BookFormat(rawValue: formatRawValue) ?? .epub }
        set { formatRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        title: String,
        author: String,
        coverImageData: Data? = nil,
        libraryRelativePath: String,
        contentHash: String,
        format: BookFormat,
        dateAdded: Date = .now,
        isPrivate: Bool = false
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverImageData = coverImageData
        self.libraryRelativePath = libraryRelativePath
        self.contentHash = contentHash
        self.formatRawValue = format.rawValue
        self.dateAdded = dateAdded
        self.isPrivate = isPrivate
        self.readingProgress = nil
        self.highlights = []
        self.notes = []
    }
}
