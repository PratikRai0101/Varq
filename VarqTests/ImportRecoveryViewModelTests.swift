import Foundation
import SwiftData
import Testing
@testable import Varq

@MainActor
struct ImportRecoveryViewModelTests {
    @Test func failedIsolatedInsertionPreservesExistingArtifactsAndRemovesOnlyItsCopy() async throws {
        let library = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        let context = try modelContext()
        let existing = Book(title: "Keep", author: "Tests", libraryRelativePath: "existing.epub", contentHash: "existing", format: .epub)
        context.insert(existing)
        context.insert(ReadingNote(anchorData: Data(), body: "Keep note", colorTag: "saffron", book: existing))
        context.insert(Highlight(locatorData: Data(), selectedText: "Keep highlight", colorTag: "saffron", book: existing))
        context.insert(ReadingProgress(locatorData: Data(), percentComplete: 0.5, book: existing))
        try context.save()
        let importer = ImportService(libraryDirectory: library)
        let viewModel = ImportViewModel(importer: importer, saveChanges: { _ in throw CocoaError(.fileWriteNoPermission) })

        await viewModel.importFiles([fixtureURL], into: context)

        #expect(viewModel.importErrors.count == 1)
        #expect(!viewModel.isImportRecoveryRequired)
        #expect(!context.hasChanges)
        let persisted = ModelContext(context.container)
        #expect(try persisted.fetchCount(FetchDescriptor<Book>()) == 1)
        #expect(existing.notes.first?.body == "Keep note")
        #expect(existing.highlights.first?.selectedText == "Keep highlight")
        #expect(existing.readingProgress?.percentComplete == 0.5)
        #expect(try FileManager.default.contentsOfDirectory(atPath: library.path).isEmpty)
        #expect(try await !importer.hasPendingImports())
    }

    @Test func failedSaveAndCleanupKeepRecoveryGateClosedUntilRetry() async throws {
        let library = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        let context = try modelContext()
        let manager = ImportRecoveryTestFileManager()
        manager.failCleanupMove = true
        let recovery = recoveryViewModel(library: library, manager: manager)
        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: library)
        #expect(recovery.isRecoveryComplete)
        let importer = ImportService(libraryDirectory: library, fileManager: manager)
        let viewModel = ImportViewModel(importer: importer,
                                       saveChanges: { _ in throw CocoaError(.fileWriteNoPermission) },
                                       onRecoveryRequired: { recovery.requireImportRecovery($0) })

        await viewModel.importFiles([fixtureURL, fixtureURL], into: context)

