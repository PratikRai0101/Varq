import Foundation

@MainActor
protocol ChapterTextProviding: AnyObject {
    func currentChapterText() async throws -> String?
}
