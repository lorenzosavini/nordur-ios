import Foundation

/// Reads the track (or route) of a GPX file: Garmin Connect, Strava, Komoot,
/// Wikiloc and most GPS apps export this format.
final class GPXReader: NSObject, XMLParserDelegate {
    /// The track's (or route's) name, else the file's.
    var name: String? { trackName ?? fileName }
    private var trackName: String?, fileName: String?
    private(set) var points: [TrackPoint] = []

    private var lat: Double?, lon: Double?, ele: Double?, time: Date?, speed: Double?
    private var inPoint = false
    private var stack: [String] = []
    private var text = ""

    /// Track name and points; nil when the file is not a GPX with at least two points.
    static func read(_ data: Data) -> (name: String?, points: [TrackPoint])? {
        let reader = GPXReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() || reader.points.count >= 2, reader.points.count >= 2 else { return nil }
        // Routes (planned, no times): one point every 10 s so the statistics work.
        if reader.points.allSatisfy({ $0.t == .distantPast }) {
            let start = Date()
            reader.points = reader.points.enumerated().map { i, p in
                TrackPoint(t: start.addingTimeInterval(Double(i) * 10), lat: p.lat, lon: p.lon, alt: p.alt, speed: -1, course: nil, accuracy: 5)
            }
        }
        return (reader.name, reader.points)
    }

    private static func local(_ name: String) -> String { name.split(separator: ":").last.map(String.init) ?? name }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        let element = Self.local(elementName)
        stack.append(element)
        text = ""
        if element == "trkpt" || element == "rtept" {
            inPoint = true
            lat = attributes["lat"].flatMap(Double.init)
            lon = attributes["lon"].flatMap(Double.init)
            ele = nil; time = nil; speed = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let element = Self.local(elementName)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        stack.removeLast()
        switch element {
        case "ele" where inPoint: ele = Double(value)
        case "time" where inPoint: time = Self.iso.date(from: value) ?? Self.isoPlain.date(from: value)
        case "speed" where inPoint: speed = Double(value)
        case "name" where !inPoint && !value.isEmpty && (stack.last == "trk" || stack.last == "rte"):
            if trackName == nil { trackName = value }
        case "name" where !value.isEmpty && stack.last == "metadata":
            fileName = value
        case "trkpt", "rtept":
            if let lat, let lon, abs(lat) <= 90, abs(lon) <= 180 {
                points.append(TrackPoint(t: time ?? .distantPast, lat: lat, lon: lon, alt: ele, speed: speed ?? -1, course: nil, accuracy: 5))
            }
            inPoint = false
        default: break
        }
        text = ""
    }
}
