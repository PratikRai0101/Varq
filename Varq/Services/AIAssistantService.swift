import Foundation
import FoundationModels

/// Reports whether Varq can offer on-device reading aids on the current Mac.
enum AIAssistantAvailability: Equatable, Sendable {
    case available
    case unavailable(AIAssistantUnavailableReason)
}

enum AIAssistantUnavailableReason: Equatable, Sendable {
    case unsupportedOS
    case deviceNotEligible
    case appleIntelligenceDisabled
    case modelNotReady
    case unavailable
}

/// A seam for checking system-model availability without coupling callers to Foundation Models.
protocol AIAssistantAvailabilityProviding: Sendable {
    func availability() -> AIAssistantAvailability
}

/// The system Foundation Models availability adapter.
struct SystemAIAssistantAvailabilityProvider: AIAssistantAvailabilityProviding {
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

/// The entry point for future on-device, bounded-context reading aids.
struct AIAssistantService {
    private let availabilityProvider: any AIAssistantAvailabilityProviding

    init(availabilityProvider: any AIAssistantAvailabilityProviding = SystemAIAssistantAvailabilityProvider()) {
        self.availabilityProvider = availabilityProvider
    }

    var availability: AIAssistantAvailability {
        availabilityProvider.availability()
    }
}
