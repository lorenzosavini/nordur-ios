import Foundation

/// The language the interface is running in: one of the app's localizations.
enum UILanguage {
    static let supported = ["it", "en", "de", "fr", "es"]
    static let code: String = {
        let first = Bundle.main.preferredLocalizations.first ?? "it"
        return supported.contains(first) ? first : "it"
    }()
    /// Region form for dates, numbers and the voice.
    static var region: String { ["it": "it_IT", "en": "en_GB", "de": "de_DE", "fr": "fr_FR", "es": "es_ES"][code] ?? "it_IT" }
}

enum Fmt {
    /// Locale for dates and numbers in the app language.
    static let italian = Locale(identifier: UILanguage.region)

    /// Temperature with the degree sign, in the unit chosen in Settings (values are °C inside the app).
    static func temp(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int(TempUnit.current.value(value).rounded()))°"
    }

    /// Temperature number only, in the chosen unit.
    static func degrees(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int(TempUnit.current.value(value).rounded()))"
    }

    /// "°C" or "°F".
    static var tempUnit: String { TempUnit.current.label }

    /// Wind speed with its unit, in the unit chosen in Settings (values are m/s inside the app).
    static func ms(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int((value * WindUnit.current.factor).rounded())) \(WindUnit.current.label)"
    }

    /// Wind speed number only, in the chosen unit.
    static func wind(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int((value * WindUnit.current.factor).rounded()))"
    }

    static var windUnit: String { WindUnit.current.label }

    static func number(_ value: Double?, decimals: Int = 0, unit: String = "") -> String {
        guard let value else { return "–" }
        let text = String(format: "%.\(decimals)f", value)
        return unit.isEmpty ? text : "\(text) \(unit)"
    }

    /// "63.42N 19.01W"
    static func coordinate(_ c: Coordinate) -> String {
        String(format: "%.2f%@ %.2f%@", abs(c.lat), c.lat >= 0 ? "N" : "S", abs(c.lon), c.lon >= 0 ? "E" : "W")
    }

    /// Hour as two digits ("07").
    static func hour(_ date: Date, in zone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return String(format: "%02d", calendar.component(.hour, from: date))
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int(value.rounded()))%"
    }

    static func compass(_ degrees: Double?) -> String {
        guard let degrees else { return "" }
        let names = [String(localized: "N"), String(localized: "NNE"), String(localized: "NE"), String(localized: "ENE"), String(localized: "E"), String(localized: "ESE"), String(localized: "SE"), String(localized: "SSE"),
                     String(localized: "S"), String(localized: "SSO"), String(localized: "SO"), String(localized: "OSO"), String(localized: "O"), String(localized: "ONO"), String(localized: "NO"), String(localized: "NNO")]
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

    /// Chart axis label: "ven 13".
    static func axis(_ date: Date, hour: Bool = true) -> String {
        let formatter = DateFormatter()
        formatter.locale = italian
        formatter.timeZone = .current
        formatter.dateFormat = hour ? "EEE HH" : "EEE d"
        return formatter.string(from: date)
    }

    static func relative(_ date: Date) -> String {
        if abs(date.timeIntervalSinceNow) < 60 { return String(localized: "adesso") }
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
        case 0: return (String(localized: "Sereno"), isDay ? "sun.max.fill" : "moon.stars.fill")
        case 1: return (String(localized: "Poco nuvoloso"), isDay ? "sun.min.fill" : "moon.fill")
        case 2: return (String(localized: "Parzialmente nuvoloso"), isDay ? "cloud.sun.fill" : "cloud.moon.fill")
        case 3: return (String(localized: "Coperto"), "cloud.fill")
        case 45, 48: return (String(localized: "Nebbia"), "cloud.fog.fill")
        case 51, 53, 55: return (String(localized: "Pioviggine"), "cloud.drizzle.fill")
        case 56, 57: return (String(localized: "Pioviggine gelata"), "cloud.sleet.fill")
        case 61, 63: return (String(localized: "Pioggia"), "cloud.rain.fill")
        case 65: return (String(localized: "Pioggia forte"), "cloud.heavyrain.fill")
        case 66, 67: return (String(localized: "Pioggia gelata"), "cloud.sleet.fill")
        case 68: return (String(localized: "Nevischio"), "cloud.sleet.fill")
        case 83: return (String(localized: "Rovesci di nevischio"), "cloud.sleet.fill")
        case 71, 73: return (String(localized: "Neve"), "cloud.snow.fill")
        case 75: return (String(localized: "Neve forte"), "snowflake")
        case 77: return (String(localized: "Granuli di neve"), "cloud.snow.fill")
        case 80, 81: return (String(localized: "Rovesci"), isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill")
        case 82: return (String(localized: "Rovesci violenti"), "cloud.heavyrain.fill")
        case 85, 86: return (String(localized: "Rovesci di neve"), "cloud.snow.fill")
        case 95: return (String(localized: "Temporale"), "cloud.bolt.fill")
        case 96, 99: return (String(localized: "Temporale con grandine"), "cloud.bolt.rain.fill")
        default: return ("—", "questionmark.circle")
        }
    }

    static func isThunderstorm(_ code: Int?) -> Bool {
        guard let code else { return false }
        return code >= 95
    }
}

extension String {
    /// Translation of a label passed around as a plain String (runtime lookup in the string catalog; unchanged when missing).
    var loc: String { Bundle.main.localizedString(forKey: self, value: self, table: nil) }
}

/// Unit for wind speeds (Settings › Units). Data stay in m/s; only the display changes.
enum TempUnit: String, CaseIterable, Identifiable {
    case celsius, fahrenheit

    static let key = "units.temperature"
    static var current: TempUnit { TempUnit(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .celsius }

    var id: String { rawValue }
    var label: String { self == .celsius ? "°C" : "°F" }
    /// A temperature in °C in this unit.
    func value(_ celsius: Double) -> Double { self == .celsius ? celsius : celsius * 9 / 5 + 32 }
}

enum WindUnit: String, CaseIterable, Identifiable {
    case ms, kmh, knots

    static let key = "units.wind"
    static var current: WindUnit { WindUnit(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .ms }

    var id: String { rawValue }
    var factor: Double {
        switch self { case .ms: return 1; case .kmh: return 3.6; case .knots: return 1.943844 }
    }
    var label: String {
        switch self { case .ms: return "m/s"; case .kmh: return "km/h"; case .knots: return String(localized: "nodi") }
    }
}
