import Foundation
import Testing
@testable import Varq

private final class ObservationChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

struct ReadingSessionServiceTests {
    @MainActor
    @Test func formattingTheSessionTimeDoesNotMutateObservedSessionState() {
        let service = ReadingSessionService()
        service.begin(at: Date(timeIntervalSince1970: 100))
        let changeCounter = ObservationChangeCounter()

        withObservationTracking {
            _ = service.elapsedSeconds
        } onChange: {
            changeCounter.increment()
        }

        _ = service.formattedElapsed(at: Date(timeIntervalSince1970: 160))

        #expect(changeCounter.value == 0)
    }

    @Test func estimatesRemainingTimeFromRecordedReadingRate() {
        let estimate = ReadingEstimateService().formattedRemainingTime(totalReadingSeconds: 600, progressFraction: 0.5)
        #expect(estimate == "~10 min left")
    }

    @Test func tracksAConsecutiveDailyGoalStreak() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let calendar = Calendar(identifier: .gregorian)
        let service = ReadingGoalService(defaults: defaults, calendar: calendar)
        let today = Date(timeIntervalSince1970: 1_728_000_000)
        service.setDailyGoal(minutes: 10)
        service.record(seconds: 600, on: today)
        service.record(seconds: 600, on: calendar.date(byAdding: .day, value: -1, to: today)!)

        #expect(service.progress(on: today).currentStreak == 2)
    }
}
