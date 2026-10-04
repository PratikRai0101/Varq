import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers
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

    @Test func importsReadableNestedBooksAndReportsAllPartialFailures() async throws {
        let library = temporaryLibraryDirectory()
        let folder = temporaryLibraryDirectory()
        defer {
            try? FileManager.default.removeItem(at: library)
            try? FileManager.default.removeItem(at: folder)
        }
        let nested = folder.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let original = folder.appendingPathComponent("a.EPUB")
        let duplicate = nested.appendingPathComponent("duplicate.epub")
        try FileManager.default.copyItem(at: epubFixtureURL, to: original)
        try FileManager.default.copyItem(at: epubFixtureURL, to: duplicate)
        try Data("not a PDF".utf8).write(to: nested.appendingPathComponent("broken.pdf"))
        try Data("unrelated".utf8).write(to: folder.appendingPathComponent("readme.txt"))
        let manager = FolderTestDirectoryEnumerator()
        manager.inaccessibleURL = folder.appendingPathComponent("unreadable")
        let scope = FolderTestSecurityScope()
        let context = try modelContext()
        let viewModel = ImportViewModel(
            importer: ImportService(libraryDirectory: library),
            folderImportService: FolderImportService(directoryEnumerator: manager, securityScope: scope)
        )

        await viewModel.importDirectory(folder, into: context)

        #expect(try context.fetchCount(FetchDescriptor<Book>()) == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: library.path).count == 1)
        #expect(Set(viewModel.importErrors.map(\.fileName)) == ["duplicate.epub", "broken.pdf", "unreadable"])
        #expect(viewModel.importErrors.contains { $0.message == "This book is already in your library." })
        let expected = try Data(contentsOf: epubFixtureURL)
        #expect(try Data(contentsOf: original) == expected)
        #expect(try Data(contentsOf: duplicate) == expected)
        #expect(scope.started == [folder])
        #expect(scope.stopped == [folder])
    }

    @Test func reportsAnUnavailableFolderInsteadOfSilentlyDoingNothing() async throws {
        let library = temporaryLibraryDirectory()
        defer { try? FileManager.default.removeItem(at: library) }
        let context = try modelContext()
        let viewModel = ImportViewModel(importer: ImportService(libraryDirectory: library))
        let missing = temporaryLibraryDirectory().appendingPathComponent("Missing folder")

        await viewModel.importDirectory(missing, into: context)

        #expect(viewModel.importErrors.count == 1)
        #expect(viewModel.importErrors.first?.fileName == "Missing folder")
        #expect(try context.fetchCount(FetchDescriptor<Book>()) == 0)
    }

    @Test func failedPreflightSaveLeavesPendingEditsAndCreatesNoManagedCopy() async throws {
        let library = temporaryLibraryDirectory()
        defer { try? FileManager.default.removeItem(at: library) }
        let context = try modelContext()
        let existing = Book(title: "Original", author: "Tests", libraryRelativePath: "existing.epub", contentHash: "existing", format: .epub)
        context.insert(existing)
        try context.save()
        existing.title = "Pending user edit"
        let viewModel = ImportViewModel(importer: ImportService(libraryDirectory: library), saveChanges: { _ in
            throw CocoaError(.fileWriteNoPermission)
        })

        await viewModel.importFiles([epubFixtureURL], into: context)

        #expect(existing.title == "Pending user edit")
        #expect(context.hasChanges)
        #expect(!FileManager.default.fileExists(atPath: library.path))
        #expect(viewModel.importErrors.count == 1)
        #expect(try ModelContext(context.container).fetchCount(FetchDescriptor<Book>()) == 1)
    }

    @Test func committedImportClearsItsRecoveryRecord() async throws {
        let library = temporaryLibraryDirectory()
        defer { try? FileManager.default.removeItem(at: library) }
        let context = try modelContext()
        let importer = ImportService(libraryDirectory: library)
        let viewModel = ImportViewModel(importer: importer)

        await viewModel.importFiles([epubFixtureURL], into: context)

        #expect(viewModel.importErrors.isEmpty)
        #expect(try ModelContext(context.container).fetchCount(FetchDescriptor<Book>()) == 1)
        #expect(try await !importer.hasPendingImports())
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
