import AppKit
import Foundation

@MainActor
protocol CBZPageView: AnyObject {
    var renderedView: NSView { get }

    func displayImage(at fileURL: URL) throws
    func clearImage()
}

@MainActor
final class CBZImageView: NSImageView, CBZPageView {
    var renderedView: NSView { self }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageScaling = .scaleProportionallyUpOrDown
        imageAlignment = .alignCenter
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        imageScaling = .scaleProportionallyUpOrDown
        imageAlignment = .alignCenter
    }

    func displayImage(at fileURL: URL) throws {
        guard let image = NSImage(contentsOf: fileURL) else {
            throw BookRendererError.cannotOpenDocument
        }
        self.image = image
    }

    func clearImage() {
        image = nil
    }
}

@MainActor
final class CBZBookRenderer: BookRenderer {
    private let pageView: any CBZPageView
    private let publicationService: CbzPublicationService
    private var publication: CbzPublication?
    private(set) var currentLocator: BookLocator?

    var view: NSView { pageView.renderedView }
    let supportedFormat: BookFormat = .cbz

    init() {
        pageView = CBZImageView()
        publicationService = CbzPublicationService()
    }

    init(pageView: any CBZPageView, publicationService: CbzPublicationService = CbzPublicationService()) {
        self.pageView = pageView
        self.publicationService = publicationService
    }

    func open(bookURL: URL, at locator: BookLocator? = nil) async throws {
        await close()

        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Varq-CBZ", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let publication = try await publicationService.extract(at: bookURL, into: rootDirectory)
        self.publication = publication

        let initialLocator = try locator ?? BookLocator(
            format: .cbz,
            spineIndex: 0,
            progression: 0
        )
        do {
            try await go(to: initialLocator)
        } catch {
            await close()
            throw error
        }
    }

    func updateReadingAppearance(_ appearance: ReadingAppearance) async throws {
        // Image pages retain their source artwork; comic-specific presentation is configured separately.
    }

    func close() async {
        if let publication {
            try? await publicationService.remove(publication)
        }
        publication = nil
        currentLocator = nil
        pageView.clearImage()
    }

    func goForward() async throws -> Bool {
        guard let currentLocator,
              let publication,
              currentLocator.spineIndex + 1 < publication.pages.count else {
            return false
        }

        try await go(to: pageLocator(for: currentLocator.spineIndex + 1, in: publication))
        return true
    }

    func goBackward() async throws -> Bool {
        guard let currentLocator,
              let publication,
              currentLocator.spineIndex > 0 else {
            return false
        }

        try await go(to: pageLocator(for: currentLocator.spineIndex - 1, in: publication))
        return true
    }

    func go(to locator: BookLocator) async throws {
        guard locator.format == supportedFormat else {
            throw BookRendererError.incompatibleLocatorFormat(locator.format)
        }
        guard let publication,
              publication.pages.indices.contains(locator.spineIndex) else {
            throw BookRendererError.invalidLocator
        }

        let page = publication.pages[locator.spineIndex]
        guard locator.resourceHref == nil || locator.resourceHref == page.archivePath else {
            throw BookRendererError.invalidLocator
        }
        try pageView.displayImage(at: page.fileURL)
        currentLocator = try pageLocator(for: locator.spineIndex, in: publication)
    }

    private func pageLocator(for pageIndex: Int, in publication: CbzPublication) throws -> BookLocator {
        try BookLocator(
            format: .cbz,
            spineIndex: pageIndex,
            resourceHref: publication.pages[pageIndex].archivePath,
            progression: 0
        )
    }
}
