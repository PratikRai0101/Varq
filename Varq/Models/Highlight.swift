import Foundation
import SwiftData

@Model
final class Highlight {
    var id: UUID
    var locatorData: Data
    var selectedText: String
    var note: String?
    var colorTag: String
    var dateCreated: Date
    var book: Book?

    init(
        id: UUID = UUID(),
        locatorData: Data,
        selectedText: String,
        note: String? = nil,
        colorTag: String,
        dateCreated: Date = .now,
        book: Book? = nil
    ) {
        self.id = id
        self.locatorData = locatorData
        self.selectedText = selectedText
        self.note = note
        self.colorTag = colorTag
        self.dateCreated = dateCreated
        self.book = book
    }
}
