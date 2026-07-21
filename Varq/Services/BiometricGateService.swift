import Foundation
import LocalAuthentication

@MainActor
protocol BiometricAuthenticationContext: AnyObject {
    func canEvaluateBiometrics() throws
    func evaluateBiometrics(localizedReason: String) async throws
}

@MainActor
final class LocalAuthenticationContext: BiometricAuthenticationContext {
    private let context: LAContext

    init(context: LAContext = LAContext()) {
        self.context = context
    }

    func canEvaluateBiometrics() throws {
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? BiometricGateError.unavailable
        }
    }

    func evaluateBiometrics(localizedReason: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: localizedReason) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? BiometricGateError.authenticationFailed)
                }
            }
        }
    }
}

@MainActor
final class BiometricGateService {
    private let authenticationContext: any BiometricAuthenticationContext

    init() {
        authenticationContext = LocalAuthenticationContext()
    }

    init(authenticationContext: any BiometricAuthenticationContext) {
        self.authenticationContext = authenticationContext
    }

    func authenticate(localizedReason: String) async throws {
        try authenticationContext.canEvaluateBiometrics()
        try await authenticationContext.evaluateBiometrics(localizedReason: localizedReason)
    }
}

enum BiometricGateError: Error, Equatable {
    case unavailable
    case authenticationFailed
}
