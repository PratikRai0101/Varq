import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import Varq

@MainActor
struct LibraryViewModelTests {
    @Test func refreshesPdfMetadataWithoutReplacingTheSavedTitleWithAManagedFilename() async throws {
        let container = try ModelContainer(for: Book.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let book = Book(title: "My saved title", author: "Outdated", libraryRelativePath: "managed-id.pdf", contentHash: "unchanged", format: .pdf)
        context.insert(book)
        try context.save()
        let viewModel = LibraryViewModel()
        try viewModel.load(using: context)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/minimal.pdf")

        await viewModel.refreshMetadata(for: book, managedFileURL: fixture, using: context)

        #expect(book.title == "My saved title")
        #expect(book.author == "Unknown Author")
        #expect(book.coverImageData?.isEmpty == false)
        #expect(book.contentHash == "unchanged")
        #expect(viewModel.metadataRefreshError == nil)
    }

    @Test func refreshesEpubMetadataFromTheOriginalFixture() async throws {
        let container = try ModelContainer(for: Book.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let book = Book(title: "Outdated", author: "Outdated", libraryRelativePath: "book.epub", contentHash: "unchanged", format: .epub)
        context.insert(book)
        try context.save()
        let viewModel = LibraryViewModel()
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/minimal.epub")

        await viewModel.refreshMetadata(for: book, managedFileURL: fixture, using: context)

        #expect(book.title == "Varq Fixture")
        #expect(book.author == "Varq Tests")
        #expect(book.coverImageData?.isEmpty == false)
        #expect(viewModel.books.first?.title == "Varq Fixture")
        #expect(viewModel.metadataRefreshError == nil)
    }

    @Test func failedRefreshSaveRestoresAllMetadataAndReportsTheFailure() async throws {
        let container = try ModelContainer(for: Book.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let originalCover = Data("original cover".utf8)
        let book = Book(title: "Original title", author: "Original writer", libraryRelativePath: "book.epub", contentHash: "unchanged", format: .epub)
        book.coverImageData = originalCover
        context.insert(book)
        try context.save()
        let viewModel = LibraryViewModel(saveChanges: { _ in throw CocoaError(.fileWriteNoPermission) })
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/minimal.epub")

        await viewModel.refreshMetadata(for: book, managedFileURL: fixture, using: context)

        #expect(book.title == "Original title")
        #expect(book.author == "Original writer")
        #expect(book.coverImageData == originalCover)
        #expect(viewModel.metadataRefreshError != nil)
    }

    @Test func refusesPrivateBooksWithoutChangingTheirCiphertextOrMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/minimal.pdf")
        let ciphertext = try PrivateBookCryptoService().encrypt(Data(contentsOf: fixture), using: SymmetricKey(size: .bits256))
        let encrypted = directory.appendingPathComponent("book.pdf")
        try ciphertext.write(to: encrypted)
        let container = try ModelContainer(for: Book.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let book = Book(title: "Private title", author: "Private writer", libraryRelativePath: "book.pdf", contentHash: "unchanged", format: .pdf, isPrivate: true)
        context.insert(book)
        try context.save()
        let viewModel = LibraryViewModel()

        await viewModel.refreshMetadata(for: book, managedFileURL: encrypted, using: context)

        #expect(viewModel.metadataRefreshError == "Unmark this book as private before refreshing its metadata.")
        #expect(book.title == "Private title")
        #expect(book.author == "Private writer")
        #expect(book.isPrivate)
        #expect(try Data(contentsOf: encrypted) == ciphertext)
    }

    @Test(arguments: [false, true])
    func parseFailuresKeepExistingMetadataAndExposeADismissibleError(missing: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("book.pdf")
        if !missing { try Data("invalid PDF".utf8).write(to: source) }
        let container = try ModelContainer(for: Book.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let cover = Data("original cover".utf8)
        let book = Book(title: "Original", author: "Original writer", libraryRelativePath: "book.pdf", contentHash: "unchanged", format: .pdf)
        book.coverImageData = cover
        context.insert(book)
        try context.save()
        let viewModel = LibraryViewModel()

        await viewModel.refreshMetadata(for: book, managedFileURL: source, using: context)

        #expect(book.title == "Original")
        #expect(book.author == "Original writer")
        #expect(book.coverImageData == cover)
        #expect(viewModel.metadataRefreshError != nil)
        viewModel.clearMetadataRefreshError()
        #expect(viewModel.metadataRefreshError == nil)
    }

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
