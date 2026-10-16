import Foundation

// Vegagerðin road webcams (~170 sites, ~500 cameras). Images refresh every few minutes.

struct WebcamImage: Identifiable, Hashable {
    let url: URL
    let caption: String
    var id: URL { url }
}

struct WebcamSite: Identifiable, Hashable {
    let id: Int
    let name: String
    let road: String
    let coordinate: Coordinate
    let images: [WebcamImage]

    static func == (lhs: WebcamSite, rhs: WebcamSite) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct RawWebcam: Decodable {
    let Maelist_nr: Double?
    let Myndavel: String?
    let Vegheiti: String?
    let NrVegur: String?
    let Skyring: String?
    let Slod: String?
    let Breidd: Double?
    let Lengd: Double?
}

enum Webcams {
    static func sites() async throws -> Fetched<[WebcamSite]> {
        guard let url = URL(string: "https://gagnaveita.vegagerdin.is/api/vefmyndavelar2014_1") else { throw HTTPError.invalidURL }
        let fetched = try await HTTP.json([RawWebcam].self, from: url, cacheKey: "webcams")
        return fetched.map(group)
    }

    fileprivate static func group(_ raw: [RawWebcam]) -> [WebcamSite] {
        var order: [Int] = []
        var byID: [Int: (name: String, road: String, coordinate: Coordinate, images: [WebcamImage])] = [:]
        for cam in raw {
            guard let number = cam.Maelist_nr, let lat = cam.Breidd, let lon = cam.Lengd, lat != 0,
                  let link = cam.Slod, let url = URL(string: link) else { continue }
            let id = Int(number)
            let image = WebcamImage(url: url, caption: cam.Skyring ?? cam.Myndavel ?? "")
            if byID[id] == nil {
                order.append(id)
                let road = [cam.NrVegur.map { String(localized: "Strada \($0)") }, cam.Vegheiti].compactMap { $0 }.joined(separator: " · ")
                byID[id] = (cam.Myndavel ?? String(localized: "Webcam \(id)"), road, Coordinate(lat: lat, lon: lon), [image])
            } else {
                byID[id]?.images.append(image)
            }
        }
        return order.compactMap { id in
            byID[id].map { WebcamSite(id: id, name: $0.name, road: $0.road, coordinate: $0.coordinate, images: $0.images) }
        }
    }

    static func nearest(_ sites: [WebcamSite], to point: Coordinate, within km: Double, limit: Int) -> [WebcamSite] {
        Array(sites
            .map { ($0, Geo.distanceKm($0.coordinate, point)) }
            .filter { $0.1 <= km }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0))
    }

    /// Image URL with a cache-busting query so a refresh shows the latest frame.
    static func fresh(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970 / 60)))]
        return components.url ?? url
    }
}
