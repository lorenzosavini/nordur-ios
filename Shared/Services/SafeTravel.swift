import Foundation

// SafeTravel.is — run by ICE-SAR (Icelandic search and rescue). Its alerts
// cover eruptions, closures, storms, highland conditions and emergency notices.

struct NewsItem: Identifiable {
    let id: Int
    var title: String
    var summary: String
    let link: URL?
    let date: Date?
    /// SafeTravel's own label colour ("red", "yellow", …), if any.
    let label: String?

    var risk: Risk {
        switch label?.lowercased() {
        case "red": return .danger
        case "orange": return .warning
        case "yellow": return .caution
        default: return .ok
        }
    }
}

private struct WPAlert: Decodable {
    let id: Int
    let date_gmt: String?
    let link: String?
    let title: Rendered?
    let content: Rendered?
    let label: String?

    struct Rendered: Decodable { let rendered: String? }

    private enum CodingKeys: String, CodingKey { case id, date_gmt, link, title, content, acf }
    private struct ACF: Decodable {
        let label: String?
        enum CodingKeys: String, CodingKey { case label = "alert-label" }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        date_gmt = try? c.decodeIfPresent(String.self, forKey: .date_gmt)
        link = try? c.decodeIfPresent(String.self, forKey: .link)
        title = try? c.decodeIfPresent(Rendered.self, forKey: .title)
        content = try? c.decodeIfPresent(Rendered.self, forKey: .content)
        // WordPress returns `[]` instead of an object when no custom fields are set.
        label = (try? c.decodeIfPresent(ACF.self, forKey: .acf))?.label
    }
}

enum SafeTravel {
    static func news() async throws -> Fetched<[NewsItem]> {
        let url = try HTTP.url("https://safetravel.is/wp-json/wp/v2/alert", ["per_page": "20"])
        let fetched = try await HTTP.json([WPAlert].self, from: url, cacheKey: "safetravel_alerts")
        return fetched.map { alerts in
            alerts.map { alert in
                NewsItem(
                    id: alert.id,
                    title: HTMLText.plain(alert.title?.rendered ?? ""),
                    summary: HTMLText.plain(alert.content?.rendered ?? ""),
                    link: alert.link.flatMap(URL.init(string:)),
                    date: DateParse.iso(alert.date_gmt),
                    label: alert.label
                )
            }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        }
    }
}

enum HTMLText {
    static func plain(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities: [(String, String)] = [
            ("[&hellip;]", "…"), ("&hellip;", "…"), ("&#8230;", "…"), ("&quot;", "\""), ("&#039;", "'"),
            ("&#8217;", "’"), ("&#8216;", "‘"), ("&#8220;", "“"), ("&#8221;", "”"), ("&#8211;", "–"),
            ("&#8212;", "—"), ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&"),
        ]
        for (key, value) in entities { text = text.replacingOccurrences(of: key, with: value) }
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
