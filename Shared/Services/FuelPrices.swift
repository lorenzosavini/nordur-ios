import Foundation

/// Fuel prices at the pump in Iceland, live: Gasvaktin (github.com/gasvaktin)
/// reads the prices the companies publish (N1, Olís, Orkan, ÓB, Atlantsolía,
/// Costco) several times a day, for about 245 stations with their position.
struct FuelPrice: Decodable, Identifiable, Hashable {
    struct Geo: Decodable, Hashable { let lat: Double; let lon: Double }
    let key: String
    let company: String
    let name: String
    let geo: Geo
    let bensin95: Double?
    let bensin95_discount: Double?
    let diesel: Double?
    let diesel_discount: Double?

    var id: String { key }
    var coordinate: Coordinate { Coordinate(lat: geo.lat, lon: geo.lon) }

    func price(_ fuel: FuelKind) -> Double? { fuel == .petrol ? bensin95 : diesel }
    func discount(_ fuel: FuelKind) -> Double? { fuel == .petrol ? bensin95_discount : diesel_discount }
}

enum FuelKind: String, CaseIterable, Identifiable {
    case petrol, diesel
    var id: String { rawValue }
    var label: String { self == .petrol ? String(localized: "Benzina 95") : String(localized: "Diesel") }
}

enum FuelPrices {
    private struct Response: Decodable { let stations: [FuelPrice] }

    static func load() async throws -> Fetched<[FuelPrice]> {
        guard let url = URL(string: "https://raw.githubusercontent.com/gasvaktin/gasvaktin/master/vaktin/gas.min.json") else { throw HTTPError.invalidURL }
        return try await HTTP.json(Response.self, from: url, cacheKey: "fuel_prices").map(\.stations)
    }

    /// The prices of an OpenStreetMap station: the Gasvaktin station at the same
    /// place (within 400 m; 1 km when the brand matches).
    static func match(_ station: FuelStation, in prices: [FuelPrice]) -> FuelPrice? {
        let brand = (station.brand ?? station.name).lowercased()
        return prices
            .map { (price: $0, km: Geo.distanceKm($0.coordinate, station.coordinate)) }
            .filter { $0.km <= 0.4 || ($0.km <= 1 && brand.contains($0.price.company.lowercased().prefix(3))) }
            .min { $0.km < $1.km }?.price
    }

    /// Cheap, average or dear compared with all the pumps in Iceland now:
    /// the cheapest quarter, the middle half, the dearest quarter.
    enum Level { case cheap, average, dear }

    static func level(_ value: Double, among prices: [FuelPrice], fuel: FuelKind) -> Level {
        let all = prices.compactMap { $0.price(fuel) }.sorted()
        guard all.count >= 4 else { return .average }
        let low = all[all.count / 4], high = all[(all.count * 3) / 4]
        return value <= low ? .cheap : value >= high ? .dear : .average
    }

    /// The cheapest within `km` of a point, for one fuel.
    static func cheapest(_ prices: [FuelPrice], near point: Coordinate, within km: Double = 30, fuel: FuelKind) -> (price: FuelPrice, km: Double)? {
        prices.compactMap { p -> (FuelPrice, Double)? in
            let d = Geo.distanceKm(p.coordinate, point)
            return d <= km && p.price(fuel) != nil ? (p, d) : nil
        }
        .min { ($0.0.price(fuel) ?? .infinity) < ($1.0.price(fuel) ?? .infinity) }
        .map { (price: $0.0, km: $0.1) }
    }
}

/// Every world currency for one Icelandic króna: ExchangeRate-API's open daily
/// rates (about 160 currencies, no key; attribution required), or the European
/// Central Bank's reference rates (Frankfurter, about 30) when it doesn't answer.
struct ExchangeRates: Decodable {
    let date: String
    let rates: [String: Double]
    var source: String?

    /// Amount in króna for one unit of a currency (ISK itself is 1).
    func perUnit(_ code: String) -> Double? { code == "ISK" ? 1 : rates[code].flatMap { $0 > 0 ? 1 / $0 : nil } }

