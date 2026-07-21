import Foundation

struct DuplicateDetectionService {
    func hasDuplicate(contentHash: String, among books: [Book]) -> Bool {
        books.contains { $0.contentHash == contentHash }
    }
}
