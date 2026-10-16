import Foundation
import SwiftUI

// Veðurstofa Íslands — Icelandic Met Office (vedur.is): official colour-coded
// weather warnings (CAP feed) and the national seismic network.

enum WarningColor: Int, Comparable {
    case unknown = 0, yellow, orange, red

    init(_ raw: String?) {
        switch raw?.lowercased() {
        case "yellow": self = .yellow
        case "orange": self = .orange
        case "red": self = .red
        default: self = .unknown
        }
    }

    static func < (lhs: WarningColor, rhs: WarningColor) -> Bool { lhs.rawValue < rhs.rawValue }

    var color: Color {
        switch self {
        case .unknown: return Theme.dim
        case .yellow: return Color(hex: 0xF5D04A)
        case .orange: return Color(hex: 0xF28A30)
        case .red: return Color(hex: 0xE5413E)
        }
    }

    var label: String {
        switch self {
        case .unknown: return "Avviso"
        case .yellow: return "Allerta gialla"
        case .orange: return "Allerta arancione"
        case .red: return "Allerta rossa"
        }
    }

    var risk: Risk {
        switch self {
        case .unknown, .yellow: return .caution
        case .orange: return .warning
        case .red: return .danger
        }
    }
}

struct WeatherWarning: Decodable, Identifiable {
    let identifier: String
    let headline: String
    let event: String
    let details: String
    let headlineIcelandic: String?
    let severity: String?
    let certainty: String?
    let messageType: String?
    let onset: Date?
    let expires: Date?
    let region: String
    let color: WarningColor
    let alertTypes: [String]
    let polygons: [[Coordinate]]

    var id: String { identifier }

    private enum CodingKeys: String, CodingKey {
        case identifier, headline_en, headline_is, event_en, description_en, severity, certainty
        case msgtype, onset, expires, geocode_en, parameter, eventcode, polygon
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try c.decode(String.self, forKey: .identifier)
        headline = (try? c.decodeIfPresent(String.self, forKey: .headline_en)) ?? "Avviso meteo"
        headlineIcelandic = try? c.decodeIfPresent(String.self, forKey: .headline_is)
        event = (try? c.decodeIfPresent(String.self, forKey: .event_en)) ?? ""
        details = (try? c.decodeIfPresent(String.self, forKey: .description_en)) ?? ""
        severity = try? c.decodeIfPresent(String.self, forKey: .severity)
        certainty = try? c.decodeIfPresent(String.self, forKey: .certainty)
        messageType = try? c.decodeIfPresent(String.self, forKey: .msgtype)
        onset = DateParse.iso((try? c.decodeIfPresent(String.self, forKey: .onset)) ?? nil)
        expires = DateParse.iso((try? c.decodeIfPresent(String.self, forKey: .expires)) ?? nil)
        let geocode = (try? c.decodeIfPresent([String: [String]].self, forKey: .geocode_en)) ?? nil
        region = geocode?.values.first?.first ?? "Islanda"
        let parameter = (try? c.decodeIfPresent([String: [String]].self, forKey: .parameter)) ?? nil
        color = WarningColor(parameter?["Color"]?.first)
        let eventCode = (try? c.decodeIfPresent([String: [String]].self, forKey: .eventcode)) ?? nil
        alertTypes = eventCode?["alertType"] ?? []
        let rawPolygons = (try? c.decodeIfPresent([String].self, forKey: .polygon)) ?? nil
        polygons = (rawPolygons ?? []).map(Geo.parseCAPPolygon).filter { $0.count >= 3 }
    }

    var isCancelled: Bool { messageType?.lowercased() == "cancel" }

    func isRelevant(at date: Date = Date()) -> Bool {
        guard !isCancelled else { return false }
        if let expires, expires < date { return false }
        return true
    }

    func isActive(at date: Date = Date()) -> Bool {
        guard isRelevant(at: date) else { return false }
        if let onset, onset > date { return false }
        return true
    }

    func covers(_ point: Coordinate) -> Bool {
        polygons.contains { Geo.contains($0, point) }
    }

    /// Does the warning's validity overlap the [start, end) interval?
    func overlaps(_ start: Date, _ end: Date) -> Bool {
        guard !isCancelled else { return false }
        let from = onset ?? .distantPast
        let to = expires ?? .distantFuture
        return from < end && to > start
    }

