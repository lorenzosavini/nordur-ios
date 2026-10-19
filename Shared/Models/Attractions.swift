import Foundation

enum AttractionKind: String, Codable, CaseIterable, Identifiable {
    case waterfall, beach, glacier, geothermal, canyon, landscape, bath, town, wildlife, shop

    var id: String { rawValue }

    var label: String {
        switch self {
        case .waterfall: return String(localized: "Cascata")
        case .beach: return String(localized: "Spiaggia")
        case .glacier: return String(localized: "Ghiacciaio e laguna")
        case .geothermal: return String(localized: "Area geotermica")
        case .canyon: return String(localized: "Canyon")
        case .landscape: return String(localized: "Paesaggio e belvedere")
        case .bath: return String(localized: "Bagni termali")
        case .town: return String(localized: "Città e monumenti")
        case .wildlife: return String(localized: "Natura e animali")
        case .shop: return String(localized: "Spesa")
        }
    }

    var symbol: String {
        switch self {
        case .waterfall: return "drop.fill"
        case .beach: return "water.waves"
        case .glacier: return "snowflake"
        case .geothermal: return "flame.fill"
        case .canyon: return "mountain.2.fill"
        case .landscape: return "binoculars.fill"
        case .bath: return "figure.pool.swim"
        case .town: return "building.columns.fill"
        case .wildlife: return "bird.fill"
        case .shop: return "cart.fill"
        }
    }
}

/// A place worth stopping at, with a usual length of visit and, when there is
/// one, what to watch out for there.
struct Attraction: Identifiable, Hashable {
    let name: String
    let lat: Double
    let lon: Double
    let kind: AttractionKind
    let minutes: Int
    var region: String
    var caution: String? = nil
    /// Places from OpenStreetMap; nil for the sights of the app's own list.
    var osmID: Int? = nil
    /// On Wikipedia (or in the app's own list): the better-known places come first.
    var notable = true
    var detail: String? = nil

    var id: String { osmID.map { "osm\($0)" } ?? name }
    var isTop: Bool { osmID == nil }
    var coordinate: Coordinate { Coordinate(lat: lat, lon: lon) }
    var place: Place { Place(name: name, coordinate: coordinate, subtitle: region) }
}

