import Foundation

nonisolated struct ReadingGoalProgress: Equatable, Sendable {
    let dailyGoalMinutes: Int
    let todayMinutes: Int
    let currentStreak: Int

    var isGoalMet: Bool { todayMinutes >= dailyGoalMinutes }
}

/// Stores optional, local-only daily reading goals and streak history.
struct ReadingGoalService {
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let goalKey = "readingGoalMinutes"
    private let historyKey = "readingGoalDailySeconds"

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    func progress(on date: Date = .now) -> ReadingGoalProgress {
        let goal = max(defaults.integer(forKey: goalKey), 0)
        let history = defaults.dictionary(forKey: historyKey) as? [String: Double] ?? [:]
        let today = Int((history[dayKey(for: date)] ?? 0) / 60)
        return ReadingGoalProgress(dailyGoalMinutes: goal, todayMinutes: today, currentStreak: streak(in: history, ending: date, goal: goal))
    }

    func setDailyGoal(minutes: Int) { defaults.set(max(minutes, 0), forKey: goalKey) }

    func record(seconds: TimeInterval, on date: Date = .now) {
        guard seconds > 0 else { return }
        var history = defaults.dictionary(forKey: historyKey) as? [String: Double] ?? [:]
        let key = dayKey(for: date)
        history[key, default: 0] += seconds
        defaults.set(history, forKey: historyKey)
    }

    private func streak(in history: [String: Double], ending date: Date, goal: Int) -> Int {
        guard goal > 0 else { return 0 }
        var cursor = calendar.startOfDay(for: date)
        var streak = 0
        while Int((history[dayKey(for: cursor)] ?? 0) / 60) >= goal {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    private func dayKey(for date: Date) -> String { ISO8601DateFormatter().string(from: calendar.startOfDay(for: date)).prefix(10).description }
}
