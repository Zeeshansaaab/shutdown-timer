import Foundation

struct DailySchedule {
    static func nextFireDate(hour: Int, minute: Int, after date: Date, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let candidate = calendar.date(from: components) else {
            return date
        }

        if candidate > date {
            return candidate
        }

        return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
    }
}
