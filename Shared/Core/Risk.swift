import SwiftUI

/// Common four-level scale used by every screen to colour hazards.
enum Risk: Int, Comparable, CaseIterable {
    case ok, caution, warning, danger

    static func < (lhs: Risk, rhs: Risk) -> Bool { lhs.rawValue < rhs.rawValue }

    var color: Color {
        switch self {
        case .ok: return .green
        case .caution: return .yellow
        case .warning: return .orange
        case .danger: return .red
        }
    }

    var label: String {
        switch self {
        case .ok: return "Tranquillo"
        case .caution: return "Attenzione"
        case .warning: return "Rischioso"
        case .danger: return "Pericoloso"
        }
    }

    var symbol: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "xmark.octagon.fill"
        }
    }

    /// Thresholds follow the usual Icelandic guidance (m/s): sustained wind above
    /// 15 is hard for cars, above 20 travel is discouraged; gusts near mountains
    /// can be far stronger than the mean wind.
    static func wind(mean: Double?, gust: Double?) -> Risk {
        var risk = Risk.ok
        if let mean {
            if mean >= 20 { risk = max(risk, .danger) }
            else if mean >= 15 { risk = max(risk, .warning) }
            else if mean >= 10 { risk = max(risk, .caution) }
        }
        if let gust {
            if gust >= 30 { risk = max(risk, .danger) }
            else if gust >= 25 { risk = max(risk, .warning) }
            else if gust >= 18 { risk = max(risk, .caution) }
        }
        return risk
    }

    static func windAdvice(_ risk: Risk) -> String {
        switch risk {
        case .ok: return "Vento gestibile."
        case .caution: return "Vento sostenuto: tieni salde le portiere dell'auto aprendole."
        case .warning: return "Guida impegnativa, raffiche forti vicino alle montagne. Evita camper e auto alte."
        case .danger: return "Sconsigliato mettersi in viaggio. Controlla umferdin.is e safetravel.is."
        }
    }

    /// Ice/snow hazard from temperature and precipitation.
    static func ice(temperature: Double?, precipitation: Double?, snowfall: Double?) -> Risk {
        guard let temperature else { return .ok }
        let snow = snowfall ?? 0
        let precip = precipitation ?? 0
        if snow >= 2 { return .warning }
        if temperature <= 1 && precip > 0.2 { return .warning }
        if snow > 0 { return .caution }
        if temperature <= 2 { return .caution }
        return .ok
    }
}
