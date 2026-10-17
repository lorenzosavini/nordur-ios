import Foundation

// Live road information from Vegagerðin's umferdin.is, served by nordur-api
// (/api/roads, refreshed every 5 minutes): every serviced road section with its
// surface condition, hazards and roadworks with positions, weight limits, tolls,
// winter-service hours and road numbers, plus the live road notifications.

struct RoadInfo: Decodable {
    struct Point: Decodable, Hashable {
        let lat: Double
        let lon: Double
        var coordinate: Coordinate { Coordinate(lat: lat, lon: lon) }
    }

    struct Condition: Decodable, Hashable {
        let code: String?
        let category: String?
        let text: String?
        let date: String?
        var updated: Date? { DateParse.iso(date) }
    }

    struct Hazard: Decodable, Identifiable, Hashable {
        let id: String
        let code: String?
        let title: String?
        let text: String?
        let from: String?
        let to: String?
        let at: Point?
        var start: Date? { DateParse.iso(from) }
        var end: Date? { DateParse.iso(to) }
    }

    struct Note: Decodable, Hashable {
        let code: String?
        let text: String?
        let date: String?
    }

    struct Hours: Decodable, Hashable {
        let day: Int        // 0 = Sunday
        let type: Int?
        let from: String?
        let to: String?
    }

    struct Weight: Decodable, Hashable { let limit: String?; let text: String? }
    struct Toll: Decodable, Hashable { let type: String?; let text: String?; let at: Point? }
    struct RoadRef: Decodable, Hashable { let nr: String; let name: String? }

    struct Section: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let roads: [RoadRef]
        let service: Int?
        let winterService: String?
        let hours: [Hours]
        let condition: Condition?
        let previous: Condition?
        let hazards: [Hazard]
        let notes: [Note]
        let weight: Weight?
        let toll: Toll?
        let bbox: [Double]?       // west, south, east, north
        let center: Point?
        let updated: String?
    }

    struct News: Decodable, Identifiable, Hashable {
        let id: String
        let region: String?
        let key: String?
        let place: String?
        let text: String
        let date: String?
        var published: Date? { DateParse.iso(date) }
    }

    struct Code: Decodable, Hashable {
        let code: String
        let type: String?
        let title: String?
        let text: String?
    }

    let generated: String?
    let lastUpdate: String?
    let sections: [Section]
    let news: [News]
    let codes: [Code]
    let stale: Bool?

    /// Official explanation of a condition, weather or hazard code (English, from Vegagerðin).
    func explanation(_ code: String?) -> String? {
        guard let code else { return nil }
        return codes.first { $0.code == code }?.text
    }
}

// MARK: - Meaning of the codes

enum RoadCode {
    /// Surface condition categories (umferdin.is RoadConditionInfo, type ROAD).
    static func label(_ category: String?) -> String? {
        switch category {
        case "A": return String(localized: "Percorribile")
        case "B": return String(localized: "Tratti ghiacciati")
        case "C": return String(localized: "Strada scivolosa")
        case "D": return String(localized: "Estremamente scivolosa")
        case "E": return String(localized: "Neve bagnata")
        case "F": return String(localized: "Neve sulla carreggiata")
        case "G": return String(localized: "Guida difficile")
        case "H": return String(localized: "Condizioni stradali difficili")
        case "J", "K": return String(localized: "Impraticabile / chiusa")
        case "L": return String(localized: "Chiusa al traffico")
        case "S": return String(localized: "Solo veicoli 4x4 da montagna")
        case "-": return String(localized: "Nessun servizio invernale")
        case "0": return String(localized: "Stato sconosciuto")
        default: return nil
        }
    }

    /// nil when there is no service or the state is unknown.
    static func risk(_ category: String?) -> Risk? {
        switch category {
        case "A": return .ok
        case "B", "E": return .caution
        case "C", "F", "G", "S": return .warning
        case "D", "H", "J", "K", "L": return .danger
        default: return nil
        }
    }

    static func isClosed(_ category: String?) -> Bool { ["J", "K", "L"].contains(category ?? "") }

