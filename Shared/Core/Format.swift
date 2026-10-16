import Foundation

enum Fmt {
    static let italian = Locale(identifier: "it_IT")

    static func temp(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int(value.rounded()))°"
    }

    static func ms(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int(value.rounded())) m/s"
    }

    static func number(_ value: Double?, decimals: Int = 0, unit: String = "") -> String {
        guard let value else { return "–" }
        let text = String(format: "%.\(decimals)f", value)
        return unit.isEmpty ? text : "\(text) \(unit)"
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int(value.rounded()))%"
    }

    static func compass(_ degrees: Double?) -> String {
        guard let degrees else { return "" }
        let names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                     "S", "SSO", "SO", "OSO", "O", "ONO", "NO", "NNO"]
        let index = Int((degrees.truncatingRemainder(dividingBy: 360) / 22.5).rounded()) % 16
        return names[(index + 16) % 16]
    }

    static func time(_ date: Date?, in zone: TimeZone = .current) -> String {
        guard let date else { return "–" }
        let formatter = DateFormatter()
        formatter.locale = italian
        formatter.timeZone = zone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func day(_ date: Date, in zone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = italian
        formatter.timeZone = zone
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }

    static func dayTime(_ date: Date?, in zone: TimeZone = .current) -> String {
        guard let date else { return "–" }
        let formatter = DateFormatter()
        formatter.locale = italian
        formatter.timeZone = zone
        formatter.dateFormat = "EEE d MMM, HH:mm"
        return formatter.string(from: date)
    }

    static func relative(_ date: Date) -> String {
        if abs(date.timeIntervalSinceNow) < 60 { return "adesso" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = italian
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// "1:05:09" or "5:09".
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func duration(_ seconds: Double?) -> String {
        guard let seconds else { return "–" }
        let minutes = Int(seconds / 60)
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}

/// WMO weather interpretation codes used by Open-Meteo.
enum WeatherCode {
    static func describe(_ code: Int?, isDay: Bool = true) -> (text: String, symbol: String) {
        switch code ?? -1 {
        case 0: return ("Sereno", isDay ? "sun.max.fill" : "moon.stars.fill")
        case 1: return ("Poco nuvoloso", isDay ? "sun.min.fill" : "moon.fill")
        case 2: return ("Parzialmente nuvoloso", isDay ? "cloud.sun.fill" : "cloud.moon.fill")
        case 3: return ("Coperto", "cloud.fill")
        case 45, 48: return ("Nebbia", "cloud.fog.fill")
        case 51, 53, 55: return ("Pioviggine", "cloud.drizzle.fill")
        case 56, 57: return ("Pioviggine gelata", "cloud.sleet.fill")
        case 61, 63: return ("Pioggia", "cloud.rain.fill")
        case 65: return ("Pioggia forte", "cloud.heavyrain.fill")
        case 66, 67: return ("Pioggia gelata", "cloud.sleet.fill")
        case 71, 73: return ("Neve", "cloud.snow.fill")
        case 75: return ("Neve forte", "snowflake")
        case 77: return ("Granuli di neve", "cloud.snow.fill")
        case 80, 81: return ("Rovesci", isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill")
        case 82: return ("Rovesci violenti", "cloud.heavyrain.fill")
        case 85, 86: return ("Rovesci di neve", "cloud.snow.fill")
        case 95: return ("Temporale", "cloud.bolt.fill")
        case 96, 99: return ("Temporale con grandine", "cloud.bolt.rain.fill")
        default: return ("—", "questionmark.circle")
        }
    }

    static func isThunderstorm(_ code: Int?) -> Bool {
        guard let code else { return false }
        return code >= 95
    }
}