    var symbol: String {
        let type = alertTypes.first?.lowercased() ?? event.lowercased()
        if type.contains("wind") { return "wind" }
        if type.contains("snow") || type.contains("blizzard") { return "snowflake" }
        if type.contains("rain") { return "cloud.heavyrain.fill" }
        if type.contains("thunder") || type.contains("lightning") { return "cloud.bolt.fill" }
        if type.contains("ice") || type.contains("frost") { return "thermometer.snowflake" }
        if type.contains("sea") || type.contains("wave") || type.contains("coastal") { return "water.waves" }
        if type.contains("avalanche") { return "mountain.2.fill" }
        return "exclamationmark.triangle.fill"
    }

    /// Italian name of the hazard (the CAP feed's English event is "Weather Warning: Wind" and similar).
    var hazardItalian: String {
        let type = (alertTypes.first ?? event).lowercased()
        let table: [(String, String)] = [("blizzard", "Bufera di neve"), ("snow", "Neve"), ("wind", "Vento"), ("rain", "Pioggia"),
                                         ("thunder", "Temporali"), ("lightning", "Fulmini"), ("ice", "Ghiaccio"), ("frost", "Gelo"),
                                         ("coastal", "Mareggiata"), ("wave", "Mareggiata"), ("sea", "Mare"), ("avalanche", "Valanghe")]
        return table.first { type.contains($0.0) }?.1 ?? "Meteo"
    }
}

struct Quake: Identifiable {
    let id: String
    let date: Date
    let magnitude: Double
    let depth: Double?
    let region: String
    let kind: String
    let reviewed: Bool
    let coordinate: Coordinate

    var risk: Risk {
        if magnitude >= 4 { return .danger }
        if magnitude >= 3 { return .warning }
        if magnitude >= 2 { return .caution }
        return .ok
    }
}

private struct QuakeCollection: Decodable {
    let features: [Feature]

    struct Feature: Decodable {
        let geometry: Geometry
        let properties: Properties
    }

    struct Geometry: Decodable {
        let coordinates: [Double]
    }

    struct Properties: Decodable {
        let event_id: String?
        let time: String?
        let magnitude: Double?
        let depth: Double?
        let region: String?
        let type: String?
        let evaluation_mode: String?
    }
}

enum IMO {
    static func warnings() async throws -> Fetched<[WeatherWarning]> {
        guard let url = URL(string: "https://api.vedur.is/cap/v1/capbroker/active/detailed/all/") else { throw HTTPError.invalidURL }
        let fetched = try await HTTP.json([WeatherWarning].self, from: url, cacheKey: "imo_warnings")
        return fetched.map { list in
            list.filter { $0.isRelevant() }.sorted {
                if $0.color != $1.color { return $0.color > $1.color }
                return ($0.onset ?? .distantPast) < ($1.onset ?? .distantPast)
            }
        }
    }

    static func quakes(hours: Int = 48) async throws -> Fetched<[Quake]> {
        let end = Date()
        let start = end.addingTimeInterval(-TimeInterval(hours) * 3600)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let url = try HTTP.url("https://api.vedur.is/quakes/events", [
            "start_time": iso.string(from: start),
            "end_time": iso.string(from: end),
        ])
        let fetched = try await HTTP.json(QuakeCollection.self, from: url, cacheKey: "imo_quakes")
        return fetched.map { collection in
            collection.features.compactMap { feature -> Quake? in
                let p = feature.properties
                guard feature.geometry.coordinates.count >= 2,
                      let date = DateParse.iso(p.time),
                      let magnitude = p.magnitude else { return nil }
                return Quake(
                    id: p.event_id ?? UUID().uuidString,
                    date: date,
                    magnitude: magnitude,
                    depth: p.depth,
                    region: p.region ?? "Islanda",
                    kind: p.type ?? "earthquake",
                    reviewed: p.evaluation_mode == "manual",
                    coordinate: Coordinate(lat: feature.geometry.coordinates[1], lon: feature.geometry.coordinates[0])
                )
            }
            .sorted { $0.date > $1.date }
        }
    }
}
