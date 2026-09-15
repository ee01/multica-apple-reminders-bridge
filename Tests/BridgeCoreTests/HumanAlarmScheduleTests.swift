import XCTest
@testable import BridgeCore

final class HumanAlarmScheduleTests: XCTestCase {
    func testNextMorningUsesTodayIfStillBeforeNine() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(2026, 9, 14, 8, 30, calendar: calendar)
        let alarm = HumanAlarmSchedule.nextMorning(hour: 9, minute: 0, after: now, calendar: calendar)
        XCTAssertEqual(alarm, date(2026, 9, 14, 9, 0, calendar: calendar))
    }

    func testNextMorningUsesTomorrowIfAlreadyPastNine() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(2026, 9, 14, 10, 0, calendar: calendar)
        let alarm = HumanAlarmSchedule.nextMorning9.alarmDate(from: now, calendar: calendar)
        XCTAssertEqual(alarm, date(2026, 9, 15, 9, 0, calendar: calendar))
    }

    func testDelayPresetsStayRelative() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(HumanAlarmSchedule.after15Minutes.alarmDate(from: now), now.addingTimeInterval(900))
        XCTAssertEqual(HumanAlarmSchedule.after3Hours.alarmDate(from: now), now.addingTimeInterval(3 * 3600))
    }

    func testOldDelaySecondsMapToNearestPreset() {
        XCTAssertEqual(HumanAlarmSchedule.inferred(fromDelaySeconds: 60), .after1Minute)
        XCTAssertEqual(HumanAlarmSchedule.inferred(fromDelaySeconds: 900), .after15Minutes)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)!
    }
}
