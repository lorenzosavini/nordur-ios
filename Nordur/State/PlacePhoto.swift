import Foundation
import UIKit
import Vision

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
        // v3: photos showing people's faces are left out; everything is looked up again.
        "place_photo3_\(stableHash(place.name))_\(Int(place.coordinate.lat * 20))_\(Int(place.coordinate.lon * 20))"
    }

    /// Wikidata / Wikipedia links of the places to see (from OpenStreetMap), by place.
    private var hints: [String: (wikidata: String?, wikipedia: String?)] = [:]

    func addHints(_ sights: [Attraction]) {
        for s in sights where s.wikidata != nil || s.wikipedia != nil {
            hints[key(s.place)] = (s.wikidata, s.wikipedia)
        }
    }

    func photo(for place: Place) async -> PlacePhoto? {
        let key = key(place)
        if let cached = memory[key] { return cached }
        if let stored = DiskCache.read(key), let photo = try? JSONDecoder().decode(PlacePhoto?.self, from: stored.data),
           // Found: kept 30 days. Not found: asked again after 3 days.
           Date().timeIntervalSince(stored.date) < (photo == nil ? 3 : 30) * 24 * 3600 {
            memory[key] = photo
            return photo
        }
        // Three places at a time: Wikimedia answers "too many requests" to bursts
        // (a list of attractions asks for many photos at once).
        while running >= 3 { await withCheckedContinuation { waiting.append($0) } }
        if let cached = memory[key] { return cached }
        running += 1
        let failuresBefore = failures
        let found = await lookup(place, hint: hints[key])
        running -= 1
        if !waiting.isEmpty { waiting.removeFirst().resume() }
        memory[key] = found
        // "No photo" is saved only when every request was answered; after a refusal or
        // a network error the place is looked up again next time.
        if found != nil || failures == failuresBefore, let data = try? JSONEncoder().encode(found) { DiskCache.write(data, key: key) }
        return found
    }

    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var failures = 0

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

    /// The best free photo of a place. First round, all at once (the first in this
    /// order that has one wins): the Wikidata image (P18), the OSM-linked article,
    /// the article with the place's name (it/en/is), photos taken on the spot
    /// (Commons, 1 km). Then: a search, the nearest article with a photo, Commons 5 km.
    private func lookup(_ place: Place, hint: (wikidata: String?, wikipedia: String?)?) async -> PlacePhoto? {
        let name = Self.searchName(place.name)
        let preferred = Bundle.main.preferredLocalizations.first == "en" ? ["en", "it"] : ["it", "en"]
        var first: [@MainActor () async -> PlacePhoto?] = []
        if let q = hint?.wikidata { first.append { await self.wikidataImage(q) } }
        if let link = hint?.wikipedia, let colon = link.firstIndex(of: ":") {
            let lang = String(link[..<colon]), title = String(link[link.index(after: colon)...])
            first.append { await self.article(lang, title) }
        }
        for lang in preferred + ["is"] { first.append { await self.article(lang, name) } }
        let c = place.coordinate
        first.append { await self.commonsNear(c, radius: 1000) }
        if let photo = await firstInOrder(first) { return photo }

        let coord = "\(c.lat)|\(c.lon)"
        let second: [@MainActor () async -> PlacePhoto?] = [
            { await self.searched("en", "\(name) Iceland") },
            { await self.nearestArticle("en", coord) },
            { await self.nearestArticle("is", coord) },
            { await self.commonsNear(c, radius: 5000) },
        ]
        return await firstInOrder(second)
    }

    /// Runs every lookup at once and returns the first result in list order.
    private func firstInOrder(_ lookups: [@MainActor () async -> PlacePhoto?]) async -> PlacePhoto? {
        await withTaskGroup(of: (Int, PlacePhoto?).self) { group in
            for (i, lookup) in lookups.enumerated() { group.addTask { (i, await lookup()) } }
            var results: [Int: PlacePhoto?] = [:]
            var next = 0
            for await (i, photo) in group {
                results[i] = photo
                while let result = results[next] {
                    if let result { group.cancelAll(); return result }
                    next += 1
                }
            }
            return nil
        }
    }

    private func article(_ lang: String, _ title: String) async -> PlacePhoto? {
        guard let page = await pages(lang, ["titles": title, "redirects": "1"]).first else { return nil }
        return await placeOnly(await make(page, lang: lang))
    }

    private func searched(_ lang: String, _ query: String) async -> PlacePhoto? {
        for page in await pages(lang, ["generator": "search", "gsrsearch": query, "gsrlimit": "3"]) {
            if let photo = await placeOnly(await make(page, lang: lang)) { return photo }
        }
        return nil
    }

    private func nearestArticle(_ lang: String, _ coord: String) async -> PlacePhoto? {
        let near = await pages(lang, ["generator": "geosearch", "ggscoord": coord, "ggsradius": "10000", "ggslimit": "12"])
            .sorted { ($0.index ?? 99) < ($1.index ?? 99) }
        for page in near.prefix(6) {
            if let photo = await placeOnly(await make(page, lang: lang)) { return photo }
        }
        return nil
    }

    // MARK: No people

    /// The photo, unless it shows people's faces: a place is shown, not who was
    /// there. Checked on the phone with Vision; file names of portraits are left
    /// out without downloading. Small figures far away are fine.
    private func placeOnly(_ photo: PlacePhoto?) async -> PlacePhoto? {
        guard let photo else { return nil }
        if Self.aboutPeople(photo.title) { return nil }
        var request = URLRequest(url: photo.imageURL, timeoutInterval: 15)
        request.setValue(Self.agent, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await HTTP.session.data(for: request), let image = UIImage(data: data), let cg = image.cgImage else {
            return photo
        }
        let faces = await Task.detached(priority: .utility) { () -> Bool in
            let detect = VNDetectFaceRectanglesRequest()
            try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([detect])
            // A face bigger than ~0.15 % of the picture (about 40 × 40 px on 1200 × 800).
            return (detect.results ?? []).contains { $0.boundingBox.width * $0.boundingBox.height > 0.0015 }
        }.value
        if faces { return nil }
        // Already downloaded: the views show it without fetching it again.
        RemoteImageCache.shared.store(image, photo.imageURL)
        return photo
    }

    private static func aboutPeople(_ title: String) -> Bool {
        let lower = title.lowercased()
        return ["portrait", "selfie", "people", "tourist", "turist", "family", "famiglia", "wedding", "couple", "man ", "woman", "girl", "boy ",
                "children", "kids", "crowd", "visitors", "persone", "ritratto", "fólk", "mynd af"].contains(where: lower.contains)
    }

    /// "Hotel Boli Keflavík" → "Hotel Boli Keflavík"; "Svartifoss (Skaftafell)" → "Svartifoss".
    private static func searchName(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s*\(.*\)"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Wikidata and Commons

    private func wikidataImage(_ q: String) async -> PlacePhoto? {
        struct Claims: Decodable {
            struct Claim: Decodable { struct Snak: Decodable { struct Value: Decodable { let value: String? }; let datavalue: Value? }; let mainsnak: Snak }
            let claims: [String: [Claim]]?
        }
        guard let url = try? HTTP.url("https://www.wikidata.org/w/api.php", ["action": "wbgetclaims", "entity": q, "property": "P18", "format": "json"]),
              let data = await get(url),
              let file = (try? JSONDecoder().decode(Claims.self, from: data))?.claims?["P18"]?.first?.mainsnak.datavalue?.value else { return nil }
        return await placeOnly(await commonsFile("File:" + file))
    }

    private struct CommonsFiles: Decodable {
        struct Query: Decodable { let pages: [String: Page]? }
        struct Page: Decodable { let title: String; let index: Int?; let imageinfo: [Info]? }
        struct Info: Decodable {
            let thumburl: String?
            let descriptionurl: String?
            let mime: String?
            let extmetadata: [String: Meta]?
        }
        struct Meta: Decodable { let value: String? }
        let query: Query?
    }

    private func commonsFile(_ title: String) async -> PlacePhoto? {
        await commons(["titles": title]).first
    }

    /// Photos taken around a point (Commons geotags), nearest first.
    private func commonsNear(_ c: Coordinate, radius: Int) async -> PlacePhoto? {
        let found = await commons(["generator": "geosearch", "ggscoord": "\(c.lat)|\(c.lon)", "ggsradius": "\(radius)",
                                   "ggsnamespace": "6", "ggslimit": "15"])
        for photo in found.prefix(6) {
            if let clean = await placeOnly(photo) { return clean }
        }
        return nil
    }

    private func commons(_ params: [String: String]) async -> [PlacePhoto] {
        var query = params
        query["action"] = "query"
        query["format"] = "json"
        query["prop"] = "imageinfo"
        query["iiprop"] = "url|mime|extmetadata"
        query["iiurlwidth"] = "1200"
        guard let url = try? HTTP.url("https://commons.wikimedia.org/w/api.php", query), let data = await get(url),
              let pages = (try? JSONDecoder().decode(CommonsFiles.self, from: data))?.query?.pages?.values else { return [] }
        return pages.sorted { ($0.index ?? 99) < ($1.index ?? 99) }.compactMap { page in
            guard let info = page.imageinfo?.first, info.mime == "image/jpeg", let thumb = info.thumburl.flatMap(URL.init(string:)),
                  !Self.notAView(page.title) else { return nil }
            let license = info.extmetadata?["LicenseShortName"]?.value
            // Free licences only.
            guard let l = license?.lowercased(), l.contains("cc") || l.contains("public domain") || l.contains("pd") else { return nil }
            let author = info.extmetadata?["Artist"]?.value.map(Self.plain).flatMap { $0.isEmpty ? nil : String($0.prefix(40)) }
            return PlacePhoto(imageURL: thumb, title: page.title, author: author, license: license,
                              page: info.descriptionurl.flatMap(URL.init(string:)))
        }
    }

    /// Maps, flags, coats of arms, logos and diagrams are not a view of the place.
    private static func notAView(_ file: String) -> Bool {
        let lower = file.lowercased()
        return [".svg", "map", "kort", "flag", "coat_of_arms", "coat of arms", "skjaldarmerki", "location", "logo", "diagram"].contains(where: lower.contains)
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

    private func make(_ page: PagesResponse.Page, lang: String = "en") async -> PlacePhoto? {
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

    // MARK: Description

    private var summaries: [String: String?] = [:]

    /// The opening lines of the place's Wikipedia article (the one its photo comes
    /// from), in the article's language. Kept on the phone 30 days.
    func summary(for place: Place) async -> String? {
        let key = "place_summary_" + self.key(place)
        if let cached = summaries[key] { return cached }
        if let stored = DiskCache.read(key), Date().timeIntervalSince(stored.date) < 30 * 24 * 3600 {
            let text = String(data: stored.data, encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 }
            summaries[key] = text
            return text
        }
        // Only articles have a text (a Commons photo has none).
        guard let photo = await photo(for: place), let host = photo.page?.host, host.hasSuffix("wikipedia.org") else { return nil }
        struct Summary: Decodable { let extract: String? }
        let title = photo.title.replacingOccurrences(of: " ", with: "_")
        var text: String?
        if let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "https://\(host)/api/rest_v1/page/summary/\(encoded)"),
           let data = await get(url), let extract = (try? JSONDecoder().decode(Summary.self, from: data))?.extract, !extract.isEmpty {
            // At most four sentences.
            let sentences = extract.components(separatedBy: ". ")
            text = sentences.prefix(4).joined(separator: ". ") + (sentences.count > 4 && !sentences[3].hasSuffix(".") ? "." : "")
        }
        summaries[key] = text
        DiskCache.write(Data((text ?? "").utf8), key: key)
        return text
    }

    private func get(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(Self.agent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await HTTP.session.data(for: request) else { failures += 1; return nil }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 429 || status >= 500 { failures += 1 }
        return status == 200 ? data : nil
    }
}
