import SwiftData
import Testing
@testable import Varq

@MainActor
struct LibraryViewModelTests {
    @Test func sortsBooksByTitle() throws {
        let container = try ModelContainer(for: Book.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.insert(Book(title: "Zulu", author: "A", libraryRelativePath: "z", contentHash: "z", format: .epub))
        context.insert(Book(title: "Alpha", author: "B", libraryRelativePath: "a", contentHash: "a", format: .pdf))
        try context.save()

        let viewModel = LibraryViewModel()
        try viewModel.load(using: context)

        #expect(viewModel.books.map(\.title) == ["Alpha", "Zulu"])
    }
}
