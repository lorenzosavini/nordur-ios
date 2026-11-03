import Foundation
import MapKit
import Observation

// Tolls, toll tunnels and paid parking: a small catalog curated by hand from
// official sources only (backend/lib/tolls-data.js), edited in the admin panel
// and served at /api/tolls. Kept on the phone for use without coverage.
// Prices are indicative: the app always says when they were checked and links
// the official page.

struct TollEntry: Decodable, Identifiable, Hashable {
    enum Kind: String {
        case tollTunnel = "toll_tunnel"
        case tollRoad = "toll_road"
        case paidParking = "paid_parking"
        case info
    }

    struct Price: Decodable, Hashable {
        let cls: String
        let isk: Double
        let unit: String

        enum CodingKeys: String, CodingKey { case cls = "class", isk, unit }
    }

    struct Texts: Decodable, Hashable {
        var summary: String?
        var payment: String?
        var window: String?
        var penalty: String?
        var rental: String?
        var alternative: String?
        var note: String?
    }

    struct Source: Decodable, Hashable {
        let name: String
        let url: String
    }

    /// What travellers said they paid: one amount for one class, how many said it.
    struct Report: Decodable, Hashable {
        let cls: String
        let isk: Double
        let count: Int
        var last: String?

        enum CodingKeys: String, CodingKey { case cls = "class", isk, count, last }
    }

    let id: String
    let type: String
    let name: String
    var lat: Double?
    var lon: Double?
    var points: [[Double]]?
    var path: [[Double]]?
    var radiusM: Double?
    var prices: [Price]?
    var payUrl: String?
    var payMethods: [String]?
    var appName: String?
    var windowBeforeH: Int?
    var windowAfterH: Int?
    var since: String?
    var until: String?
    var texts: [String: Texts]?
    var sourceName: String?
    let sourceUrl: String
    var sources: [Source]?
    let verifiedAt: String
    /// Prices reported by people using the app (last 120 days), most reported first.
    var reports: [Report]?

    var kind: Kind? { Kind(rawValue: type) }
    var isToll: Bool { kind == .tollTunnel || kind == .tollRoad }
    var isParking: Bool { kind == .paidParking }
    var allPrices: [Price] { prices ?? [] }

    var coordinate: Coordinate? {
        guard let lat, let lon else { return nil }
        return Coordinate(lat: lat, lon: lon)
    }

    var pointCoordinates: [Coordinate] { (points ?? []).compactMap { $0.count == 2 ? Coordinate(lat: $0[0], lon: $0[1]) : nil } }
    var pathCoordinates: [Coordinate] { (path ?? []).compactMap { $0.count == 2 ? Coordinate(lat: $0[0], lon: $0[1]) : nil } }

    /// In the app language; German, French and Spanish fall back to English, then Italian.
    var text: Texts {
        let all = texts ?? [:]
        return all[UILanguage.code] ?? all["en"] ?? all["it"] ?? Texts()
    }

    var verifiedDate: Date? { Self.day(verifiedAt) }
    var payURL: URL? { payUrl.flatMap(URL.init(string:)) }
    var sourceURL: URL? { URL(string: sourceUrl) }

    /// Not yet tolled (a road opening later) or no longer.
    func isActive(at date: Date = Date()) -> Bool {
        if let since = since.flatMap(Self.day), date < since { return false }
        if let until = until.flatMap(Self.day), date > until.addingTimeInterval(24 * 3600) { return false }
        return true
    }

    /// The price for the vehicle chosen in the app, nil when the source gives none for it.
    func price(for vehicle: TollVehicle = .current) -> Price? {
        for cls in vehicle.classes {
            if let price = allPrices.first(where: { $0.cls == cls }) { return price }
        }
        return nil
    }

    /// What travellers report for this vehicle: the most reported amount, how many
    /// reported it, how many reports in all for that class.
    func community(for vehicle: TollVehicle = .current) -> (isk: Double, count: Int, total: Int, cls: String)? {
        let all = reports ?? []
        for cls in vehicle.classes {
            let mine = all.filter { $0.cls == cls }
            guard let top = mine.max(by: { $0.count < $1.count }) else { continue }
            return (top.isk, top.count, mine.reduce(0) { $0 + $1.count }, cls)
        }
        return nil
    }

    /// Most of at least three recent reports say another amount than the official one.
    func reportsDisagree(for vehicle: TollVehicle = .current) -> (isk: Double, count: Int)? {
        guard let official = price(for: vehicle), let c = community(for: vehicle),
              c.count >= 3, c.count * 2 > c.total, abs(c.isk - official.isk) >= 1 else { return nil }
        return (c.isk, c.count)
    }

