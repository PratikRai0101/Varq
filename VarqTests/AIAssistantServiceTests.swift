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