    /// An amount from one currency to another.
    func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let a = perUnit(from), let b = perUnit(to) else { return nil }
        return amount * a / b
    }

    private struct Open: Decodable {
        let result: String
        let time_last_update_unix: Double?
        let rates: [String: Double]?
    }

    static func load() async throws -> Fetched<ExchangeRates> {
        do {
            guard let url = URL(string: "https://open.er-api.com/v6/latest/ISK") else { throw HTTPError.invalidURL }
            let fetched = try await HTTP.json(Open.self, from: url, cacheKey: "rates_isk_world")
            guard fetched.value.result == "success", let rates = fetched.value.rates, rates.count > 30 else { throw URLError(.badServerResponse) }
            let day = Date(timeIntervalSince1970: fetched.value.time_last_update_unix ?? fetched.date.timeIntervalSince1970)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            return Fetched(value: ExchangeRates(date: formatter.string(from: day), rates: rates, source: "ExchangeRate-API"), date: fetched.date, isStale: fetched.isStale)
        } catch {
            guard let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=ISK") else { throw HTTPError.invalidURL }
            let fetched = try await HTTP.json(ExchangeRates.self, from: url, cacheKey: "rates_isk_ecb")
            var value = fetched.value
            value.source = String(localized: "BCE")
            return Fetched(value: value, date: fetched.date, isStale: fetched.isStale)
        }
    }

    /// Currency codes known to the system, with these rates when loaded, by localized name.
    static func codes(_ rates: ExchangeRates?) -> [String] {
        let all = Set(Locale.commonISOCurrencyCodes).subtracting(["ISK"])
        let known = rates.map { all.intersection($0.rates.keys) } ?? all
        return known.sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
    }

    static func name(_ code: String) -> String {
        Fmt.italian.localizedString(forCurrencyCode: code)?.capitalized(with: Fmt.italian) ?? code
    }

    /// "1,87 €", "¥ 290", "2,09 US$" in the app language, without more decimals than asked.
    static func format(_ amount: Double, _ code: String, decimals: Int = 2) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Fmt.italian
        f.currencyCode = code
        f.maximumFractionDigits = min(decimals, f.maximumFractionDigits)
        f.minimumFractionDigits = min(f.minimumFractionDigits, f.maximumFractionDigits)
        return f.string(from: NSNumber(value: amount)) ?? "\(Fmt.number(amount, decimals: decimals)) \(code)"
    }
}

/// The other currencies the prices in króna are shown in (Settings › Unità di misura):
/// up to three of any in the world, or none.
struct CurrencyDisplay: Equatable {
    static let key = "currency.display"
    static let both = CurrencyDisplay(codes: ["EUR", "USD"])
    static let limit = 3
    let codes: [String]

    init(codes: [String]) { self.codes = Array(codes.prefix(Self.limit)) }

    /// Older choices ("both", "eur", "usd", "none") and lists of codes ("EUR,GBP").
    init?(rawValue: String) {
        switch rawValue {
        case "both": self.init(codes: ["EUR", "USD"])
        case "eur": self.init(codes: ["EUR"])
        case "usd": self.init(codes: ["USD"])
        case "none", "": self.init(codes: [])
        default:
            let codes = rawValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { $0.count == 3 }
            self.init(codes: codes)
        }
    }

    var rawValue: String { codes.isEmpty ? "none" : codes.joined(separator: ",") }

    var label: String { codes.isEmpty ? String(localized: "Solo corone") : codes.joined(separator: " · ") }

    /// "≈ 1,87 € · 2,09 US$" for an amount in króna, or nil without rates.
    func converted(_ isk: Double, _ rates: ExchangeRates?, decimals: Int = 2) -> String? {
        guard let rates, !codes.isEmpty else { return nil }
        let parts = codes.compactMap { code in rates.convert(isk, from: "ISK", to: code).map { ExchangeRates.format($0, code, decimals: decimals) } }
        return parts.isEmpty ? nil : "≈ " + parts.joined(separator: " · ")
    }
}