    /// Without an official price: the travellers' one, once at least three agree.
    func reportedPrice(for vehicle: TollVehicle = .current) -> Price? {
        guard price(for: vehicle) == nil, let c = community(for: vehicle), c.count >= 3, c.count * 2 > c.total else { return nil }
        return Price(cls: c.cls, isk: c.isk, unit: isToll ? "trip" : "day")
    }

    /// Closest distance (km) from a point to the entry: its section, its gates or its centre.
    func distanceKm(from c: Coordinate) -> Double? {
        var best: Double?
        let line = pathCoordinates
        if line.count >= 2 {
            for i in 1..<line.count { best = min(best ?? .infinity, Geo.distanceToSegmentKm(c, line[i - 1], line[i])) }
        }
        for p in pointCoordinates { best = min(best ?? .infinity, Geo.distanceKm(c, p)) }
        if let centre = coordinate { best = min(best ?? .infinity, Geo.distanceKm(c, centre)) }
        return best
    }

    /// The area of a car park (arrival), in km.
    var areaKm: Double { (radiusM ?? 600) / 1000 }

    var symbol: String {
        switch kind {
        case .tollTunnel: return "road.lanes.curved.right"
        case .tollRoad: return "road.lanes"
        case .paidParking: return "parkingsign.circle.fill"
        default: return "info.circle"
        }
    }

    var kindLabel: String {
        switch kind {
        case .tollTunnel: return String(localized: "Tunnel a pedaggio")
        case .tollRoad: return String(localized: "Strada a pedaggio")
        case .paidParking: return String(localized: "Parcheggio a pagamento")
        default: return String(localized: "Informazione")
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .iceland
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func day(_ text: String) -> Date? { dayFormatter.date(from: text) }

    static func == (a: TollEntry, b: TollEntry) -> Bool { a.id == b.id && a.verifiedAt == b.verifiedAt && a.allPrices == b.allPrices }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Which price applies: tunnels and roads price by weight, car parks by seats.
enum TollVehicle: String, CaseIterable, Identifiable {
    case car, van, camper, motorcycle

    static let key = "tolls.vehicle"
    static var current: TollVehicle { TollVehicle(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .car }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .car: return String(localized: "Auto fino a 5 posti (sotto 3,5 t)")
        case .van: return String(localized: "Auto o furgone da 6 a 9 posti (sotto 3,5 t)")
        case .camper: return String(localized: "Camper o furgone da 3,5 a 7,5 t")
        case .motorcycle: return String(localized: "Moto")
        }
    }

    /// Price classes of the catalog, best match first.
    var classes: [String] {
        switch self {
        case .car: return ["car_5", "under_3_5t"]
        case .van: return ["car_6_9", "under_3_5t"]
        case .camper: return ["t3_5_7_5"]
        case .motorcycle: return ["motorcycle"]
        }
    }
}

extension TollEntry.Price {
    var classLabel: String {
        switch cls {
        case "under_3_5t": return String(localized: "Veicoli fino a 3,5 t")
        case "t3_5_7_5": return String(localized: "Veicoli da 3,5 a 7,5 t")
        case "over_7_5t": return String(localized: "Veicoli oltre 7,5 t")
        case "motorcycle": return String(localized: "Moto")
        case "car_5": return String(localized: "Auto fino a 5 posti")
        case "car_6_9": return String(localized: "Auto da 6 a 9 posti")
        case "bus_10_19": return String(localized: "Bus da 10 a 19 posti")
        case "bus_10_21": return String(localized: "Bus da 10 a 21 posti")
        case "bus_20_32": return String(localized: "Bus da 20 a 32 posti")
        case "bus_22_32": return String(localized: "Bus da 22 a 32 posti")
        case "bus_33": return String(localized: "Bus da 33 posti in su")
        default: return cls
        }
    }

    var unitLabel: String {
        switch unit {
        case "trip": return String(localized: "a passaggio")
        case "day": return String(localized: "al giorno")
        case "hour": return String(localized: "all'ora")
        case "km": return String(localized: "al km")
        default: return unit
        }
    }

    /// "2.216 ISK", "6,95 ISK".
    var iskText: String {
        let whole = isk.rounded() == isk
        return "\(Fmt.number(isk, decimals: whole ? 0 : 2)) ISK"
    }
}

enum Tolls {
    static let endpoint = URL(string: "https://nordur-api.vercel.app/api/tolls")!

    private struct File: Decodable {
        let entries: [TollEntry]
        var reports: [String: [TollEntry.Report]]?
    }

    static func parse(_ data: Data) throws -> [TollEntry] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let file = try decoder.decode(File.self, from: data)
        return file.entries.map { entry in
            var entry = entry
            entry.reports = file.reports?[entry.id]
            return entry
        }
    }

    enum ReportError: LocalizedError {
        case refused(String)
        var errorDescription: String? {
            switch self { case .refused(let message): return message }
        }
    }

    /// A random id of this phone for the reports (no account): with the network
    /// it limits them to one per toll per day.
    static var clientID: String {
        if let id = UserDefaults.standard.string(forKey: "tolls.client") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "tolls.client")
        return id
    }

