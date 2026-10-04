import Foundation

final class ImportRecoveryTestFileManager: FileManager, @unchecked Sendable {
    var failCopy = false
    var leavePartialCopy = false
    var failCleanupMove = false
    var failCompletedRemoval = false
    var copyStarted: (@Sendable () -> Void)?
    var copyRelease: DispatchSemaphore?
    var mutateOriginalAfterCopy = false

    override func copyItem(at source: URL, to destination: URL) throws {
        if let copyRelease {
            copyStarted?()
            copyRelease.wait()
        }
        if failCopy {
            if leavePartialCopy { try Data("partial copy".utf8).write(to: destination) }
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.copyItem(at: source, to: destination)
        if mutateOriginalAfterCopy { try Data("changed original".utf8).write(to: source) }
    }

    override func moveItem(at source: URL, to destination: URL) throws {
        if failCleanupMove, destination.lastPathComponent == "payload" { throw CocoaError(.fileWriteNoPermission) }
        try super.moveItem(at: source, to: destination)
    }

    override func removeItem(at url: URL) throws {
        if failCompletedRemoval, url.lastPathComponent.hasPrefix(".completed-") { throw CocoaError(.fileWriteNoPermission) }
        try super.removeItem(at: url)
    }
}
