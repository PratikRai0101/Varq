import CoreGraphics
import Testing
@testable import Varq

struct AIAssistantServiceTests {
    @Test func reportsInjectedModelAvailability() {
        let service = AIAssistantService(
            availabilityProvider: TestAIAssistantAvailabilityProvider(.available)
        )

        #expect(service.availability == .available)
    }

    @Test func preservesTheReasonIntelligenceIsUnavailable() {
        let service = AIAssistantService(
            availabilityProvider: TestAIAssistantAvailabilityProvider(.unavailable(.appleIntelligenceDisabled))
        )

        #expect(service.availability == .unavailable(.appleIntelligenceDisabled))
    }

    @Test func generatesAnExplanationFromBoundedSelectedText() async throws {
        let responder = RecordingAIAssistantResponder(response: "A short explanation.")
        let service = AIAssistantService(
            availabilityProvider: TestAIAssistantAvailabilityProvider(.available),
            responder: responder
        )
        let context = try BoundedReadingContext(selectedText: "The moon reflected on the river.")

        let aid = try await service.generate(.explain, using: context)

        #expect(aid.text == "A short explanation.")
        #expect(await responder.prompts == [
            """
            Explain the selected passage in clear, concise language. Use only the passage below. If the passage does not contain enough information, say so rather than inventing details. Respond in plain text and do not use Markdown.

            Reading context:
            The moon reflected on the river.
            """
        ])
    }

    @Test func recapsLongChaptersBySummarizingBoundedChunks() async throws {
        let responder = RecordingAIAssistantResponder(response: "Condensed chapter")
        let service = AIAssistantService(
            availabilityProvider: TestAIAssistantAvailabilityProvider(.available),
            responder: responder
        )

        let recap = try await service.generateChapterRecap(
            from: String(repeating: "a", count: BoundedReadingContext.maximumCharacterCount + 1)
        )

        #expect(recap.text == "Condensed chapter")
        #expect(await responder.prompts.count == 3)
    }

    @Test func generatesAVisiblePageExplanationFromOCRText() async throws {
        let responder = RecordingAIAssistantResponder(response: "A page explanation.")
        let service = AIAssistantService(
            availabilityProvider: TestAIAssistantAvailabilityProvider(.available),
            responder: responder
        )
        let context = try BoundedReadingContext(selectedText: "A caption from the page.")

        let aid = try await service.generateVisiblePageExplanation(using: context)

        #expect(aid.text == "A page explanation.")
        #expect((await responder.prompts).first?.contains("extracted locally with OCR") == true)
    }

    @Test func boundsVisiblePageOCRTextBeforeSendingItToTheModel() async throws {
        let ocrService = VisiblePageOCRService(
            recognizer: TestVisiblePageTextRecognizer(text: String(repeating: "a", count: BoundedReadingContext.maximumCharacterCount + 10))
        )

        let context = try await ocrService.readingContext(for: VisiblePageImage(cgImage: try testImage()))

        #expect(context.selectedText.count == BoundedReadingContext.maximumCharacterCount)
    }

    @Test func rejectsContextThatExceedsTheBound() throws {
        let text = String(repeating: "a", count: BoundedReadingContext.maximumCharacterCount + 1)

        #expect(throws: BoundedReadingContextError.exceedsMaximumLength) {
            try BoundedReadingContext(selectedText: text)
        }
    }

    @Test func doesNotCallTheModelWhenItIsUnavailable() async {
        let responder = RecordingAIAssistantResponder(response: "Should not be used.")
        let service = AIAssistantService(
            availabilityProvider: TestAIAssistantAvailabilityProvider(.unavailable(.deviceNotEligible)),
            responder: responder
        )
        let context = try! BoundedReadingContext(selectedText: "A passage.")

        await #expect(throws: AIAssistantServiceError.unavailable(.deviceNotEligible)) {
            try await service.generate(.summarize, using: context)
        }
        #expect(await responder.prompts.isEmpty)
    }
}

private struct TestAIAssistantAvailabilityProvider: AIAssistantAvailabilityProviding {
    let value: AIAssistantAvailability

    init(_ value: AIAssistantAvailability) {
        self.value = value
    }

    func availability() -> AIAssistantAvailability {
        value
    }
}

private struct TestVisiblePageTextRecognizer: VisiblePageTextRecognizing {
    let text: String

    func recognizeText(in image: VisiblePageImage) async throws -> String {
        text
    }
}

private func testImage() throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let image = context.makeImage() else {
        throw TestImageError.unavailable
    }
    return image
}

private enum TestImageError: Error {
    case unavailable
}

private actor RecordingAIAssistantResponder: AIAssistantResponding {
    private(set) var prompts: [String] = []
    let response: String

    init(response: String) {
        self.response = response
    }

    func respond(to prompt: String) async throws -> String {
        prompts.append(prompt)
        return response
    }
}