    /// Tells nordur-api what you paid.
    static func report(entry: TollEntry, cls: String, isk: Int) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["entry": entry.id, "class": cls, "isk": isk, "client": clientID] as [String: Any])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message: String
            switch object?["code"] as? String {
            case "amount": message = String(localized: "Importo non valido: scrivi le corone, tra 50 e 100.000.")
            case "far": message = String(localized: "L'importo è troppo lontano dal prezzo ufficiale: controlla di aver scritto le corone.")
            case "rate": message = String(localized: "Troppe segnalazioni: riprova più tardi.")
            default: message = String(localized: "Segnalazione non inviata, riprova più tardi.")
            }
            throw ReportError.refused(message)
        }
        UserDefaults.standard.set(Date(), forKey: "tolls.reported.\(entry.id)")
    }

    /// Already reported today from this phone.
    static func reportedToday(_ entry: TollEntry) -> Bool {
        guard let date = UserDefaults.standard.object(forKey: "tolls.reported.\(entry.id)") as? Date else { return false }
        return Calendar.iceland.isDate(date, inSameDayAs: Date())
    }

    /// The catalog, from nordur-api; the copy on the phone when offline.
    static func load() async throws -> Fetched<[TollEntry]> {
        try await HTTP.get(endpoint, cacheKey: "tolls_catalog").map { try parse($0) }
    }

    /// "≈ 13,20 € · 14,10 US$" for króna, in the currencies chosen in Settings.
    static func converted(_ isk: Double, rates: ExchangeRates?) -> String? {
        let display = CurrencyDisplay(rawValue: UserDefaults.standard.string(forKey: CurrencyDisplay.key) ?? "both") ?? .both
        return display.converted(isk, rates)
    }

    /// The car parks whose area holds this place (a stop, a visit).
    static func parking(at c: Coordinate, in entries: [TollEntry], date: Date = Date()) -> [TollEntry] {
        entries.filter { $0.isParking && $0.isActive(at: date) && ($0.distanceKm(from: c) ?? .infinity) <= max($0.areaKm, 0.5) + 0.3 }
    }
}

// MARK: - Legs of the trip

/// What a drive between two stops pays: tolls on the way (from the driving
/// route, Apple Maps) and paid parking where you arrive and at the visits.
struct TollCharge: Identifiable, Hashable {
    let entry: TollEntry
    let price: TollEntry.Price?
    /// Where it is paid: on the leg towards the stop, or at the stop.
    let atStop: Bool
    var id: String { "\(entry.id)-\(atStop)" }
}

/// Driving routes between trip stops, to know which tolls a leg really passes.
/// Computed once per leg (Apple Maps) and kept on the phone; until then, a
/// strict straight-line estimate.
@MainActor
@Observable
final class TollRoutes {
    static let shared = TollRoutes()

