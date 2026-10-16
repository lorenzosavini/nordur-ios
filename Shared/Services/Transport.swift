import Foundation

// Keflavík airport live flight board (data embedded in kefairport.com) and the
// Herjólfur ferry notices (the Vestmannaeyjar ferry is often cancelled or
// diverted to Þorlákshöfn in bad weather).

struct Flight: Identifiable, Hashable, Decodable {
    let flightId: Int
    let flightNumber: String
    let airline: String?
    let destination: String?
    let airportCode: String?
    let arrival: Bool
    let date: String?
    let time: String?
    let updatedTime: String?
    let status: String?
    let gate: String?
    let belt: String?

    var id: Int { flightId }
    var scheduled: Date? { DateParse.iso(date) }

    var statusInfo: (text: String, risk: Risk) {
        let updated = updatedTime.map { " \($0)" } ?? ""
        switch status?.uppercased() {
        case "ATD", "DEP": return (String(localized: "Partito\(updated)"), .ok)
        case "LBB": return (String(localized: "Atterrato · bagagli al nastro \(belt ?? "")"), .ok)
        case "LND", "ARR", "ATA": return (String(localized: "Atterrato\(updated)"), .ok)
        case "EST": return (String(localized: "Previsto\(updated)"), isLate ? .caution : .ok)
        case "BDC", "BRD": return (String(localized: "Imbarco in corso"), .ok)
        case "GTO": return (String(localized: "Gate aperto"), .ok)
        case "OFF", "GCL": return (String(localized: "Gate chiuso"), .ok)
        case "DEL", "DLY": return (String(localized: "In ritardo\(updated)"), .warning)
        case "CNL", "CAN", "CXX": return (String(localized: "Cancellato"), .danger)
        case "DIV": return (String(localized: "Dirottato"), .danger)
        case "NOSTATUS", nil: return (String(localized: "In orario"), .ok)
        default: return (status ?? "—", .ok)
        }
    }

    /// Updated time later than the scheduled one by 30+ minutes.
    var isLate: Bool {
        guard let time, let updatedTime, let a = Self.minutes(time), let b = Self.minutes(updatedTime) else { return false }
        var delta = b - a
        if delta < -12 * 60 { delta += 24 * 60 }
        return delta >= 30
    }

    private static func minutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }
}

struct FerryNotice {
    let text: String
    let url: URL
}

enum TransportService {
    static let kefFlightsPage = "https://www.kefairport.com/flights"
    static let herjolfurPage = "https://www.herjolfur.is/en/"

    static func kefFlights() async throws -> Fetched<[Flight]> {
        guard let url = URL(string: kefFlightsPage) else { throw HTTPError.invalidURL }
        let fetched = try await HTTP.get(url, cacheKey: "kef_flights")
        return try fetched.map(parseFlights)
    }

    static func parseFlights(_ data: Data) throws -> [Flight] {
        guard let html = String(data: data, encoding: .utf8),
              let start = html.range(of: "<script id=\"__NEXT_DATA__\" type=\"application/json\">"),
              let end = html.range(of: "</script>", range: start.upperBound..<html.endIndex) else {
            throw HTTPError.status(0)
        }
        let json = Data(html[start.upperBound..<end.lowerBound].utf8)
        let root = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        let pageProps = (root?["props"] as? [String: Any])?["pageProps"] as? [String: Any]
        let flightsData: Data
        if let text = pageProps?["flightArrayData"] as? String {
            flightsData = Data(text.utf8)
        } else if let array = pageProps?["flightArrayData"] as? [Any] {
            flightsData = try JSONSerialization.data(withJSONObject: array)
        } else {
            return []
        }
        let flights = try JSONDecoder().decode([LossyFlight].self, from: flightsData).compactMap(\.flight)
        return flights.sorted { ($0.scheduled ?? .distantPast) < ($1.scheduled ?? .distantPast) }
    }

    static func herjolfur() async throws -> Fetched<FerryNotice?> {
        guard let url = URL(string: herjolfurPage) else { throw HTTPError.invalidURL }
        let fetched = try await HTTP.get(url, cacheKey: "herjolfur")
        return fetched.map { data in
            guard let html = String(data: data, encoding: .utf8), let text = extractNotice(html) else { return nil }
            return FerryNotice(text: text, url: url)
        }
    }

    static func extractNotice(_ html: String) -> String? {
        var text = html.replacingOccurrences(of: "<(script|style)[^>]*>[\\s\\S]*?</(script|style)>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
        let lines = text.components(separatedBy: "\n")
            .map { HTMLText.plain($0) }
            .filter { !$0.isEmpty }
        guard let index = lines.firstIndex(where: { $0.localizedCaseInsensitiveContains("Attention passengers") }) else { return nil }
        let body = lines[(index + 1)...].prefix(6)
        let joined = body.joined(separator: "\n")
        return joined.isEmpty ? nil : String(joined.prefix(700))
    }
}

/// Skips malformed rows instead of failing the whole board.
private struct LossyFlight: Decodable {
    let flight: Flight?
    init(from decoder: Decoder) throws {
        flight = try? Flight(from: decoder)
    }
}
