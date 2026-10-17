import Foundation
import UIKit

/// A photograph of the active place, for the blurred backdrop on Today.
///
/// Source: the lead image of the place's Wikipedia article (free licences
/// only, Wikipedia's `pilicense=free`), looked up by name and, failing that,
/// among geotagged articles within 10 km. Author and licence come from
/// Wikimedia Commons and are shown under the backdrop. Kept on the phone.
struct PlacePhoto: Codable, Equatable {
    let imageURL: URL
    let title: String
    let author: String?
    let license: String?
    let page: URL?

    var credit: String {
        [author.map { String(localized: "Foto: \($0)") }, license, "Wikimedia"].compactMap { $0 }.joined(separator: " · ")
    }
}

@MainActor
final class PlacePhotoService {
    static let shared = PlacePhotoService()

    private var memory: [String: PlacePhoto?] = [:]
    private static let agent = "Nordur/1.0 (iOS; https://github.com/lorenzosavini/nordur-ios)"

    private func key(_ place: Place) -> String {
        "place_photo_\(stableHash(place.name))_\(Int(place.coordinate.lat * 20))_\(Int(place.coordinate.lon * 20))"
    }

    func photo(for place: Place) async -> PlacePhoto? {
        let key = key(place)
        if let cached = memory[key] { return cached }
        if let stored = DiskCache.read(key), Date().timeIntervalSince(stored.date) < 30 * 24 * 3600,
           let photo = try? JSONDecoder().decode(PlacePhoto?.self, from: stored.data) {
            memory[key] = photo
            return photo
        }
        let found = await lookup(place)
        memory[key] = found
        if let data = try? JSONEncoder().encode(found) { DiskCache.write(data, key: key) }
        return found
    }

    // MARK: Wikipedia

    private struct PagesResponse: Decodable {
        struct Query: Decodable { let pages: [String: Page]? }
        struct Page: Decodable {
            let title: String
            let index: Int?
            let pageimage: String?
            let thumbnail: Thumb?
            let fullurl: String?
        }
        struct Thumb: Decodable { let source: String }
        let query: Query?
    }

    private func lookup(_ place: Place) async -> PlacePhoto? {
        let languages = Bundle.main.preferredLocalizations.first == "en" ? ["en", "it"] : ["it", "en"]
        // 1. The article with the place's own name.
        for lang in languages {
            if let page = await pages(lang, ["titles": place.name, "redirects": "1"]).first, let photo = await make(page) { return photo }
        }
        // 2. The nearest geotagged article with a free image.
        let coord = "\(place.coordinate.lat)|\(place.coordinate.lon)"
        for lang in ["en", "is"] {
            let near = await pages(lang, ["generator": "geosearch", "ggscoord": coord, "ggsradius": "10000", "ggslimit": "12"])
                .sorted { ($0.index ?? 99) < ($1.index ?? 99) }
            for page in near {
                if let photo = await make(page) { return photo }
            }
        }
        return nil
    }

    private func pages(_ lang: String, _ params: [String: String]) async -> [PagesResponse.Page] {
        var query = params
        query["action"] = "query"
        query["format"] = "json"
        query["prop"] = "pageimages|info"
        query["inprop"] = "url"
        query["piprop"] = "thumbnail|name"
        query["pithumbsize"] = "1200"
        query["pilicense"] = "free"
        guard let url = try? HTTP.url("https://\(lang).wikipedia.org/w/api.php", query),
              let data = await get(url),
              let decoded = try? JSONDecoder().decode(PagesResponse.self, from: data) else { return [] }
        return Array((decoded.query?.pages ?? [:]).values).filter { $0.thumbnail != nil && $0.pageimage != nil }
    }

    private struct CommonsResponse: Decodable {
        struct Query: Decodable { let pages: [String: Page]? }
        struct Page: Decodable { let imageinfo: [Info]? }
        struct Info: Decodable { let extmetadata: [String: Meta]? }
        struct Meta: Decodable { let value: String? }
        let query: Query?
    }

    private func make(_ page: PagesResponse.Page) async -> PlacePhoto? {
        guard let thumb = page.thumbnail?.source, let imageURL = URL(string: thumb), let file = page.pageimage else { return nil }
        // Skip maps, flags, coats of arms and diagrams (not a view of the place).
        let lower = file.lowercased()
        if [".svg", "map", "kort", "flag", "coat_of_arms", "skjaldarmerki", "location", "logo"].contains(where: lower.contains) { return nil }
        var author: String?, license: String?
        if let url = try? HTTP.url("https://commons.wikimedia.org/w/api.php",
                                   ["action": "query", "format": "json", "titles": "File:\(file)", "prop": "imageinfo", "iiprop": "extmetadata"]),
           let data = await get(url),
           let meta = (try? JSONDecoder().decode(CommonsResponse.self, from: data))?.query?.pages?.values.first?.imageinfo?.first?.extmetadata {
            author = meta["Artist"]?.value.map(Self.plain).flatMap { $0.isEmpty ? nil : String($0.prefix(40)) }
            license = meta["LicenseShortName"]?.value
        }
        return PlacePhoto(imageURL: imageURL, title: page.title, author: author, license: license, page: page.fullurl.flatMap(URL.init(string:)))
    }

    private static func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func get(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(Self.agent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await HTTP.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
