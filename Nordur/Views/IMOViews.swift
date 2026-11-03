import SwiftUI

/// "Now, measured": the latest observation of the nearest IMO station — wind,
/// the gust really measured in the last hour, temperature, and when.
struct IMOObservationBlock: View {
    let observation: IMOObservation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(Theme.aurora).frame(width: 6, height: 6)
                Text(String(localized: "ADESSO, MISURATO · \(observation.station.uppercased())"))
                    .font(.mono(9.5, .semibold)).foregroundStyle(Theme.dim).lineLimit(1)
                Spacer(minLength: 4)
                Text(Fmt.time(observation.time, in: .iceland)).font(.mono(9.5)).foregroundStyle(Theme.faint)
            }
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                if let t = observation.temperature {
                    reading(Fmt.temp(t), String(localized: "aria"), Theme.text)
                }
                if let w = observation.wind {
                    reading("\(Fmt.wind(w)) \(Fmt.windUnit)",
                            observation.direction.isEmpty ? String(localized: "vento") : String(localized: "vento da \(observation.direction)"),
                            Theme.text)
                }
                if let g = observation.gust {
                    reading("\(Fmt.wind(g)) \(Fmt.windUnit)", String(localized: "raffica misurata"), g >= 20 ? Theme.warning : g >= 15 ? Theme.caution : Theme.text)
                }
            }
            Text(String(localized: "Veðurstofa Íslands · stazione a \(Int(observation.distanceKm.rounded())) km, misura delle \(Fmt.time(observation.time, in: .iceland))"))
                .font(.app(.caption2)).foregroundStyle(Theme.faint)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func reading(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.metric(20, .semibold)).foregroundStyle(color).monospacedDigit()
            Text(label.uppercased()).font(.mono(8.5)).foregroundStyle(Theme.faint)
        }
    }
}

extension Forecast {
    /// Where the forecast comes from, in one line: "Veðurstofa Íslands · Reykjavík" or the models.
    var sourceLine: String {
        if let official {
            return "\(IMOForecast.sourceName) · \(official.station.name)"
        }
        return sources.joined(separator: " + ")
    }

    /// Who made the forecast for a given hour.
    func source(at date: Date) -> String {
        if let official, official.covers(date) { return IMOForecast.sourceName }
        if let primaryUntil, date <= primaryUntil, sources.contains("MET Norway") { return "MET Norway" }
        return sources.last(where: { $0 != IMOForecast.sourceName }) ?? "Open-Meteo"
    }
}

/// Under a forecast: which part is IMO's, from which station, issued when, until
/// when; what the models add; and the switch to the models after IMO's horizon.
struct ForecastSourceNote: View {
    let forecast: Forecast

    var body: some View {
        if let official = forecast.official {
            VStack(alignment: .leading, spacing: 3) {
                Text(official.issued.map { String(localized: "Previsione ufficiale per la stazione \(official.station.name) (\(Int(official.distanceKm.rounded())) km), emessa alle \(Fmt.dayTime($0, in: .iceland)).") }
                     ?? String(localized: "Previsione ufficiale per la stazione \(official.station.name) (\(Int(official.distanceKm.rounded())) km)."))
                    .font(.app(.caption)).foregroundStyle(Theme.text)
                Text(String(localized: "Da Veðurstofa Íslands fino a \(Fmt.dayTime(official.until, in: .iceland)): temperatura, vento medio e direzione, cielo, nuvolosità e pioggia. Raffiche, probabilità di pioggia e nuvole a strati da MET Norway e Open-Meteo; dopo quell'ora, solo i modelli."))
                    .font(.app(.caption)).foregroundStyle(Theme.dim)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
