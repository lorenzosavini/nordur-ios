import Foundation

extension TimeZone {
    static let iceland = TimeZone(identifier: "Atlantic/Reykjavik") ?? TimeZone(secondsFromGMT: 0)!
}

enum DateParse {
    private static let internet: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let utcNoZone: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    private static let icelandic: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .iceland
        formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
        return formatter
    }()

    /// Parses the ISO-8601 variants used by the sources: with or without
    /// fractional seconds, `Z`, `-00:00` or no zone at all (assumed UTC).
    static func iso(_ raw: String?) -> Date? {
        guard var text = raw?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if let fraction = text.range(of: #"\.\d+"#, options: .regularExpression) {
            text.removeSubrange(fraction)
        }
        if text.hasSuffix("-00:00") {
            text = String(text.dropLast(6)) + "Z"
        }
        text = text.replacingOccurrences(of: " ", with: "T")
        if let date = internet.date(from: text) { return date }
        return utcNoZone.date(from: text)
    }

    /// Road stations report "16.10.2026 11:10:00" in Icelandic time.
    static func roadStation(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return icelandic.date(from: raw)
    }
}
