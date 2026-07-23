import Foundation
import FoundationModels

/// Reports whether Varq can offer on-device reading aids on the current Mac.
nonisolated enum AIAssistantAvailability: Equatable, Sendable {
    case available
    case unavailable(AIAssistantUnavailableReason)
}

nonisolated enum AIAssistantUnavailableReason: Equatable, Sendable {
    case unsupportedOS
    case deviceNotEligible
    case appleIntelligenceDisabled
    case modelNotReady
    case unavailable
}

/// A reader-selected operation that produces a non-authoritative reading aid.
nonisolated enum ReadingAidKind: Equatable, Sendable {
    case explain
    case simplify
    case summarize
    case discussionQuestions
    case chapterRecap

    var displayName: String {
        switch self {
        case .explain: "Explain"
        case .simplify: "Simplify"
        case .summarize: "Summarize"
        case .discussionQuestions: "Discussion questions"
        case .chapterRecap: "Chapter recap"
        }
    }
}

/// Text explicitly selected by a reader, limited to a size suitable for an on-device request.
nonisolated struct BoundedReadingContext: Sendable {
    static let maximumCharacterCount = 12_000

    let selectedText: String

    init(selectedText: String) throws {
        let trimmedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw BoundedReadingContextError.empty
        }
        guard trimmedText.count <= Self.maximumCharacterCount else {
            throw BoundedReadingContextError.exceedsMaximumLength
        }
        self.selectedText = trimmedText
    }
}

nonisolated enum BoundedReadingContextError: Error, Equatable, Sendable {
    case empty
    case exceedsMaximumLength
}

/// A generated response that is not persisted unless the reader explicitly saves it.
nonisolated struct GeneratedReadingAid: Equatable, Sendable {
    let text: String
}

nonisolated enum AIAssistantServiceError: Error, Equatable, Sendable {
    case unavailable(AIAssistantUnavailableReason)
}

/// A seam for checking system-model availability without coupling callers to Foundation Models.
nonisolated protocol AIAssistantAvailabilityProviding: Sendable {
    func availability() -> AIAssistantAvailability
}

/// A seam for generating text without exposing Foundation Models to callers or tests.
nonisolated protocol AIAssistantResponding: Sendable {
    func respond(to prompt: String) async throws -> String
}

/// The system Foundation Models availability adapter.
nonisolated struct SystemAIAssistantAvailabilityProvider: AIAssistantAvailabilityProviding {
    func availability() -> AIAssistantAvailability {
        guard #available(macOS 26.0, *) else {
            return .unavailable(.unsupportedOS)
        }

        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(.appleIntelligenceDisabled)
        case .unavailable(.modelNotReady):
            return .unavailable(.modelNotReady)
        @unknown default:
            return .unavailable(.unavailable)
        }
    }
}

nonisolated struct SystemAIAssistantResponder: AIAssistantResponding {
    func respond(to prompt: String) async throws -> String {
        guard #available(macOS 26.0, *) else {
            throw AIAssistantServiceError.unavailable(.unsupportedOS)
        }
        return try await respondOnSupportedSystem(to: prompt)
    }

    @available(macOS 26.0, *)
    private func respondOnSupportedSystem(to prompt: String) async throws -> String {
        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        return response.content
    }
}

/// The entry point for future on-device, bounded-context reading aids.
nonisolated struct AIAssistantService {
    private let availabilityProvider: any AIAssistantAvailabilityProviding
    private let responder: any AIAssistantResponding

    init(
        availabilityProvider: any AIAssistantAvailabilityProviding = SystemAIAssistantAvailabilityProvider(),
        responder: any AIAssistantResponding = SystemAIAssistantResponder()
    ) {
        self.availabilityProvider = availabilityProvider
        self.responder = responder
    }

    var availability: AIAssistantAvailability {
        availabilityProvider.availability()
    }

    func generate(
        _ kind: ReadingAidKind,
        using context: BoundedReadingContext
    ) async throws -> GeneratedReadingAid {
        guard case .available = availability else {
            if case .unavailable(let reason) = availability {
                throw AIAssistantServiceError.unavailable(reason)
            }
            throw AIAssistantServiceError.unavailable(.unavailable)
        }

        return GeneratedReadingAid(text: try await responder.respond(to: prompt(for: kind, context: context)))
    }

    private func prompt(for kind: ReadingAidKind, context: BoundedReadingContext) -> String {
        let instruction: String
        switch kind {
        case .explain:
            instruction = "Explain the selected passage in clear, concise language."
        case .simplify:
            instruction = "Rewrite the selected passage in simpler language while preserving its meaning."
        case .summarize:
            instruction = "Summarize the selected passage concisely."
        case .discussionQuestions:
            instruction = "Write up to five thoughtful discussion questions about the selected passage as a numbered list."
        case .chapterRecap:
            instruction = "Write a short recap of this chapter, followed by key ideas and up to three reflection questions."
        }

        return """
        \(instruction) Use only the passage below. If the passage does not contain enough information, say so rather than inventing details. Respond in plain text and do not use Markdown.

        Reading context:
        \(context.selectedText)
        """
    }
}
