import Foundation

struct Place: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var coordinate: Coordinate
    var subtitle: String?

    init(id: UUID = UUID(), name: String, lat: Double, lon: Double, subtitle: String? = nil) {
        self.id = id
        self.name = name
        self.coordinate = Coordinate(lat: lat, lon: lon)
        self.subtitle = subtitle
    }

    init(name: String, coordinate: Coordinate, subtitle: String? = nil) {
        self.name = name
        self.coordinate = coordinate
        self.subtitle = subtitle
    }
}

extension Place {
    static let reykjavik = Place(name: "Reykjavík", lat: 64.1466, lon: -21.9426, subtitle: String(localized: "Capitale"))

    /// Places most Iceland itineraries touch, grouped roughly along the Ring Road.
    static let presets: [Place] = [
        reykjavik,
        Place(name: "Aeroporto di Keflavík (KEF)", lat: 63.9850, lon: -22.6056, subtitle: String(localized: "Penisola di Reykjanes")),
        Place(name: "Blue Lagoon / Grindavík", lat: 63.8804, lon: -22.4495, subtitle: String(localized: "Reykjanes – zona vulcanica attiva")),
        Place(name: "Þingvellir", lat: 64.2559, lon: -21.1299, subtitle: String(localized: "Golden Circle")),
        Place(name: "Geysir", lat: 64.3104, lon: -20.3024, subtitle: String(localized: "Golden Circle")),
        Place(name: "Gullfoss", lat: 64.3271, lon: -20.1199, subtitle: String(localized: "Golden Circle")),
        Place(name: "Selfoss", lat: 63.9331, lon: -20.9971, subtitle: String(localized: "Sud")),
        Place(name: "Seljalandsfoss", lat: 63.6156, lon: -19.9886, subtitle: String(localized: "Sud")),
        Place(name: "Landeyjahöfn (traghetto)", lat: 63.5300, lon: -20.1200, subtitle: String(localized: "Porto per Vestmannaeyjar")),
        Place(name: "Vestmannaeyjar", lat: 63.4427, lon: -20.2734, subtitle: String(localized: "Isole Westman")),
        Place(name: "Skógafoss", lat: 63.5321, lon: -19.5114, subtitle: String(localized: "Sud")),
        Place(name: "Reynisfjara", lat: 63.4044, lon: -19.0450, subtitle: String(localized: "Spiaggia nera – onde anomale")),
        Place(name: "Vík í Mýrdal", lat: 63.4186, lon: -19.0060, subtitle: String(localized: "Sud")),
        Place(name: "Landmannalaugar", lat: 63.9910, lon: -19.0605, subtitle: String(localized: "Highlands – solo strade F")),
        Place(name: "Skaftafell", lat: 64.0160, lon: -16.9660, subtitle: String(localized: "Vatnajökull")),
        Place(name: "Jökulsárlón", lat: 64.0784, lon: -16.2306, subtitle: String(localized: "Laguna glaciale")),
        Place(name: "Höfn", lat: 64.2539, lon: -15.2082, subtitle: String(localized: "Sud-est")),
        Place(name: "Egilsstaðir", lat: 65.2653, lon: -14.3948, subtitle: String(localized: "Est")),
        Place(name: "Seyðisfjörður", lat: 65.2597, lon: -14.0103, subtitle: String(localized: "Fiordi orientali")),
        Place(name: "Dettifoss", lat: 65.8147, lon: -16.3846, subtitle: String(localized: "Nord-est")),
        Place(name: "Mývatn (Reykjahlíð)", lat: 65.6436, lon: -16.9100, subtitle: String(localized: "Nord")),
        Place(name: "Húsavík", lat: 66.0449, lon: -17.3389, subtitle: String(localized: "Nord – whale watching")),
        Place(name: "Akureyri", lat: 65.6885, lon: -18.1262, subtitle: String(localized: "Nord")),
        Place(name: "Siglufjörður", lat: 66.1522, lon: -18.9100, subtitle: String(localized: "Penisola di Tröllaskagi")),
        Place(name: "Ísafjörður", lat: 66.0750, lon: -23.1350, subtitle: String(localized: "Fiordi occidentali")),
        Place(name: "Kirkjufell / Grundarfjörður", lat: 64.9419, lon: -23.3067, subtitle: String(localized: "Snæfellsnes")),
        Place(name: "Arnarstapi", lat: 64.7680, lon: -23.6250, subtitle: String(localized: "Snæfellsnes")),
        Place(name: "Borgarnes", lat: 64.5383, lon: -21.9206, subtitle: String(localized: "Ovest")),
    ]
}
