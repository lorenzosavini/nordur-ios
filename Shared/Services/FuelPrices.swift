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

/// Euro and dollar for one Icelandic króna, from the European Central Bank's
/// daily reference rates (Frankfurter).
struct ExchangeRates: Decodable {
    let date: String
    let rates: [String: Double]

    static func load() async throws -> Fetched<ExchangeRates> {
        guard let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=ISK&symbols=EUR,USD") else { throw HTTPError.invalidURL }
        return try await HTTP.json(ExchangeRates.self, from: url, cacheKey: "rates_isk")
    }
}

/// Which other currency the prices in króna are shown in (Settings › Unità di misura).
enum CurrencyDisplay: String, CaseIterable, Identifiable {
    case both, eur, usd, none
    static let key = "currency.display"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .both: return String(localized: "Euro e dollari")
        case .eur: return String(localized: "Euro")
        case .usd: return String(localized: "Dollari")
        case .none: return String(localized: "Solo corone")
        }
    }

    /// "≈ 1,87 € · 2,09 $" for an amount in króna, or nil without rates.
    func converted(_ isk: Double, _ rates: ExchangeRates?, decimals: Int = 2) -> String? {
        guard let rates, self != .none else { return nil }
        var parts: [String] = []
        if self == .both || self == .eur, let eur = rates.rates["EUR"] { parts.append("\(Fmt.number(isk * eur, decimals: decimals)) €") }
        if self == .both || self == .usd, let usd = rates.rates["USD"] { parts.append("\(Fmt.number(isk * usd, decimals: decimals)) $") }
        return parts.isEmpty ? nil : "≈ " + parts.joined(separator: " · ")
    }
}
