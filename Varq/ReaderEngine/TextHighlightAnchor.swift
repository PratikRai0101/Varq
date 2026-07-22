import CoreGraphics
import Foundation

/// A versioned, renderer-neutral text range persisted in `Highlight.locatorData`.
/// Exact offsets are UTF-16 offsets in the text content unit identified by `locator`.
struct TextHighlightAnchor: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 3
    private static let legacySchemaVersion = 2

    let schemaVersion: Int
    let locator: BookLocator
    let precision: TextHighlightPrecision
    let startOffset: Int?
    let endOffset: Int?
    let approximatePosition: Double?
    let pdfSelectionRects: [NormalizedPDFRect]?
    let quote: TextQuoteSelector

    init(
        schemaVersion: Int = TextHighlightAnchor.currentSchemaVersion,
        locator: BookLocator,
        startOffset: Int,
        endOffset: Int,
        quote: TextQuoteSelector
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw TextHighlightAnchorError.unsupportedSchemaVersion(schemaVersion)
        }
        guard locator.format == .epub || locator.format == .pdf else {
            throw TextHighlightAnchorError.unsupportedFormat(locator.format)
        }
        guard startOffset >= 0, endOffset > startOffset else {
            throw TextHighlightAnchorError.invalidTextRange(start: startOffset, end: endOffset)
        }
        try Self.validateQuote(quote)

        self.init(
            schemaVersion: schemaVersion,
            locator: locator,
            precision: .exactTextRange,
            startOffset: startOffset,
            endOffset: endOffset,
            approximatePosition: nil,
            pdfSelectionRects: nil,
            quote: quote
        )
    }

    /// A legacy page-level fallback for highlights created before PDF geometry was persisted.
    init(
        coarsePDFLocator locator: BookLocator,
        approximatePosition: Double,
        quote: TextQuoteSelector
    ) throws {
        guard locator.format == .pdf else {
            throw TextHighlightAnchorError.unsupportedFormat(locator.format)
        }
        guard approximatePosition.isFinite, (0...1).contains(approximatePosition) else {
            throw TextHighlightAnchorError.invalidApproximatePosition(approximatePosition)
        }
        try Self.validateQuote(quote)

        self.init(
            schemaVersion: Self.currentSchemaVersion,
            locator: locator,
            precision: .coarsePagePosition,
            startOffset: nil,
            endOffset: nil,
            approximatePosition: approximatePosition,
            pdfSelectionRects: nil,
            quote: quote
        )
    }

    /// PDFKit exposes stable page geometry for a selected passage but not a stable character range.
    init(
        pdfLocator locator: BookLocator,
        selectionRects: [NormalizedPDFRect],
        quote: TextQuoteSelector
    ) throws {
        guard locator.format == .pdf else {
            throw TextHighlightAnchorError.unsupportedFormat(locator.format)
        }
        guard !selectionRects.isEmpty else {
            throw TextHighlightAnchorError.emptyPDFSelectionGeometry
        }
        try Self.validateQuote(quote)

        self.init(
            schemaVersion: Self.currentSchemaVersion,
            locator: locator,
            precision: .pdfSelectionGeometry,
            startOffset: nil,
            endOffset: nil,
            approximatePosition: nil,
            pdfSelectionRects: selectionRects,
            quote: quote
        )
    }

    private init(
        schemaVersion: Int,
        locator: BookLocator,
        precision: TextHighlightPrecision,
        startOffset: Int?,
        endOffset: Int?,
        approximatePosition: Double?,
        pdfSelectionRects: [NormalizedPDFRect]?,
        quote: TextQuoteSelector
    ) {
        self.schemaVersion = schemaVersion
        self.locator = locator
        self.precision = precision
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.approximatePosition = approximatePosition
        self.pdfSelectionRects = pdfSelectionRects
        self.quote = quote
    }

    private static func validateQuote(_ quote: TextQuoteSelector) throws {
        guard !quote.exact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TextHighlightAnchorError.emptyQuote
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, locator, precision, startOffset, endOffset, approximatePosition, pdfSelectionRects, quote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.legacySchemaVersion || schemaVersion == Self.currentSchemaVersion else {
            throw TextHighlightAnchorError.unsupportedSchemaVersion(schemaVersion)
        }

        let locator = try container.decode(BookLocator.self, forKey: .locator)
        let precision = try container.decode(TextHighlightPrecision.self, forKey: .precision)
        let quote = try container.decode(TextQuoteSelector.self, forKey: .quote)
        try Self.validateQuote(quote)

        switch precision {
        case .exactTextRange:
            guard locator.format == .epub || locator.format == .pdf else {
                throw TextHighlightAnchorError.unsupportedFormat(locator.format)
            }
            let startOffset = try container.decode(Int.self, forKey: .startOffset)
            let endOffset = try container.decode(Int.self, forKey: .endOffset)
            guard startOffset >= 0, endOffset > startOffset else {
                throw TextHighlightAnchorError.invalidTextRange(start: startOffset, end: endOffset)
            }
            self.init(
                schemaVersion: schemaVersion,
                locator: locator,
                precision: precision,
                startOffset: startOffset,
                endOffset: endOffset,
                approximatePosition: nil,
                pdfSelectionRects: nil,
                quote: quote
            )
        case .coarsePagePosition:
            guard locator.format == .pdf else {
                throw TextHighlightAnchorError.unsupportedFormat(locator.format)
            }
            let approximatePosition = try container.decode(Double.self, forKey: .approximatePosition)
            guard approximatePosition.isFinite, (0...1).contains(approximatePosition) else {
                throw TextHighlightAnchorError.invalidApproximatePosition(approximatePosition)
            }
            self.init(
                schemaVersion: schemaVersion,
                locator: locator,
                precision: precision,
                startOffset: nil,
                endOffset: nil,
                approximatePosition: approximatePosition,
                pdfSelectionRects: nil,
                quote: quote
            )
        case .pdfSelectionGeometry:
            guard schemaVersion == Self.currentSchemaVersion else {
                throw TextHighlightAnchorError.unsupportedSchemaVersion(schemaVersion)
            }
            guard locator.format == .pdf else {
                throw TextHighlightAnchorError.unsupportedFormat(locator.format)
            }
            let selectionRects = try container.decode([NormalizedPDFRect].self, forKey: .pdfSelectionRects)
            guard !selectionRects.isEmpty else {
                throw TextHighlightAnchorError.emptyPDFSelectionGeometry
            }
            self.init(
                schemaVersion: schemaVersion,
                locator: locator,
                precision: precision,
                startOffset: nil,
                endOffset: nil,
                approximatePosition: nil,
                pdfSelectionRects: selectionRects,
                quote: quote
            )
        }
    }
}

