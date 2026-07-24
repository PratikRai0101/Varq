import Foundation
import Testing
@testable import Varq

struct ReadingSessionServiceTests {
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
