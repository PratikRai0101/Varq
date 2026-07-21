import Foundation
import Testing
@testable import Varq

struct DuplicateDetectionServiceTests {
    @Test func identifiesMatchingContentHashes() {
        let existingBook = Book(
            title: "Existing",
            author: "Author",
            libraryRelativePath: "existing.epub",
            contentHash: "same-hash",
            format: .epub
        )
        let service = DuplicateDetectionService()

        #expect(service.hasDuplicate(contentHash: "same-hash", among: [existingBook]))
        #expect(!service.hasDuplicate(contentHash: "different-hash", among: [existingBook]))
    }
}
