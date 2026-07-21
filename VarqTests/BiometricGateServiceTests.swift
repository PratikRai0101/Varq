import Foundation
import Testing
@testable import Varq

@MainActor
struct BiometricGateServiceTests {
    @Test func evaluatesBiometricsAfterCheckingAvailability() async throws {
        let context = FakeBiometricAuthenticationContext()
        let service = BiometricGateService(authenticationContext: context)

        try await service.authenticate(localizedReason: "Unlock private shelf")

        #expect(context.didCheckAvailability)
        #expect(context.localizedReason == "Unlock private shelf")
    }

    @Test func doesNotEvaluateWhenBiometricsAreUnavailable() async {
        let context = FakeBiometricAuthenticationContext(availabilityError: BiometricGateError.unavailable)
        let service = BiometricGateService(authenticationContext: context)

        await #expect(throws: BiometricGateError.unavailable) {
            try await service.authenticate(localizedReason: "Unlock private shelf")
        }
        #expect(context.localizedReason == nil)
    }
}

@MainActor
private final class FakeBiometricAuthenticationContext: BiometricAuthenticationContext {
    let availabilityError: Error?
    private(set) var didCheckAvailability = false
    private(set) var localizedReason: String?

    init(availabilityError: Error? = nil) {
        self.availabilityError = availabilityError
    }

    func canEvaluateBiometrics() throws {
        didCheckAvailability = true
        if let availabilityError {
            throw availabilityError
        }
    }

    func evaluateBiometrics(localizedReason: String) async throws {
        self.localizedReason = localizedReason
    }
}
