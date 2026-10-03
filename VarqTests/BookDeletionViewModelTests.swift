import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import Varq

@MainActor
struct BookDeletionViewModelTests {
    @Test func committedDeletionCleanupFailureRetainsCiphertextAndKeepsTheSharedRecoveryGateClosed() throws {
        let library = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: library) }
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let container = try ModelContainer(for: Book.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let book = Book(title: "Private", author: "Varq", libraryRelativePath: "book.pdf", contentHash: "hash", format: .pdf, isPrivate: true)
        let keys = DeletionTestKeyStore()
        let key = SymmetricKey(size: .bits256)
        try keys.store(key, for: book.id)
        let ciphertext = try PrivateBookCryptoService().encrypt(Data("private original".utf8), using: key)
        try ciphertext.write(to: library.appendingPathComponent("book.pdf"))
        context.insert(book)
        try context.save()
        let service = BookDeletionService(keyStore: keys)
        let libraryModel = LibraryViewModel(deletionService: service)
        keys.removalError = CocoaError(.fileWriteNoPermission)
        libraryModel.deleteBook(book, managedLibraryDirectory: library, using: context)
        #expect(libraryModel.isDeletionRecoveryRequired)
        #expect(libraryModel.deletionError?.contains("cleanup is incomplete") == true)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Book>()) == 0)
        let pending = try #require(service.pendingRecords(in: library).first)
        let payload = library.appendingPathComponent(".book-deletions/" + pending.bookID.uuidString + "/payload")
        #expect(try Data(contentsOf: payload) == ciphertext)
        let recovery = PrivateBookViewModel(deletionService: service)
        recovery.requireDeletionRecovery(try #require(libraryModel.deletionError))
        recovery.clearError()
        #expect(!recovery.isRecoveryComplete)
        #expect(recovery.errorMessage != nil)
        keys.removalError = nil

        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: library)

        #expect(recovery.isRecoveryComplete)
        #expect(keys.keys.isEmpty)
        #expect(try service.pendingRecords(in: library).isEmpty)
    }

    @Test func rollbackFailureBlocksLibraryRecoveryUntilTheFileCanBeRestored() throws {
        let library = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: library) }
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let source = library.appendingPathComponent("book.epub")
        let data = Data("original managed file".utf8)
        try data.write(to: source)
        let container = try ModelContainer(for: Book.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let book = Book(title: "Keep", author: "Varq", libraryRelativePath: "book.epub", contentHash: "hash", format: .epub)
        context.insert(book)
        try context.save()
        let manager = DeletionTestFileManager()
        manager.failMovesToManagedFile = true
        let service = BookDeletionService(fileManager: manager)
        let libraryModel = LibraryViewModel(deletionService: service, saveChanges: { _ in throw CocoaError(.fileWriteNoPermission) })
        libraryModel.deleteBook(book, managedLibraryDirectory: library, using: context)
        #expect(libraryModel.isDeletionRecoveryRequired)
        #expect(libraryModel.deletionError?.contains("restoration also failed") == true)
        let recovery = PrivateBookViewModel(deletionService: service)
        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: library)
        #expect(!recovery.isRecoveryComplete)
        manager.failMovesToManagedFile = false

        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: library)

        #expect(recovery.isRecoveryComplete)
        #expect(try Data(contentsOf: source) == data)
        try libraryModel.load(using: context)
        #expect(libraryModel.books.count == 1)
    }

    @Test func failedDeleteDoesNotDiscardAnUnrelatedPendingEdit() throws {
        let library = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: library) }
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try Data("book".utf8).write(to: library.appendingPathComponent("book.epub"))
        let container = try ModelContainer(for: Book.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let book = Book(title: "Delete", author: "Varq", libraryRelativePath: "book.epub", contentHash: "hash", format: .epub)
        let other = Book(title: "Original", author: "Varq", libraryRelativePath: "other.pdf", contentHash: "other", format: .pdf)
        context.insert(book)
        context.insert(other)
        try context.save()
        other.title = "Unsaved user edit"
        let viewModel = LibraryViewModel(saveChanges: { _ in throw CocoaError(.fileWriteNoPermission) })
        viewModel.deleteBook(book, managedLibraryDirectory: library, using: context)
        #expect(other.title == "Unsaved user edit")
        #expect(FileManager.default.fileExists(atPath: library.appendingPathComponent("book.epub").path))
        #expect(viewModel.deletionError != nil)
    }

    @Test func successfulDeletionRemovesOnlyTheSelectedBookAndItsArtifacts() throws {
        let library = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: library) }
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try Data("selected".utf8).write(to: library.appendingPathComponent("book.epub"))
        let otherFile = library.appendingPathComponent("other.pdf")
        try Data("other".utf8).write(to: otherFile)
        let container = try ModelContainer(for: Book.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let book = Book(title: "Delete", author: "Varq", libraryRelativePath: "book.epub", contentHash: "hash", format: .epub)
        let other = Book(title: "Keep", author: "Varq", libraryRelativePath: "other.pdf", contentHash: "other", format: .pdf)
        context.insert(book)
        context.insert(other)
        context.insert(ReadingNote(anchorData: Data(), body: "Selected note", colorTag: "saffron", book: book))
        context.insert(ReadingProgress(locatorData: Data(), percentComplete: 0.5, book: book))
        context.insert(Highlight(locatorData: Data(), selectedText: "Selected passage", colorTag: "saffron", book: book))
        try context.save()
        let viewModel = LibraryViewModel()

        viewModel.deleteBook(book, managedLibraryDirectory: library, using: context)

        #expect(viewModel.deletionError == nil)
        #expect(viewModel.books.map(\.title) == ["Keep"])
        #expect(!FileManager.default.fileExists(atPath: library.appendingPathComponent("book.epub").path))
        #expect(try Data(contentsOf: otherFile) == Data("other".utf8))
        let persisted = ModelContext(container)
        #expect(try persisted.fetchCount(FetchDescriptor<ReadingNote>()) == 0)
        #expect(try persisted.fetchCount(FetchDescriptor<ReadingProgress>()) == 0)
        #expect(try persisted.fetchCount(FetchDescriptor<Highlight>()) == 0)
    }

    @Test func failedDeletionSaveKeepsTheBookItsNotesAndManagedFile() throws {
        let library = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: library) }
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let source = library.appendingPathComponent("book.epub")
        let bytes = Data("managed book".utf8)
        try bytes.write(to: source)
        let container = try ModelContainer(for: Book.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let book = Book(title: "Keep me", author: "Varq", libraryRelativePath: "book.epub", contentHash: "hash", format: .epub)
        let note = ReadingNote(anchorData: Data(), body: "Keep this note", colorTag: "saffron", book: book)
        context.insert(book)
        context.insert(note)
        context.insert(Highlight(locatorData: Data(), selectedText: "Keep this highlight", colorTag: "saffron", book: book))
        context.insert(ReadingProgress(locatorData: Data(), percentComplete: 0.5, book: book))
        try context.save()
        let viewModel = LibraryViewModel(deletionService: BookDeletionService(), saveChanges: { _ in throw CocoaError(.fileWriteNoPermission) })

        viewModel.deleteBook(book, managedLibraryDirectory: library, using: context)
        try viewModel.load(using: context)

        #expect(viewModel.books.contains { $0.id == book.id })
        #expect(book.notes.contains { $0.body == "Keep this note" })
        #expect(book.highlights.contains { $0.selectedText == "Keep this highlight" })
        #expect(book.readingProgress?.percentComplete == 0.5)
        #expect(viewModel.deletionError != nil)
        #expect(try Data(contentsOf: source) == bytes)
        #expect(try BookDeletionService().pendingRecords(in: library).isEmpty)
    }
}
