import Foundation
import Observation

@MainActor
@Observable
final class ReadingSessionService {
    private(set) var startedAt: Date?
    private(set) var elapsedSeconds: TimeInterval = 0
    private var accumulatedSeconds: TimeInterval = 0

    func begin(at date: Date = .now) {
        guard startedAt == nil else { return }
        startedAt = date
    }

    func end(at date: Date = .now) -> TimeInterval {
        refresh(at: date)
        startedAt = nil
        accumulatedSeconds = elapsedSeconds
        return elapsedSeconds
    }

    func refresh(at date: Date = .now) {
        guard let startedAt else { return }
        elapsedSeconds = accumulatedSeconds + max(date.timeIntervalSince(startedAt), 0)
    }

    func formattedElapsed(at date: Date = .now) -> String {
        refresh(at: date)
        let minutes = Int(elapsedSeconds / 60)
        return minutes == 1 ? "1 min" : "\(minutes) min"
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
