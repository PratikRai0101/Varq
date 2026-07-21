import AppKit
import Foundation
import Testing
@testable import Varq

@MainActor
struct CBZBookRendererTests {
    @Test func displaysImagePagesAndNavigatesBySequence() async throws {
        let pageView = FakeCBZPageView()
        let renderer = CBZBookRenderer(pageView: pageView)

        try await renderer.open(bookURL: fixtureURL, at: nil)

        #expect(renderer.currentLocator?.format == .cbz)
        #expect(renderer.currentLocator?.spineIndex == 0)
        #expect(renderer.currentLocator?.resourceHref == "001.png")
        #expect(pageView.displayedURL?.lastPathComponent == "001.png")

        #expect(try await renderer.goForward())
        #expect(renderer.currentLocator?.spineIndex == 1)
        #expect(pageView.displayedURL?.lastPathComponent == "002.png")
        #expect(!(try await renderer.goForward()))

        #expect(try await renderer.goBackward())
        #expect(renderer.currentLocator?.spineIndex == 0)
    }

    @Test func restoresAPageFromItsCbzLocator() async throws {
        let pageView = FakeCBZPageView()
        let renderer = CBZBookRenderer(pageView: pageView)
        let locator = try BookLocator(format: .cbz, spineIndex: 1, resourceHref: "002.png", progression: 0)

        try await renderer.open(bookURL: fixtureURL, at: locator)

        #expect(renderer.currentLocator == locator)
        #expect(pageView.displayedURL?.lastPathComponent == "002.png")
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/minimal.cbz")
    }
}

@MainActor
private final class FakeCBZPageView: CBZPageView {
    let renderedView = NSView()
    private(set) var displayedURL: URL?

    func displayImage(at fileURL: URL) throws {
        displayedURL = fileURL
    }

    func clearImage() {
        displayedURL = nil
    }
}