extension Attraction {
    /// The main sights of Iceland. Coordinates are those of the sight (parking is usually close).
    static let catalog: [Attraction] = [
        // Reykjavík and Reykjanes
        Attraction(name: "Hallgrímskirkja", lat: 64.1417, lon: -21.9266, kind: .town, minutes: 45, region: "Reykjavík"),
        Attraction(name: "Harpa", lat: 64.1504, lon: -21.9325, kind: .town, minutes: 40, region: "Reykjavík"),
        Attraction(name: "Sky Lagoon", lat: 64.1162, lon: -21.9550, kind: .bath, minutes: 150, region: "Reykjavík"),
        Attraction(name: "Blue Lagoon", lat: 63.8804, lon: -22.4495, kind: .bath, minutes: 180, region: "Reykjanes"),
        Attraction(name: "Ponte tra i continenti", lat: 63.8680, lon: -22.6754, kind: .landscape, minutes: 20, region: "Reykjanes"),
        Attraction(name: "Gunnuhver", lat: 63.8193, lon: -22.6847, kind: .geothermal, minutes: 30, region: "Reykjanes"),
        // Golden Circle
        Attraction(name: "Þingvellir", lat: 64.2559, lon: -21.1299, kind: .landscape, minutes: 90, region: "Golden Circle"),
        Attraction(name: "Geysir e Strokkur", lat: 64.3104, lon: -20.3024, kind: .geothermal, minutes: 60, region: "Golden Circle"),
        Attraction(name: "Gullfoss", lat: 64.3271, lon: -20.1199, kind: .waterfall, minutes: 60, region: "Golden Circle"),
        Attraction(name: "Kerið", lat: 64.0411, lon: -20.8853, kind: .landscape, minutes: 30, region: "Golden Circle"),
        Attraction(name: "Brúarfoss", lat: 64.2644, lon: -20.5156, kind: .waterfall, minutes: 75, region: "Golden Circle"),
        Attraction(name: "Secret Lagoon", lat: 64.1375, lon: -20.3097, kind: .bath, minutes: 90, region: "Golden Circle"),
        // South coast
        Attraction(name: "Seljalandsfoss", lat: 63.6156, lon: -19.9886, kind: .waterfall, minutes: 45, region: "Costa sud",
                   caution: String(localized: "Il sentiero dietro la cascata è chiuso e ghiacciato in inverno.")),
        Attraction(name: "Gljúfrabúi", lat: 63.6206, lon: -19.9861, kind: .waterfall, minutes: 20, region: "Costa sud"),
        Attraction(name: "Skógafoss", lat: 63.5321, lon: -19.5114, kind: .waterfall, minutes: 45, region: "Costa sud"),
        Attraction(name: "Sólheimajökull", lat: 63.5306, lon: -19.3700, kind: .glacier, minutes: 60, region: "Costa sud",
                   caution: String(localized: "Sul ghiacciaio solo con una guida.")),
        Attraction(name: "Dyrhólaey", lat: 63.4022, lon: -19.1300, kind: .landscape, minutes: 45, region: "Costa sud",
                   caution: String(localized: "Strada chiusa con vento forte e in primavera per la nidificazione.")),
        Attraction(name: "Reynisfjara", lat: 63.4044, lon: -19.0447, kind: .beach, minutes: 45, region: "Costa sud",
                   caution: String(localized: "Onde anomale: stai lontano dall'acqua, mai di spalle al mare.")),
        Attraction(name: "Vík í Mýrdal", lat: 63.4197, lon: -19.0064, kind: .town, minutes: 30, region: "Costa sud"),
        Attraction(name: "Fjaðrárgljúfur", lat: 63.7713, lon: -18.1719, kind: .canyon, minutes: 45, region: "Costa sud"),
        // South-east
        Attraction(name: "Skaftafell e Svartifoss", lat: 64.0275, lon: -16.9750, kind: .waterfall, minutes: 120, region: "Sud-est"),
        Attraction(name: "Fjallsárlón", lat: 64.0167, lon: -16.3667, kind: .glacier, minutes: 40, region: "Sud-est"),
        Attraction(name: "Jökulsárlón", lat: 64.0784, lon: -16.2306, kind: .glacier, minutes: 60, region: "Sud-est"),
        Attraction(name: "Diamond Beach", lat: 64.0444, lon: -16.1781, kind: .beach, minutes: 40, region: "Sud-est",
                   caution: String(localized: "Onde forti: non salire sui blocchi di ghiaccio vicino all'acqua.")),
        Attraction(name: "Stokksnes e Vestrahorn", lat: 64.2483, lon: -14.9958, kind: .landscape, minutes: 60, region: "Sud-est"),
        // East and north-east
        Attraction(name: "Stuðlagil", lat: 65.1650, lon: -15.3070, kind: .canyon, minutes: 90, region: "Est"),
        Attraction(name: "Seyðisfjörður", lat: 65.2603, lon: -14.0097, kind: .town, minutes: 60, region: "Est",
                   caution: String(localized: "Il passo Fjarðarheiði chiude spesso con la neve.")),
        Attraction(name: "Dettifoss", lat: 65.8147, lon: -16.3844, kind: .waterfall, minutes: 60, region: "Nord-est",
                   caution: String(localized: "La strada 862 d'inverno può essere chiusa.")),
        Attraction(name: "Ásbyrgi", lat: 66.0167, lon: -16.5000, kind: .canyon, minutes: 60, region: "Nord-est"),
        Attraction(name: "Húsavík", lat: 66.0449, lon: -17.3389, kind: .wildlife, minutes: 180, region: "Nord",
                   caution: String(localized: "Le uscite per le balene dipendono dal mare.")),
        // Mývatn and the north
        Attraction(name: "Hverir", lat: 65.6411, lon: -16.8094, kind: .geothermal, minutes: 40, region: "Mývatn"),
        Attraction(name: "Mývatn Nature Baths", lat: 65.6311, lon: -16.8467, kind: .bath, minutes: 120, region: "Mývatn"),
        Attraction(name: "Dimmuborgir", lat: 65.5911, lon: -16.9089, kind: .landscape, minutes: 60, region: "Mývatn"),
        Attraction(name: "Grjótagjá", lat: 65.6262, lon: -16.8828, kind: .geothermal, minutes: 20, region: "Mývatn"),
        Attraction(name: "Goðafoss", lat: 65.6828, lon: -17.5502, kind: .waterfall, minutes: 40, region: "Nord"),
        Attraction(name: "Akureyri", lat: 65.6835, lon: -18.0878, kind: .town, minutes: 120, region: "Nord"),
        Attraction(name: "Hvítserkur", lat: 65.6061, lon: -20.6375, kind: .landscape, minutes: 40, region: "Nord-ovest"),
        // West, Snæfellsnes, Westfjords
        Attraction(name: "Hraunfossar e Barnafoss", lat: 64.7025, lon: -20.9775, kind: .waterfall, minutes: 40, region: "Ovest"),
        Attraction(name: "Deildartunguhver", lat: 64.6636, lon: -21.4111, kind: .geothermal, minutes: 20, region: "Ovest"),
        Attraction(name: "Kirkjufell", lat: 64.9417, lon: -23.3069, kind: .landscape, minutes: 45, region: "Snæfellsnes"),
        Attraction(name: "Arnarstapi", lat: 64.7686, lon: -23.6236, kind: .landscape, minutes: 45, region: "Snæfellsnes"),
        Attraction(name: "Djúpalónssandur", lat: 64.7522, lon: -23.8967, kind: .beach, minutes: 40, region: "Snæfellsnes",
                   caution: String(localized: "Onde forti: stai lontano dalla riva.")),
        Attraction(name: "Búðakirkja", lat: 64.8217, lon: -23.3842, kind: .town, minutes: 20, region: "Snæfellsnes"),
        Attraction(name: "Dynjandi", lat: 65.7317, lon: -23.1997, kind: .waterfall, minutes: 60, region: "Fiordi occidentali",
                   caution: String(localized: "D'inverno le strade dei fiordi occidentali chiudono spesso.")),
        // Highlands (summer only)
        Attraction(name: "Landmannalaugar", lat: 63.9910, lon: -19.0600, kind: .geothermal, minutes: 180, region: "Highlands",
                   caution: String(localized: "Solo d'estate, con un 4×4 su strade F con guadi.")),
    ]

    /// Attractions sorted by distance from a point, closest first.
    static func near(_ c: Coordinate, within km: Double = 400) -> [Attraction] {
        catalog.map { ($0, Geo.distanceKm(c, $0.coordinate)) }
            .filter { $0.1 <= km }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    static func named(_ name: String) -> Attraction? { catalog.first { $0.name == name } }
}
