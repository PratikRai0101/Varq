import Foundation
import SwiftData
import Testing
@testable import Varq

@MainActor
struct ImportViewModelTests {
    @Test func importsSupportedBooksAndReportsUnsupportedFilesIndividually() async throws {
        let libraryDirectory = temporaryLibraryDirectory()
        defer { try? FileManager.default.removeItem(at: libraryDirectory) }
        let context = try modelContext()
        let viewModel = ImportViewModel(importer: ImportService(libraryDirectory: libraryDirectory))

        await viewModel.importFiles([epubFixtureURL, URL(fileURLWithPath: "/tmp/unsupported.cbr")], into: context)

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.count == 1)
        #expect(books.first?.format == .epub)
        #expect(viewModel.importErrors.count == 1)
        #expect(viewModel.importErrors.first?.fileName == "unsupported.cbr")
    }

    @Test func rejectsDuplicateImportsAndRemovesTheirManagedCopy() async throws {
        let libraryDirectory = temporaryLibraryDirectory()
        defer { try? FileManager.default.removeItem(at: libraryDirectory) }
        let context = try modelContext()
        let viewModel = ImportViewModel(importer: ImportService(libraryDirectory: libraryDirectory))

        await viewModel.importFiles([epubFixtureURL], into: context)
        await viewModel.importFiles([epubFixtureURL], into: context)

        let books = try context.fetch(FetchDescriptor<Book>())
        let managedFiles = try FileManager.default.contentsOfDirectory(atPath: libraryDirectory.path)
        #expect(books.count == 1)
        #expect(managedFiles.count == 1)
        #expect(viewModel.importErrors.count == 1)
        #expect(viewModel.importErrors.first?.message == "This book is already in your library.")
    }

    @Test func pickerContentTypesExcludeCbr() {
        let fileExtensions = Set(ImportViewModel.supportedContentTypes.compactMap(\.preferredFilenameExtension))

        #expect(fileExtensions.isSuperset(of: ["epub", "pdf", "cbz"]))
        #expect(!fileExtensions.contains("cbr"))
    }

    private func modelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Book.self,
            ReadingProgress.self,
            Highlight.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func temporaryLibraryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private var epubFixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/minimal.epub")
    }
}
