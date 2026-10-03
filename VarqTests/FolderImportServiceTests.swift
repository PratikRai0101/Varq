import Foundation
import Testing
@testable import Varq

@MainActor
struct FolderImportServiceTests {
    @Test(arguments: [true, false])
    func holdsFolderAccessThroughAwaitedWorkAndBalancesOnlySuccessfulStarts(granted: Bool) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let nested = folder.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let source = nested.appendingPathComponent("book.EPUB")
        try FileManager.default.copyItem(at: fixtureURL, to: source)
        let access = FolderTestSecurityScope(granted: granted)
        let service = FolderImportService(securityScope: access)

        try await service.withBooks(in: folder) { discovery in
            #expect(discovery.files == [source])
            #expect(discovery.issues.isEmpty)
            #expect(access.started == [folder])
            #expect(access.stopped.isEmpty)
            await Task.yield()
            #expect(access.stopped.isEmpty)
            let expected = try Data(contentsOf: fixtureURL)
            #expect(try Data(contentsOf: discovery.files[0]) == expected)
        }

        #expect(access.stopped == (granted ? [folder] : []))
    }

    @Test(arguments: [true, false])
    func releasesFolderAccessWhenEnumerationOrAwaitedWorkFails(throwDuringWork: Bool) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manager = FolderTestDirectoryEnumerator()
        manager.failEnumeration = !throwDuringWork
        let access = FolderTestSecurityScope()
        let service = FolderImportService(directoryEnumerator: manager, securityScope: access)
        do {
            try await service.withBooks(in: folder) { _ in
                await Task.yield()
                throw CancellationError()
            }
            Issue.record("Expected enumeration or batch failure")
        } catch {
            #expect(access.stopped == [folder])
        }
        #expect(access.started == [folder])
        #expect(access.stopped == [folder])
    }

    @Test func rejectsAFileOrLinkedRootAsTheChosenFolder() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let link = folder.appendingPathComponent("linked-folder")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixtureURL.deletingLastPathComponent())
        let access = FolderTestSecurityScope()
        for url in [fixtureURL, link] {
            do {
                try await FolderImportService(securityScope: access).withBooks(in: url) { _ in
                    Issue.record("An invalid folder must not start a batch")
                }
                Issue.record("Expected invalid folder failure")
            } catch {
                #expect(!error.localizedDescription.isEmpty)
            }
        }
        #expect(access.stopped == [fixtureURL, link])
    }

    @Test func excludesSymlinksAndDirectoriesMasqueradingAsBooks() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent("real.epub")
        try FileManager.default.copyItem(at: fixtureURL, to: source)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("directory.epub"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("linked.epub"), withDestinationURL: fixtureURL)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("linked-directory"), withDestinationURL: fixtureURL.deletingLastPathComponent())

        try await FolderImportService().withBooks(in: folder) { discovery in
            #expect(discovery.files == [source])
            #expect(Set(discovery.issues.map(\.url.lastPathComponent)) == ["linked.epub", "linked-directory"])
        }
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/minimal.epub")
    }
}

@MainActor
final class FolderTestSecurityScope: FolderSecurityScopeAccessing {
    let granted: Bool
    private(set) var started: [URL] = []
    private(set) var stopped: [URL] = []
    init(granted: Bool = true) { self.granted = granted }
    func startAccessing(_ url: URL) -> Bool { started.append(url); return granted }
    func stopAccessing(_ url: URL) { stopped.append(url) }
}
