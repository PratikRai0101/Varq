import CoreGraphics

/// Supplies the reader's current page for bounded, local OCR.
@MainActor
protocol VisiblePageProviding: AnyObject {
    func visiblePageImage() throws -> CGImage?
}
