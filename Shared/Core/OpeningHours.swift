import Foundation

/// The common forms of OpenStreetMap `opening_hours` ("Mo-Fr 10:00-19:00; Sa 11:00-18:00",
/// "24/7", "Mo-Su 08:00-24:00", "Su off"…). A later rule wins for the days it names,
/// as in OSM. Anything it can't read gives nil, and the raw text is shown instead.
struct OpeningHours {
    /// Minutes from midnight; an end past 1440 runs into the next day.
    typealias Span = (start: Int, end: Int)

    private var week: [[Span]] = Array(repeating: [], count: 7) // 0 = Monday

    private static let dayNames = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    init?(_ text: String) {
        // "Mo-Fr 09:00-21:00, Sa-Su 11:00-21:00": a comma between a time and a day starts a new rule.
        let text = text.replacingOccurrences(of: #"(?<=\d),\s*(?=(Mo|Tu|We|Th|Fr|Sa|Su)\b)"#, with: ";", options: .regularExpression)
        let rules = text.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !rules.isEmpty else { return nil }
        var parsedAny = false
        for rule in rules {
            if rule == "24/7" {
                week = Array(repeating: [(0, 1440)], count: 7)
                parsedAny = true
                continue
            }
            var parts = rule.split(separator: " ", maxSplits: 1).map(String.init)
            var days = Set(0..<7)
            if let first = parts.first, let named = Self.days(first) {
                // Public and school holidays only: nothing to apply on a normal day.
                if named.isEmpty { continue }
                days = named
                parts.removeFirst()
            } else if let first = parts.first, !(first.first?.isNumber ?? false) && first != "off" && first != "closed" {
                // Holidays and dates ("PH off", "May 01 12:00-17:00", "easter +49 days off"): not a normal week.
                continue
            }
            guard let times = parts.first.map({ $0.trimmingCharacters(in: .whitespaces) }), let spans = Self.spans(times) else { return nil }
            for day in days { week[day] = spans }
            parsedAny = true
        }
        guard parsedAny else { return nil }
    }

    /// "Mo-Fr", "Sa,Su", "Mo-Fr,Su", "Mo-Su,PH" → weekdays; PH/SH alone → empty set.
    private static func days(_ token: String) -> Set<Int>? {
        var result = Set<Int>()
        for piece in token.split(separator: ",") {
            let p = String(piece)
            if p == "PH" || p == "SH" { continue }
            let ends = p.split(separator: "-").map(String.init)
            guard let a = dayNames.firstIndex(of: ends[0]) else { return nil }
            if ends.count == 2 {
                guard let b = dayNames.firstIndex(of: ends[1]) else { return nil }
                var d = a
                while true { result.insert(d); if d == b { break }; d = (d + 1) % 7 }
            } else if ends.count == 1 {
                result.insert(a)
            } else { return nil }
        }
        return result
    }

    private static func spans(_ text: String) -> [Span]? {
        if text == "off" || text == "closed" { return [] }
        if text == "24/7" { return [(0, 1440)] }
        var result: [Span] = []
        for piece in text.split(separator: ",") {
            let ends = piece.trimmingCharacters(in: .whitespaces).split(separator: "-").map(String.init)
            guard ends.count == 2, let a = minutes(ends[0]), var b = minutes(ends[1]) else { return nil }
            if b <= a { b += 1440 }
            result.append((a, b))
        }
        return result.isEmpty ? nil : result
    }

    private static func minutes(_ hhmm: String) -> Int? {
        let p = hhmm.split(separator: ":")
        guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]), (0...24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    private static func weekday(_ date: Date, _ calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    func isOpen(at date: Date, calendar: Calendar = .iceland) -> Bool {
        let day = Self.weekday(date, calendar)
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if week[day].contains(where: { $0.start <= m && m < $0.end }) { return true }
        // Late opening that started the day before ("18:00-02:00").
        return week[(day + 6) % 7].contains { $0.start <= m + 1440 && m + 1440 < $0.end }
    }

    /// When it next opens (if closed) or closes (if open), within a week.
    func nextChange(after date: Date, calendar: Calendar = .iceland) -> Date? {
        let open = isOpen(at: date, calendar: calendar)
        let today = calendar.startOfDay(for: date)
        var boundaries: [Date] = []
        for offset in -1...7 {
            guard let start = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for span in week[Self.weekday(start, calendar)] {
                boundaries.append(start.addingTimeInterval(Double(span.start) * 60))
                boundaries.append(start.addingTimeInterval(Double(span.end) * 60))
            }
        }
        return boundaries.filter { $0 > date }.sorted().first { isOpen(at: $0, calendar: calendar) != open }
    }
}
