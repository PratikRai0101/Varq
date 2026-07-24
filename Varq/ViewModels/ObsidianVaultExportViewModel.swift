import Foundation
import Observation

@MainActor
@Observable
final class ObsidianVaultExportViewModel {
    private let destinationService: any ObsidianVaultFolderSelecting & ObsidianVaultBookmarkStoring
    private let exportService: ObsidianVaultExportService

    private(set) var report: ObsidianVaultExportReport?
    private(set) var errorMessage: String?

    init(
        destinationService: (any ObsidianVaultFolderSelecting & ObsidianVaultBookmarkStoring)? = nil,
        exportService: ObsidianVaultExportService = ObsidianVaultExportService()
    ) {
        self.destinationService = destinationService ?? ObsidianVaultDestinationService()
        self.exportService = exportService
    }

    func clearResult() {
        report = nil
        errorMessage = nil
    }

    func chooseDestinationAndExport(books: [Book]) {
        guard let url = destinationService.selectFolder() else { return }
        export(books: books, to: url)
    }

    func exportToSavedDestination(books: [Book]) {
        do {
            guard let url = try destinationService.resolve() else {
                chooseDestinationAndExport(books: books)
                return
            }
            export(books: books, to: url)
        } catch {
            errorMessage = "Varq could not access the saved Obsidian vault. Choose the vault again."
        }
    }

    private func export(books: [Book], to url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Varq needs permission to access this vault. Choose it again."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            report = try exportService.export(books: books, to: url)
            errorMessage = nil
        } catch {
            errorMessage = "Varq could not export this vault: \(error.localizedDescription)"
        }
    }
}
