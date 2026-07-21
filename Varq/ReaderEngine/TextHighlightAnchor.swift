import Foundation

/// A versioned, renderer-neutral text range persisted in `Highlight.locatorData`.
/// Exact offsets are UTF-16 offsets in the text content unit identified by `locator`.
struct TextHighlightAnchor: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let locator: BookLocator
    let precision: TextHighlightPrecision
    let startOffset: Int?
    let endOffset: Int?
    let approximatePosition: Double?
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

        self.schemaVersion = schemaVersion
        self.locator = locator
        self.precision = .exactTextRange
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.approximatePosition = nil
        self.quote = quote
    }

    /// PDFKit does not expose a stable selected-character range. This records a page-level fallback.
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

        schemaVersion = Self.currentSchemaVersion
        self.locator = locator
        precision = .coarsePagePosition
        startOffset = nil
        endOffset = nil
        self.approximatePosition = approximatePosition
        self.quote = quote
    }

    private static func validateQuote(_ quote: TextQuoteSelector) throws {
        guard !quote.exact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TextHighlightAnchorError.emptyQuote
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, locator, precision, startOffset, endOffset, approximatePosition, quote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw TextHighlightAnchorError.unsupportedSchemaVersion(schemaVersion)
        }

        let locator = try container.decode(BookLocator.self, forKey: .locator)
        let precision = try container.decode(TextHighlightPrecision.self, forKey: .precision)
        let quote = try container.decode(TextQuoteSelector.self, forKey: .quote)
        switch precision {
        case .exactTextRange:
            try self.init(
                schemaVersion: schemaVersion,
                locator: locator,
                startOffset: try container.decode(Int.self, forKey: .startOffset),
                endOffset: try container.decode(Int.self, forKey: .endOffset),
                quote: quote
            )
        case .coarsePagePosition:
            try self.init(
                coarsePDFLocator: locator,
                approximatePosition: try container.decode(Double.self, forKey: .approximatePosition),
                quote: quote
            )
        }
    }
}

enum TextHighlightPrecision: String, Codable, Sendable {
    case exactTextRange
    case coarsePagePosition
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
    case emptyQuote
}
