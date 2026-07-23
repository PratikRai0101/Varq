import Foundation

struct ReaderTableOfContentsEntry: Identifiable, Equatable {
    let id: Int
    let title: String
    let locator: BookLocator
}

@MainActor
protocol TableOfContentsProviding: AnyObject {
    func tableOfContents() async throws -> [ReaderTableOfContentsEntry]
}