    /// Weather notes on a section (type WEATHER_CONDITION).
    static func weather(_ code: String?) -> String? {
        switch code {
        case "1": return String(localized: "Tempesta")
        case "2": return String(localized: "Nevicata")
        case "3": return String(localized: "Neve soffiata dal vento")
        case "4": return String(localized: "Bufera di neve")
        case "5": return String(localized: "Nebbia")
        case "6": return String(localized: "Sgombero neve in corso")
        case "7": return String(localized: "Sabbia sollevata dal vento")
        case "16": return String(localized: "Rovesci di neve")
        case "18": return String(localized: "Condizioni sconosciute fuori orario di servizio")
        default: return nil
        }
    }

    /// Hazards and roadworks (type ICON), by code.
    static func hazard(_ code: String?) -> (label: String, symbol: String) {
        switch code {
        case "VEGAVINNA", "8": return (String(localized: "Lavori stradali"), "cone.fill")
        case "HOLUR_I_VEGI", "19": return (String(localized: "Buche sulla strada"), "exclamationmark.triangle.fill")
        case "GRJOTHRUN": return (String(localized: "Caduta massi"), "mountain.2.fill")
        case "10": return (String(localized: "Ghiaia che vola"), "aqi.medium")
        case "WEIGHT_RESTRICTION": return (String(localized: "Limiti di peso"), "scalemass.fill")
        case "OSLETTUR_VEGUR": return (String(localized: "Strada dissestata"), "road.lanes")
        case "ALLUR_AKSTUR_BANN", "17": return (String(localized: "Divieto di transito"), "nosign")
        case "DYR_A_VEGI": return (String(localized: "Animali sulla strada"), "hare.fill")
        case "SVIPTIVINDUR": return (String(localized: "Raffiche improvvise"), "wind")
        case "BIKBLAEDINGAR": return (String(localized: "Bitume affiorante: scivoloso"), "drop.fill")
        default: return (String(localized: "Avviso"), "exclamationmark.circle.fill")
        }
    }

    /// What kind of road a road number is (Icelandic road classification).
    static func kind(_ nr: String) -> String {
        if nr == "1" { return String(localized: "Hringvegur (Ring Road): strada nazionale principale") }
        if nr.uppercased().hasPrefix("F") { return String(localized: "Strada F di montagna: solo 4x4, guadi senza ponti, aperta in genere da giugno a settembre") }
        let digits = nr.filter(\.isNumber)
        switch digits.count {
        case 1, 2: return String(localized: "Strada principale (stofnvegur)")
        case 3: return String(localized: "Strada regionale o di collegamento (tengivegur)")
        default: return String(localized: "Strada locale")
        }
    }
}

// MARK: - Geometry

extension RoadInfo.Section {
    var label: String { RoadCode.label(condition?.category) ?? condition?.text ?? String(localized: "Stato sconosciuto") }
    var risk: Risk? { RoadCode.risk(condition?.category) }
    var isClosed: Bool { RoadCode.isClosed(condition?.category) }
    var numbers: String { roads.map(\.nr).joined(separator: " / ") }
    var worsened: Bool {
        guard let now = risk, let before = RoadCode.risk(previous?.category) else { return false }
        return now > before
    }

    /// Distance from a point to the section (0 inside its bounding box), km.
    func distanceKm(to c: Coordinate) -> Double? {
        if let b = bbox, b.count == 4 {
            let lat = min(max(c.lat, b[1]), b[3]), lon = min(max(c.lon, b[0]), b[2])
            return Geo.distanceKm(c, Coordinate(lat: lat, lon: lon))
        }
        return center.map { Geo.distanceKm(c, $0.coordinate) }
    }

    /// Winter-service hours for a weekday (0 = Sunday), "06:30–22:00", "24 h" or nil.
    func serviceHours(on day: Int) -> String? {
        guard let h = hours.first(where: { $0.day == day }), let from = h.from, let to = h.to else { return nil }
        return from == to ? String(localized: "24 h") : "\(from)–\(to)"
    }
}

enum RoadInfoService {
    static let endpoint = URL(string: "https://nordur-api.vercel.app/api/roads")!

    static func load() async throws -> Fetched<RoadInfo> {
        try await HTTP.json(RoadInfo.self, from: endpoint, cacheKey: "road_info")
    }
}
