import Foundation

/// Text that comes from the web (IMO warnings, SafeTravel, Vegagerðin road news,
/// Herjólfur notices, NOAA alerts) in the app's language. nordur-api translates
/// it (an LLM briefed on Icelandic weather, roads and space weather, results
/// cached for everyone); translations are also kept on the phone, so a text is
/// translated once and works offline afterwards. When the service is not
/// reachable the original text is shown.
@MainActor
final class Translator {
    static let shared = Translator()

    static let endpoint = URL(string: "https://nordur-api.vercel.app/api/translate")!

    /// "it" or "en": the language the interface is running in.
    var language: String { Bundle.main.preferredLocalizations.first == "en" ? "en" : "it" }

    private var cache: [String: String] = [:]
    private var dirty = false
    private let file: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("translations.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: file), let stored = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = stored
        }
    }

    private func key(_ text: String) -> String { "\(language)|\(text)" }

    /// The cached translation, if any.
    func cached(_ text: String) -> String? { cache[key(text)] }

    /// Translations for `texts` (original → translated). Texts that fail keep no entry.
    func translate(_ texts: [String]) async -> [String: String] {
        let wanted = Array(Set(texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { Self.worthTranslating($0) }))
        var result: [String: String] = [:]
        var missing: [String] = []
        for text in wanted {
            if let hit = cache[key(text)] { result[text] = hit } else { missing.append(text) }
        }
        var index = 0
        while index < missing.count {
            // Batches of at most 25 texts / ~12k characters.
            var batch: [String] = [], size = 0
            while index < missing.count, batch.count < 25, size + missing[index].count <= 12_000 || batch.isEmpty {
                batch.append(missing[index]); size += missing[index].count; index += 1
            }
            guard let translated = await request(batch) else { break }
            for (original, text) in zip(batch, translated) where !text.isEmpty {
                cache[key(original)] = text
                // Text already in the app language (e.g. an alert quoting a translated warning) is not sent again.
                cache[key(text)] = text
                result[original] = text
            }
            dirty = true
        }
        if dirty { persist() }
        // Map back the untrimmed originals.
        var mapped: [String: String] = [:]
        for text in texts {
            if let t = result[text.trimmingCharacters(in: .whitespacesAndNewlines)] { mapped[text] = t }
        }
        return mapped
    }

    func translate(_ text: String) async -> String {
        await translate([text])[text] ?? text
    }

    /// Strings with letters only (not numbers, codes or road numbers).
    private static func worthTranslating(_ text: String) -> Bool {
        text.count >= 3 && text.rangeOfCharacter(from: .letters) != nil
            && text.filter(\.isLetter).count >= 3
    }

    private struct Request: Encodable { let to: String; let texts: [String] }
    private struct Response: Decodable { let translations: [String] }

    private func request(_ texts: [String]) async -> [String]? {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(Request(to: language, texts: texts))
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data),
              decoded.translations.count == texts.count else { return nil }
        return decoded.translations
    }

    private func persist() {
        dirty = false
        // Keep the cache bounded.
        if cache.count > 4000 { cache = Dictionary(uniqueKeysWithValues: cache.shuffled().prefix(3000).map { ($0.key, $0.value) }) }
        if let data = try? JSONEncoder().encode(cache) { try? data.write(to: file, options: .atomic) }
    }
}

// MARK: - Web data in the app language

extension Translator {
    func localize(_ warnings: [WeatherWarning]) async -> [WeatherWarning] {
        let map = await translate(warnings.flatMap { [$0.headline, $0.event, $0.details] })
        return warnings.map { w in
            var w = w
            w.headline = map[w.headline] ?? w.headline
            w.event = map[w.event] ?? w.event
            w.details = map[w.details] ?? w.details
            return w
        }
    }

    func localize(_ news: [NewsItem]) async -> [NewsItem] {
        let map = await translate(news.flatMap { [$0.title, $0.summary] })
        return news.map { n in
            var n = n
            n.title = map[n.title] ?? n.title
            n.summary = map[n.summary] ?? n.summary
            return n
        }
    }

    func localize(_ info: RoadInfo) async -> RoadInfo {
        var texts = info.news.map(\.text) + info.codes.compactMap(\.text) + info.codes.compactMap(\.title)
        for s in info.sections {
            texts += s.hazards.compactMap(\.text) + s.hazards.compactMap(\.title) + s.notes.compactMap(\.text)
            texts += [s.weight?.text, s.toll?.text].compactMap { $0 }
        }
        let map = await translate(texts)
        guard !map.isEmpty else { return info }
        func t(_ s: String?) -> String? { s.map { map[$0] ?? $0 } }
        var out = info
        out.news = info.news.map { var n = $0; n.text = map[n.text] ?? n.text; return n }
        out.codes = info.codes.map { var c = $0; c.text = t(c.text); c.title = t(c.title); return c }
        out.sections = info.sections.map { s in
            var s = s
            s.hazards = s.hazards.map { var h = $0; h.text = t(h.text); h.title = t(h.title); return h }
            s.notes = s.notes.map { var n = $0; n.text = t(n.text); return n }
            s.weight?.text = t(s.weight?.text)
            s.toll?.text = t(s.toll?.text)
            return s
        }
        return out
    }

    func localize(_ ferry: FerryNotice) async -> FerryNotice {
        var ferry = ferry
        ferry.text = await translate(ferry.text)
        return ferry
    }

    func localize(_ state: AuroraState) async -> AuroraState {
        guard let alerts = state.alerts, !alerts.isEmpty else { return state }
        let map = await translate(alerts.map(\.headline))
        var state = state
        state.alerts = alerts.map { var a = $0; a.headline = map[a.headline] ?? a.headline; return a }
        return state
    }

    /// An alert's title and body in the app language (they may quote web text).
    func localize(_ event: AlertEvent) async -> AlertEvent {
        let map = await translate([event.title, event.body])
        return AlertEvent(id: event.id, date: event.date, category: event.category, severity: event.severity,
                          title: map[event.title] ?? event.title, body: map[event.body] ?? event.body,
                          coordinate: event.coordinate, read: event.read, expires: event.expires)
    }
}