/// A PDF page-space rectangle normalized to its media box, so it remains valid across view scale changes.
struct NormalizedPDFRect: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(rect: CGRect, within pageBounds: CGRect) throws {
        guard pageBounds.width > 0, pageBounds.height > 0 else {
            throw TextHighlightAnchorError.invalidPDFSelectionGeometry
        }
        let clippedRect = rect.intersection(pageBounds)
        guard !clippedRect.isNull, !clippedRect.isEmpty else {
            throw TextHighlightAnchorError.invalidPDFSelectionGeometry
        }

        x = (clippedRect.minX - pageBounds.minX) / pageBounds.width
        y = (clippedRect.minY - pageBounds.minY) / pageBounds.height
        width = clippedRect.width / pageBounds.width
        height = clippedRect.height / pageBounds.height

        guard [x, y, width, height].allSatisfy(\.isFinite),
              x >= 0, y >= 0, width > 0, height > 0,
              x + width <= 1, y + height <= 1 else {
            throw TextHighlightAnchorError.invalidPDFSelectionGeometry
        }
    }

    func rect(within pageBounds: CGRect) -> CGRect {
        CGRect(
            x: pageBounds.minX + pageBounds.width * x,
            y: pageBounds.minY + pageBounds.height * y,
            width: pageBounds.width * width,
            height: pageBounds.height * height
        )
    }
}

enum TextHighlightPrecision: String, Codable, Sendable {
    case exactTextRange
    case coarsePagePosition
    case pdfSelectionGeometry
}

struct TextQuoteSelector: Codable, Equatable, Sendable {
    let exact: String
    let prefix: String?
    let suffix: String?

    init(exact: String, prefix: String? = nil, suffix: String? = nil) {
        self.exact = exact
        self.prefix = prefix
        self.suffix = suffix
    }
}

enum TextHighlightAnchorError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case unsupportedFormat(BookFormat)
    case invalidTextRange(start: Int, end: Int)
    case invalidApproximatePosition(Double)
    case invalidPDFSelectionGeometry
    case emptyPDFSelectionGeometry
    case emptyQuote
}
