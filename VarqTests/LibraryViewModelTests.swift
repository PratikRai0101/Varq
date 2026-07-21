import Foundation
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

    @Test func restoresAllBooksAfterLeavingCurrentlyReading() throws {
        let container = try ModelContainer(
            for: Book.self,
            BookCollection.self,
            ReadingProgress.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let ongoing = Book(title: "Ongoing", author: "A", libraryRelativePath: "ongoing", contentHash: "ongoing", format: .epub)
        let unread = Book(title: "Unread", author: "B", libraryRelativePath: "unread", contentHash: "unread", format: .epub)
        let progress = ReadingProgress(locatorData: Data(), percentComplete: 0.5, book: ongoing)
        context.insert(ongoing)
        context.insert(unread)
        context.insert(progress)
        try context.save()

        let viewModel = LibraryViewModel()
        try viewModel.load(using: context)
        let currentlyReading = try #require(viewModel.collections.first { $0.name == "Currently Reading" })
        let all = try #require(viewModel.collections.first { $0.name == "All" })

        viewModel.selectedCollection = currentlyReading
        #expect(viewModel.books.map(\.title) == ["Ongoing"])

        viewModel.selectedCollection = all
        #expect(viewModel.books.map(\.title) == ["Ongoing", "Unread"])
    }

    @Test func createsAClockIconForRecentlyRead() throws {
        let container = try ModelContainer(
            for: Book.self,
            BookCollection.self,
            ReadingProgress.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let viewModel = LibraryViewModel()

        try viewModel.load(using: context)

        let recentlyRead = try #require(viewModel.collections.first { $0.name == "Recently Read" })
        #expect(recentlyRead.symbolName == "clock")
    }

    @Test func reappliesSortingWhenTheSelectedOrderChanges() throws {
        let container = try ModelContainer(for: Book.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let first = Book(title: "Zulu", author: "Alpha", libraryRelativePath: "z", contentHash: "z", format: .epub, dateAdded: .distantPast)
        let second = Book(title: "Alpha", author: "Zulu", libraryRelativePath: "a", contentHash: "a", format: .pdf, dateAdded: .now)
        context.insert(first)
        context.insert(second)
        try context.save()
        let viewModel = LibraryViewModel()
        try viewModel.load(using: context)

        viewModel.sortOrder = .author
        #expect(viewModel.books.map(\.title) == ["Zulu", "Alpha"])

        viewModel.sortOrder = .dateAdded
        #expect(viewModel.books.map(\.title) == ["Alpha", "Zulu"])
    }
}
