import CoreGraphics
import Foundation
import Vision

nonisolated struct VisiblePageImage: @unchecked Sendable {
    let cgImage: CGImage
}

nonisolated enum VisiblePageOCRError: Error, Equatable, Sendable {
    case noRecognizableText
}

nonisolated protocol VisiblePageTextRecognizing: Sendable {
    func recognizeText(in image: VisiblePageImage) async throws -> String
}

/// Performs bounded OCR entirely on-device for the reader's explicitly visible page.
nonisolated struct VisiblePageOCRService {
    private let recognizer: any VisiblePageTextRecognizing

    init(recognizer: any VisiblePageTextRecognizing = SystemVisiblePageTextRecognizer()) {
        self.recognizer = recognizer
    }

    func readingContext(for image: VisiblePageImage) async throws -> BoundedReadingContext {
        let text = try await recognizer.recognizeText(in: image)
        let boundedText = String(text.prefix(BoundedReadingContext.maximumCharacterCount))
        do {
            return try BoundedReadingContext(selectedText: boundedText)
        } catch BoundedReadingContextError.empty {
            throw VisiblePageOCRError.noRecognizableText
        }
    }
}

nonisolated struct SystemVisiblePageTextRecognizer: VisiblePageTextRecognizing {
    func recognizeText(in image: VisiblePageImage) async throws -> String {
        let cgImage = image.cgImage
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try handler.perform([request])
            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }
}
