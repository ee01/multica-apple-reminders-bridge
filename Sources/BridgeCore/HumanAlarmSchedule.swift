import Foundation

public enum HumanAlarmSchedule: String, Codable, CaseIterable, Hashable, Sendable {
    case immediately = "immediately"
    case after1Minute = "after_1_minute"
    case after5Minutes = "after_5_minutes"
    case after15Minutes = "after_15_minutes"
    case after1Hour = "after_1_hour"
    case after3Hours = "after_3_hours"
    case nextMorning9 = "next_morning_9"

    public var displayName: String {
        switch self {
        case .immediately: return "Immediately"
        case .after1Minute: return "In 1 minute"
        case .after5Minutes: return "In 5 minutes"
        case .after15Minutes: return "In 15 minutes"
        case .after1Hour: return "In 1 hour"
        case .after3Hours: return "In 3 hours"
        case .nextMorning9: return "Next morning at 9:00"
        }
    }

    public var helpText: String {
        switch self {
        case .nextMorning9:
            return "Uses the next 9:00 AM. If it is already past 9:00, this is tomorrow morning."
        default:
            return "Applies to Review and Failed reminders. Action Required (blocked) always notifies immediately."
        }
    }

    public var legacyDelaySeconds: TimeInterval {
        switch self {
        case .immediately: return 0
        case .after1Minute: return 60
        case .after5Minutes: return 5 * 60
        case .after15Minutes: return 15 * 60
        case .after1Hour: return 60 * 60
        case .after3Hours: return 3 * 60 * 60
        case .nextMorning9: return 60
        }
    }

    public func alarmDate(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .immediately: return now
        case .after1Minute: return now.addingTimeInterval(60)
        case .after5Minutes: return now.addingTimeInterval(5 * 60)
        case .after15Minutes: return now.addingTimeInterval(15 * 60)
        case .after1Hour: return now.addingTimeInterval(60 * 60)
        case .after3Hours: return now.addingTimeInterval(3 * 60 * 60)
        case .nextMorning9: return Self.nextMorning(hour: 9, minute: 0, after: now, calendar: calendar)
        }
    }

    public static func inferred(fromDelaySeconds delay: TimeInterval) -> HumanAlarmSchedule {
        let presets: [(HumanAlarmSchedule, TimeInterval)] = [
            (.immediately, 0),
            (.after1Minute, 60),
            (.after5Minutes, 5 * 60),
            (.after15Minutes, 15 * 60),
            (.after1Hour, 60 * 60),
            (.after3Hours, 3 * 60 * 60)
        ]
        return presets.min(by: { abs($0.1 - delay) < abs($1.1 - delay) })?.0 ?? .after1Minute
    }

    public static func nextMorning(hour: Int, minute: Int, after now: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard let today = calendar.date(from: components) else { return now.addingTimeInterval(12 * 60 * 60) }
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(24 * 60 * 60)
    }
}
