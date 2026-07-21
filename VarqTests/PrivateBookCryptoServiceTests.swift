import CryptoKit
import Foundation
import Testing
@testable import Varq

struct PrivateBookCryptoServiceTests {
    @Test func encryptsManagedContentAndDecryptsItIntoASessionFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let managedFileURL = directory.appendingPathComponent("book.epub")
        let sessionFileURL = directory.appendingPathComponent("Session/book.epub")
        let plaintext = Data("private book content".utf8)
        try plaintext.write(to: managedFileURL)
        let service = PrivateBookCryptoService()
        let key = SymmetricKey(size: .bits256)

        try service.encryptManagedFile(at: managedFileURL, using: key)

        #expect(try Data(contentsOf: managedFileURL) != plaintext)
        try service.decryptManagedFile(at: managedFileURL, to: sessionFileURL, using: key)
        #expect(try Data(contentsOf: sessionFileURL) == plaintext)
    }
}
