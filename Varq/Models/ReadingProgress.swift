import Foundation
import SwiftData

@Model
final class ReadingProgress {
    var id: UUID
    var locatorData: Data
    var lastReadDate: Date
    var percentComplete: Double
    var book: Book?

    init(
        id: UUID = UUID(),
        locatorData: Data,
        lastReadDate: Date = .now,
        percentComplete: Double = 0,
        book: Book? = nil
    ) {
        self.id = id
        self.locatorData = locatorData
        self.lastReadDate = lastReadDate
        self.percentComplete = percentComplete
        self.book = book
    }
}
