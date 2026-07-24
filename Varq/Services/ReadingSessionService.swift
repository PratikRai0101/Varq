import Foundation
import Observation

@MainActor
@Observable
final class ReadingSessionService {
    private(set) var startedAt: Date?
    private var accumulatedSeconds: TimeInterval = 0

    /// The current session duration. This is derived rather than stored so rendering
    /// the timer cannot trigger an observation update while SwiftUI is rendering.
    var elapsedSeconds: TimeInterval {
        elapsed(at: .now)
    }

    func begin(at date: Date = .now) {
        guard startedAt == nil else { return }
        startedAt = date
    }

    func end(at date: Date = .now) -> TimeInterval {
        let completedSeconds = elapsed(at: date)
        startedAt = nil
        accumulatedSeconds = completedSeconds
        return completedSeconds
    }

    func formattedElapsed(at date: Date = .now) -> String {
        let minutes = Int(elapsed(at: date) / 60)
        return minutes == 1 ? "1 min" : "\(minutes) min"
    }

    private func elapsed(at date: Date) -> TimeInterval {
        guard let startedAt else { return accumulatedSeconds }
        return accumulatedSeconds + max(date.timeIntervalSince(startedAt), 0)
    }
}

nonisolated struct ReadingEstimateService {
    func remainingTime(totalReadingSeconds: TimeInterval, progressFraction: Double) -> TimeInterval? {
        guard progressFraction > 0.02, totalReadingSeconds > 0, progressFraction < 1 else { return nil }
        return max((totalReadingSeconds / progressFraction) * (1 - progressFraction), 0)
    }

    func formattedRemainingTime(totalReadingSeconds: TimeInterval, progressFraction: Double) -> String? {
        guard let seconds = remainingTime(totalReadingSeconds: totalReadingSeconds, progressFraction: progressFraction) else { return nil }
        let minutes = max(Int((seconds / 60).rounded()), 1)
        return minutes < 60 ? "~\(minutes) min left" : "~\(minutes / 60) hr left"
    }
}
