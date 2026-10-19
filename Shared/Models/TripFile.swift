import Foundation

/// Places read from a trip planned elsewhere: GPX waypoints and route points
/// (gpx.studio, Komoot, Garmin BaseCamp, our own export) or KML placemarks
/// (Google My Maps, Google Earth). Each is a stop (where you sleep) or an
/// attraction; the file's own hints decide the first guess.
struct TripFileItem: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var lat: Double
    var lon: Double
    var date: Date?
    var notes: String?
    var isStop: Bool
    var nights: Int?
}

final class TripFileReader: NSObject, XMLParserDelegate {
    private var items: [TripFileItem] = []
    private var stack: [String] = []
    private var folders: [String] = []
    private var text = ""
    private var inItem = false
    private var isRoutePoint = false
    private var name: String?, desc: String?, type: String?, sym: String?, time: Date?, nights: Int?
    private var lat: Double?, lon: Double?
    private var sawRoute = false

    /// Words that mark the place where you sleep (in the type, symbol, folder or description).
    private static let stopWords = #"(?i)\b(tapp[ae]|stop|stops|hotel|lodging|lodge|camp\w*|nott[ei]|night\w*|sleep|accommodation|alloggi\w*|pernott\w*|guest ?house|hostel|b&b|bed|cottage|cabin)\b"#
    private static let attractionWords = #"(?i)\b(attrazion\w*|attraction\w*|sight\w*|poi|da vedere|visit\w*|scenic|waterfall|cascat\w*)\b"#

    static func read(_ data: Data) -> [TripFileItem]? {
        let reader = TripFileReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        _ = parser.parse()
        var items = reader.items
        guard !items.isEmpty else { return nil }
        // Nothing marked as a stop: a short list is the stops, a long one is the sights between the first and the last.
        if !items.contains(where: \.isStop) {
            if items.count <= 10 {
                for i in items.indices { items[i].isStop = true }
            } else {
                items[0].isStop = true
                items[items.count - 1].isStop = true
            }
        }
        return items
    }

    private static func local(_ name: String) -> String { name.split(separator: ":").last.map(String.init) ?? name }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()
    private static let dayOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .iceland
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func date(_ s: String) -> Date? { iso.date(from: s) ?? isoPlain.date(from: s) ?? dayOnly.date(from: String(s.prefix(10))) }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        let element = Self.local(elementName)
        stack.append(element)
        text = ""
        switch element {
        case "wpt", "rtept":
            inItem = true
            isRoutePoint = element == "rtept"
            if isRoutePoint { sawRoute = true }
            lat = attributes["lat"].flatMap(Double.init)
            lon = attributes["lon"].flatMap(Double.init)
            name = nil; desc = nil; type = nil; sym = nil; time = nil; nights = nil
        case "Placemark":
            inItem = true
            isRoutePoint = false
            lat = nil; lon = nil
            name = nil; desc = nil; type = nil; sym = nil; time = nil; nights = nil
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { text += String(decoding: CDATABlock, as: UTF8.self) }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let element = Self.local(elementName)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        stack.removeLast()
        let parent = stack.last
        if !inItem {
            // KML folder (a My Maps layer) names: "Tappe", "Hotel", "Attrazioni"…
            if element == "name", parent == "Folder" || parent == "Document" { folders.append(value) }
            if element == "Folder", !folders.isEmpty { folders.removeLast() }
            text = ""
            return
        }
        switch element {
        case "name": if name == nil { name = value }
        case "desc", "description", "cmt": desc = [desc, Self.plain(value)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        case "type": type = value
        case "sym": sym = value
        case "time", "when": time = Self.date(value)
        case "nights": nights = Int(value)
        case "coordinates":
            // KML: "lon,lat[,alt]"; a line or polygon gives its first point.
            let first = value.split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map { $0.split(separator: ",") } ?? []
            if first.count >= 2 { lon = Double(first[0]); lat = Double(first[1]) }
        case "wpt", "rtept", "Placemark":
            inItem = false
            guard let lat, let lon, (-90...90).contains(lat), (-180...180).contains(lon) else { break }
            let hints = [type, sym, folders.last, desc].compactMap { $0 }.joined(separator: " ")
            let attraction = hints.range(of: Self.attractionWords, options: .regularExpression) != nil
            let stop = !attraction && (hints.range(of: Self.stopWords, options: .regularExpression) != nil || (isRoutePoint && type == nil))
            let label = name.flatMap { $0.isEmpty ? nil : $0 } ?? String(format: "%.3f, %.3f", lat, lon)
            // A route point at the same place as a waypoint is the same place.
            if isRoutePoint, let i = items.firstIndex(where: { abs($0.lat - lat) < 0.0005 && abs($0.lon - lon) < 0.0005 }) {
                if !attraction { items[i].isStop = true }
                break
            }
            items.append(TripFileItem(name: label, lat: lat, lon: lon, date: time, notes: desc.flatMap { $0.isEmpty ? nil : $0 },
                                      isStop: stop, nights: nights ?? Self.nights(in: desc)))
        default: break
        }
        text = ""
    }

    /// "2 notti", "3 nights" in a description.
    private static func nights(in text: String?) -> Int? {
        guard let text, let r = text.range(of: #"(?i)(\d{1,2})\s*(notti|notte|nights?)"#, options: .regularExpression) else { return nil }
        return Int(text[r].prefix { $0.isNumber })
    }

    private static func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<br>", with: " ").replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
