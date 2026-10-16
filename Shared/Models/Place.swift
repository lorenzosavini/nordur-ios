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
    static let reykjavik = Place(name: "Reykjavík", lat: 64.1466, lon: -21.9426, subtitle: "Capitale")

    /// Places most Iceland itineraries touch, grouped roughly along the Ring Road.
    static let presets: [Place] = [
        reykjavik,
        Place(name: "Aeroporto di Keflavík (KEF)", lat: 63.9850, lon: -22.6056, subtitle: "Penisola di Reykjanes"),
        Place(name: "Blue Lagoon / Grindavík", lat: 63.8804, lon: -22.4495, subtitle: "Reykjanes – zona vulcanica attiva"),
        Place(name: "Þingvellir", lat: 64.2559, lon: -21.1299, subtitle: "Golden Circle"),
        Place(name: "Geysir", lat: 64.3104, lon: -20.3024, subtitle: "Golden Circle"),
        Place(name: "Gullfoss", lat: 64.3271, lon: -20.1199, subtitle: "Golden Circle"),
        Place(name: "Selfoss", lat: 63.9331, lon: -20.9971, subtitle: "Sud"),
        Place(name: "Seljalandsfoss", lat: 63.6156, lon: -19.9886, subtitle: "Sud"),
        Place(name: "Landeyjahöfn (traghetto)", lat: 63.5300, lon: -20.1200, subtitle: "Porto per Vestmannaeyjar"),
        Place(name: "Vestmannaeyjar", lat: 63.4427, lon: -20.2734, subtitle: "Isole Westman"),
        Place(name: "Skógafoss", lat: 63.5321, lon: -19.5114, subtitle: "Sud"),
        Place(name: "Reynisfjara", lat: 63.4044, lon: -19.0450, subtitle: "Spiaggia nera – onde anomale"),
        Place(name: "Vík í Mýrdal", lat: 63.4186, lon: -19.0060, subtitle: "Sud"),
        Place(name: "Landmannalaugar", lat: 63.9910, lon: -19.0605, subtitle: "Highlands – solo strade F"),
        Place(name: "Skaftafell", lat: 64.0160, lon: -16.9660, subtitle: "Vatnajökull"),
        Place(name: "Jökulsárlón", lat: 64.0784, lon: -16.2306, subtitle: "Laguna glaciale"),
        Place(name: "Höfn", lat: 64.2539, lon: -15.2082, subtitle: "Sud-est"),
        Place(name: "Egilsstaðir", lat: 65.2653, lon: -14.3948, subtitle: "Est"),
        Place(name: "Seyðisfjörður", lat: 65.2597, lon: -14.0103, subtitle: "Fiordi orientali"),
        Place(name: "Dettifoss", lat: 65.8147, lon: -16.3846, subtitle: "Nord-est"),
        Place(name: "Mývatn (Reykjahlíð)", lat: 65.6436, lon: -16.9100, subtitle: "Nord"),
        Place(name: "Húsavík", lat: 66.0449, lon: -17.3389, subtitle: "Nord – whale watching"),
        Place(name: "Akureyri", lat: 65.6885, lon: -18.1262, subtitle: "Nord"),
        Place(name: "Siglufjörður", lat: 66.1522, lon: -18.9100, subtitle: "Penisola di Tröllaskagi"),
        Place(name: "Ísafjörður", lat: 66.0750, lon: -23.1350, subtitle: "Fiordi occidentali"),
        Place(name: "Kirkjufell / Grundarfjörður", lat: 64.9419, lon: -23.3067, subtitle: "Snæfellsnes"),
        Place(name: "Arnarstapi", lat: 64.7680, lon: -23.6250, subtitle: "Snæfellsnes"),
        Place(name: "Borgarnes", lat: 64.5383, lon: -21.9206, subtitle: "Ovest"),
    ]
}
