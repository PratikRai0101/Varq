import AppKit
import Foundation

@MainActor
protocol CBZPageView: AnyObject {
    var renderedView: NSView { get }

    func displayImages(at fileURLs: [URL]) throws
    func setPageFit(_ pageFit: ComicPageFit)
    func clearImage()
}

@MainActor
final class CBZImageView: NSScrollView, CBZPageView {
    private let canvasView = ComicImageCanvasView()

    var renderedView: NSView { self }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureScrollView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureScrollView()
    }

    override func layout() {
        super.layout()
        canvasView.updateViewportSize(contentView.bounds.size)
    }

    func displayImages(at fileURLs: [URL]) throws {
        guard !fileURLs.isEmpty, fileURLs.count <= ComicImageCanvasView.maximumImageCount else {
            throw BookRendererError.invalidLocator
        }
        let images = try fileURLs.map { fileURL -> NSImage in
            guard let image = NSImage(contentsOf: fileURL) else {
                throw BookRendererError.cannotOpenDocument
            }
            return image
        }
        canvasView.images = images
    }

    func setPageFit(_ pageFit: ComicPageFit) {
        canvasView.pageFit = pageFit
    }

    func clearImage() {
        canvasView.images = []
    }

    private func configureScrollView() {
        drawsBackground = false
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        documentView = canvasView
    }
}

@MainActor
private final class ComicImageCanvasView: NSView {
    static let maximumImageCount = 2

    var images: [NSImage] = [] {
        didSet { updateCanvasSize() }
    }
    var pageFit: ComicPageFit = .fitWidth {
        didSet { updateCanvasSize() }
    }

    private var viewportSize = NSSize(width: 1, height: 1)

    override var isFlipped: Bool { true }

    func updateViewportSize(_ viewportSize: NSSize) {
        guard self.viewportSize != viewportSize else {
            return
        }
        self.viewportSize = viewportSize
        updateCanvasSize()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        var horizontalOrigin: CGFloat = 0
        for image in images {
            let pageSize = renderedSize(for: image)
            let verticalOrigin = max((bounds.height - pageSize.height) / 2, 0)
            image.draw(
                in: NSRect(origin: NSPoint(x: horizontalOrigin, y: verticalOrigin), size: pageSize),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            horizontalOrigin += pageSize.width
        }
    }

    private func updateCanvasSize() {
        let sizes = images.map(renderedSize(for:))
        let width = max(sizes.reduce(0) { $0 + $1.width }, viewportSize.width)
        let height = max(sizes.map(\.height).max() ?? 0, viewportSize.height)
        frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        needsDisplay = true
    }

    private func renderedSize(for image: NSImage) -> NSSize {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return .zero
        }

        switch pageFit {
        case .fitWidth:
            let pageWidth = viewportSize.width / CGFloat(max(images.count, 1))
            return NSSize(width: pageWidth, height: imageSize.height * (pageWidth / imageSize.width))
        case .fitHeight:
            let pageHeight = viewportSize.height
            return NSSize(width: imageSize.width * (pageHeight / imageSize.height), height: pageHeight)
        case .actualSize:
            return imageSize
        }
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
        pageView.setPageFit(appearance.comicPageFit)
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