        #expect(viewModel.isImportRecoveryRequired)
        #expect(viewModel.importErrors.count == 1)
        #expect(viewModel.importErrors.first?.message.contains("Cleanup also failed") == true)
        #expect(!recovery.isRecoveryComplete)
        viewModel.dismissImportErrors()
        recovery.clearError()
        #expect(recovery.errorMessage != nil)
        #expect(try ModelContext(context.container).fetchCount(FetchDescriptor<Book>()) == 0)
        manager.failCleanupMove = false
        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: library)
        #expect(recovery.isRecoveryComplete)
        #expect(try await !importer.hasPendingImports())
    }

    @Test func uncertainSaveResultNeverRemovesAFileReferencedByCommittedRows() async throws {
        let library = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        let context = try modelContext()
        let recovery = recoveryViewModel(library: library)
        let viewModel = ImportViewModel(importer: ImportService(libraryDirectory: library), saveChanges: { insertion in
            try insertion.save()
            throw CocoaError(.fileWriteUnknown)
        }, onRecoveryRequired: { recovery.requireImportRecovery($0) })

        await viewModel.importFiles([fixtureURL], into: context)

        let saved = try #require(ModelContext(context.container).fetch(FetchDescriptor<Book>()).first)
        let managed = library.appendingPathComponent(saved.libraryRelativePath)
        #expect(FileManager.default.fileExists(atPath: managed.path))
        #expect(viewModel.isImportRecoveryRequired)
        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: library)
        #expect(recovery.isRecoveryComplete)
        let expected = try Data(contentsOf: fixtureURL)
        #expect(try Data(contentsOf: managed) == expected)
    }

    @Test func postCommitCleanupFailureKeepsTheSavedBookAndItsVerifiedFile() async throws {
        let library = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        let context = try modelContext()
        let manager = ImportRecoveryTestFileManager()
        manager.failCompletedRemoval = true
        let recovery = recoveryViewModel(library: library, manager: manager)
        let importer = ImportService(libraryDirectory: library, fileManager: manager)
        let viewModel = ImportViewModel(importer: importer, onRecoveryRequired: { recovery.requireImportRecovery($0) })

        await viewModel.importFiles([fixtureURL], into: context)

        #expect(!recovery.isRecoveryComplete)
        #expect(viewModel.importErrors.first?.message.contains("The book was saved") == true)
        let saved = try #require(ModelContext(context.container).fetch(FetchDescriptor<Book>()).first)
        let managed = library.appendingPathComponent(saved.libraryRelativePath)
        let bytes = try Data(contentsOf: fixtureURL)
        #expect(try Data(contentsOf: managed) == bytes)
        manager.failCompletedRemoval = false
        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: library)
        #expect(recovery.isRecoveryComplete)
        #expect(try Data(contentsOf: managed) == bytes)
        await viewModel.importFiles([fixtureURL], into: context)
        #expect(!viewModel.isImportRecoveryRequired)
        #expect(viewModel.importErrors.first?.message == "This book is already in your library.")
        #expect(try ModelContext(context.container).fetchCount(FetchDescriptor<Book>()) == 1)
    }

    @Test func unknownPartialCopyIsPreservedAndBlocksRestartRecovery() async throws {
        let library = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        let context = try modelContext()
        let manager = ImportRecoveryTestFileManager()
        manager.failCopy = true
        manager.leavePartialCopy = true
        let recovery = recoveryViewModel(library: library, manager: manager)
        let viewModel = ImportViewModel(importer: ImportService(libraryDirectory: library, fileManager: manager),
                                       onRecoveryRequired: { recovery.requireImportRecovery($0) })

        await viewModel.importFiles([fixtureURL], into: context)

        #expect(viewModel.isImportRecoveryRequired)
        let files = try FileManager.default.contentsOfDirectory(at: library, includingPropertiesForKeys: nil)
        let partial = try #require(files.first { $0.pathExtension == "epub" })
        #expect(try Data(contentsOf: partial) == Data("partial copy".utf8))
        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: library)
        #expect(!recovery.isRecoveryComplete)
        #expect(try Data(contentsOf: partial) == Data("partial copy".utf8))
        #expect(try ModelContext(context.container).fetchCount(FetchDescriptor<Book>()) == 0)
    }

    @Test func startupUsesCommittedRowsRatherThanUnsavedWindowObjects() async throws {
        let library = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        let context = try modelContext()
        let imported = try await ImportService(libraryDirectory: library).importEpub(at: fixtureURL)
        context.autosaveEnabled = false
        context.insert(Book(id: imported.id, title: "Unsaved", author: "Tests", libraryRelativePath: imported.libraryRelativePath,
                            contentHash: imported.contentHash, format: .epub))
        let recovery = recoveryViewModel(library: library)

        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: library)

        #expect(recovery.isRecoveryComplete)
        #expect(!FileManager.default.fileExists(atPath: library.appendingPathComponent(imported.libraryRelativePath).path))
        #expect(try ModelContext(context.container).fetchCount(FetchDescriptor<Book>()) == 0)
        #expect(context.hasChanges)
    }

    @Test func overlappingBatchIsRejectedWithoutResettingActiveBatchResults() async throws {
        let library = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        let context = try modelContext()
        let manager = ImportRecoveryTestFileManager()
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        manager.copyRelease = release
        let stream = AsyncStream<Void> { continuation in
            manager.copyStarted = { continuation.yield(()) }
        }
        let viewModel = ImportViewModel(importer: ImportService(libraryDirectory: library, fileManager: manager))
        let recovery = recoveryViewModel(library: library)
        recovery.setImportActivityCheck { [weak viewModel] in viewModel?.isImporting == true }
        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: library)
        let active = Task { await viewModel.importFiles([fixtureURL], into: context) }
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        #expect(viewModel.isImporting)
        // Simulate another window's startup task while the copy is in flight.
        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: library)
        #expect(recovery.isRecoveryComplete)
        #expect(try ImportRecoveryJournalService().hasPendingImports(in: library))

        await viewModel.importFiles([URL(fileURLWithPath: "/tmp/second.cbr")], into: context)
        release.signal()
        await active.value

        #expect(!viewModel.isImporting)
        #expect(viewModel.importErrors.count == 1)
        #expect(viewModel.importErrors.first?.message.contains("already in progress") == true)
        #expect(try ModelContext(context.container).fetchCount(FetchDescriptor<Book>()) == 1)
    }

    private func recoveryViewModel(library: URL, manager: FileManager = .default) -> PrivateBookViewModel {
        PrivateBookViewModel(readerSessionStorage: ReaderSessionStorageService(rootDirectory: library.appendingPathComponent("Sessions")),
                             importJournal: ImportRecoveryJournalService(fileManager: manager))
    }
    private func modelContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Book.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }
    private func temporaryLibrary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private var fixtureURL: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/minimal.epub") }
}
