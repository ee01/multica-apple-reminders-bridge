import Foundation

public enum FlexibleDateParser {
    private static let internetWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let internet: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let dayOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return internetWithFractional.date(from: value) ?? internet.date(from: value) ?? dayOnly.date(from: value)
    }
}
