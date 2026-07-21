import AppKit
import Foundation

@MainActor
protocol CBZPageView: AnyObject {
    var renderedView: NSView { get }

    func displayImages(at fileURLs: [URL]) throws
    func clearImage()
}

@MainActor
final class CBZImageView: NSView, CBZPageView {
    private let imageViews = [NSImageView(), NSImageView()]
    private let stackView: NSStackView

    var renderedView: NSView { self }

    override init(frame frameRect: NSRect) {
        stackView = NSStackView(views: imageViews)
        super.init(frame: frameRect)
        configureStackView()
    }

    required init?(coder: NSCoder) {
        stackView = NSStackView(views: imageViews)
        super.init(coder: coder)
        configureStackView()
    }

    func displayImages(at fileURLs: [URL]) throws {
        guard !fileURLs.isEmpty, fileURLs.count <= imageViews.count else {
            throw BookRendererError.invalidLocator
        }
        let images = try fileURLs.map { fileURL -> NSImage in
            guard let image = NSImage(contentsOf: fileURL) else {
                throw BookRendererError.cannotOpenDocument
            }
            return image
        }

        for (index, imageView) in imageViews.enumerated() {
            imageView.image = images.indices.contains(index) ? images[index] : nil
            imageView.isHidden = !images.indices.contains(index)
        }
    }

    func clearImage() {
        for imageView in imageViews {
            imageView.image = nil
            imageView.isHidden = true
        }
    }

    private func configureStackView() {
        for imageView in imageViews {
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.imageAlignment = .alignCenter
        }
        stackView.orientation = .horizontal
        stackView.distribution = .fillEqually
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

@MainActor
final class CBZBookRenderer: BookRenderer {
    private let pageView: any CBZPageView
    private let publicationService: CbzPublicationService
    private var publication: CbzPublication?
    private var readingDirection: ComicReadingDirection = .leftToRight
    private var pageLayout: ComicPageLayout = .singlePage
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
        readingDirection = appearance.comicReadingDirection
        pageLayout = appearance.comicPageLayout
        if let currentLocator {
            try await go(to: currentLocator)
        }
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
        try await navigate(by: readingDirection == .leftToRight ? 1 : -1)
    }

    func goBackward() async throws -> Bool {
        try await navigate(by: readingDirection == .leftToRight ? -1 : 1)
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
        try pageView.displayImages(at: visiblePageURLs(startingAt: locator.spineIndex, in: publication))
        currentLocator = try pageLocator(for: locator.spineIndex, in: publication)
    }

    private func navigate(by offset: Int) async throws -> Bool {
        guard let currentLocator,
              let publication else {
            return false
        }
        let destinationIndex = currentLocator.spineIndex + (offset * pageStride)
        guard publication.pages.indices.contains(destinationIndex) else {
            return false
        }
        try await go(to: pageLocator(for: destinationIndex, in: publication))
        return true
    }

    private var pageStride: Int {
        pageLayout == .dualPage ? 2 : 1
    }

    private func visiblePageURLs(startingAt pageIndex: Int, in publication: CbzPublication) -> [URL] {
        switch readingDirection {
        case .leftToRight:
            let indexes = [pageIndex, pageIndex + 1].prefix(pageStride)
            return indexes.compactMap { publication.pages.indices.contains($0) ? publication.pages[$0].fileURL : nil }
        case .rightToLeft:
            let indexes = [pageIndex - 1, pageIndex].suffix(pageStride)
            return indexes.compactMap { publication.pages.indices.contains($0) ? publication.pages[$0].fileURL : nil }
        }
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
