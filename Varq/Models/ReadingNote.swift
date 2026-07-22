import Foundation
import SwiftData

@Model
final class ReadingNote {
    var id: UUID
    var anchorData: Data
    var selectedText: String?
    var body: String
    var colorTag: String
    var dateCreated: Date
    var dateModified: Date
    var book: Book?

    init(
        id: UUID = UUID(),
        anchorData: Data,
        selectedText: String? = nil,
        body: String,
        colorTag: String,
        dateCreated: Date = .now,
        dateModified: Date = .now,
        book: Book? = nil
    ) {
        self.id = id
        self.anchorData = anchorData
        self.selectedText = selectedText
        self.body = body
        self.colorTag = colorTag
        self.dateCreated = dateCreated
        self.dateModified = dateModified
        self.book = book
    }
}