    /// Leg key -> ids of the tolled entries the route passes.
    private(set) var passes: [String: [String]] = [:]
    @ObservationIgnored private var pending: Set<String> = []
    private static let storeKey = "tolls.legRoutes.v1"
    private static let signatureKey = "tolls.legRoutes.signature"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let stored = try? JSONDecoder().decode([String: [String]].self, from: data) {
            passes = stored
        }
    }

    static func key(_ a: Coordinate, _ b: Coordinate) -> String { "\(a.key)>\(b.key)" }

    /// The tolled entries on a drive, from the route when known.
    func tolls(from a: Coordinate, to b: Coordinate, entries: [TollEntry], date: Date) -> [TollEntry] {
        let tolled = entries.filter { $0.isToll && $0.isActive(at: date) }
        guard !tolled.isEmpty else { return [] }
        let key = Self.key(a, b)
        if let ids = passes[key] {
            return tolled.filter { ids.contains($0.id) }
        }
        request(from: a, to: b, key: key, tolled: tolled)
        return tolled.filter { Self.likely($0, from: a, to: b) }
    }

    /// A toll added, moved or removed in the panel: every leg is computed again.
    func catalogChanged(_ entries: [TollEntry]) {
        let signature = entries.filter(\.isToll).map { "\($0.id):\($0.pointCoordinates.count):\($0.since ?? "")" }.sorted().joined(separator: ",")
        guard UserDefaults.standard.string(forKey: Self.signatureKey) != signature else { return }
        UserDefaults.standard.set(signature, forKey: Self.signatureKey)
        passes = [:]
        pending.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.storeKey)
    }

    /// Without a route: the leg passes the section only if going through it costs
    /// almost no detour (both gates, in either order).
    nonisolated static func likely(_ entry: TollEntry, from a: Coordinate, to b: Coordinate) -> Bool {
        let gates = entry.pointCoordinates
        guard gates.count >= 2, let first = gates.first, let last = gates.last else { return false }
        let direct = Geo.distanceKm(a, b)
        guard direct > 2 else { return false }
        let section = Geo.distanceKm(first, last)
        let detour = min(Geo.distanceKm(a, first) + section + Geo.distanceKm(last, b),
                         Geo.distanceKm(a, last) + section + Geo.distanceKm(first, b)) - direct
        return detour <= max(3, direct * 0.04)
    }

    private func request(from a: Coordinate, to b: Coordinate, key: String, tolled: [TollEntry]) {
        guard !pending.contains(key) else { return }
        pending.insert(key)
        Task { @MainActor in
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: a.clCoordinate))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: b.clCoordinate))
            request.transportType = .automobile
            guard let route = try? await MKDirections(request: request).calculate().routes.first else { return }
            let mapPoints = route.polyline.points()
            let line = (0..<route.polyline.pointCount).map { Coordinate(mapPoints[$0].coordinate) }
            let ids = tolled.filter { Self.routePasses(line, $0) }.map(\.id)
            passes[key] = ids
            if passes.count > 400 { passes = [:]; passes[key] = ids }
            if let data = try? JSONEncoder().encode(passes) { UserDefaults.standard.set(data, forKey: Self.storeKey) }
        }
    }

    /// The route passes a toll when it comes close to both of its gates (the
    /// whole section), or to its line for one without gates.
    nonisolated static func routePasses(_ route: [Coordinate], _ entry: TollEntry) -> Bool {
        guard route.count >= 2 else { return false }
        func near(_ c: Coordinate, _ km: Double) -> Bool {
            for i in 1..<route.count where Geo.distanceToSegmentKm(c, route[i - 1], route[i]) <= km { return true }
            return false
        }
        let gates = entry.pointCoordinates
        if gates.count >= 2 { return gates.allSatisfy { near($0, 0.6) } }
        if let centre = entry.coordinate { return near(centre, 0.4) }
        return false
    }
}

/// A stop of the trip and what arriving there costs.
struct TripTollStop: Identifiable {
    let stop: TripStop
    let charges: [TollCharge]
    var id: UUID { stop.id }
}

enum TripTolls {
    /// What arriving at a stop costs: the tolls on the drive from the previous
    /// stop (by car or bus) and the paid parking at the stop and its visits.
    @MainActor
    static func charges(to stop: TripStop, from previous: TripStop?, entries: [TollEntry], vehicle: TollVehicle = .current) -> [TollCharge] {
        guard !entries.isEmpty else { return [] }
        var charges: [TollCharge] = []
        if let previous, stop.transport == .car || stop.transport == .bus {
            for entry in TollRoutes.shared.tolls(from: previous.place.coordinate, to: stop.place.coordinate, entries: entries, date: stop.date) {
                charges.append(TollCharge(entry: entry, price: entry.price(for: vehicle) ?? entry.reportedPrice(for: vehicle), atStop: false))
            }
        }
        var seen = Set<String>()
        for c in [stop.place.coordinate] + stop.visits.map(\.place.coordinate) {
            for entry in Tolls.parking(at: c, in: entries, date: stop.date) where seen.insert(entry.id).inserted {
                charges.append(TollCharge(entry: entry, price: entry.price(for: vehicle) ?? entry.reportedPrice(for: vehicle), atStop: true))
            }
        }
        return charges
    }

    /// For each stop of the trip, in date order.
    @MainActor
    static func charges(stops: [TripStop], entries: [TollEntry], vehicle: TollVehicle = .current) -> [TripTollStop] {
        let sorted = stops.sorted { $0.date < $1.date }
        var result: [TripTollStop] = []
        for (i, stop) in sorted.enumerated() {
            let found = Self.charges(to: stop, from: i > 0 ? sorted[i - 1] : nil, entries: entries, vehicle: vehicle)
            if !found.isEmpty { result.append(TripTollStop(stop: stop, charges: found)) }
        }
        return result
    }

    /// Sum in króna of the charges with a price per trip or day, and how many have none.
    static func total(_ charges: [TollCharge]) -> (isk: Double, unpriced: Int) {
        var isk = 0.0, unpriced = 0
        for charge in charges {
            if let price = charge.price, price.unit == "trip" || price.unit == "day" { isk += price.isk } else { unpriced += 1 }
        }
        return (isk, unpriced)
    }
}
