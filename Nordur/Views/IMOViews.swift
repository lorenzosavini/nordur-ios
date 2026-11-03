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
            if !details.isEmpty {
                // Everything else the station measured: humidity, dew point, pressure, rain, visibility, cloud, snow, sea.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(details) { d in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(d.value).font(.metric(13, .medium)).foregroundStyle(Theme.text).monospacedDigit()
                            Text(d.label.uppercased()).font(.mono(8)).foregroundStyle(Theme.faint).lineLimit(1)
                        }
                    }
                }
            }
            if let text = observation.text {
                Text(text).font(.app(.caption)).foregroundStyle(Theme.dim)
            }
            Text(observation.tenMinute == true
                 ? String(localized: "Veðurstofa Íslands · stazione a \(Int(observation.distanceKm.rounded())) km, misura delle \(Fmt.time(observation.time, in: .iceland)) (ogni 10 minuti)")
                 : String(localized: "Veðurstofa Íslands · stazione a \(Int(observation.distanceKm.rounded())) km, misura delle \(Fmt.time(observation.time, in: .iceland))"))
                .font(.app(.caption2)).foregroundStyle(Theme.faint)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private struct Detail: Identifiable {
        let label: String
        let value: String
        var id: String { label }
        init(_ label: String, _ value: String) { self.label = label; self.value = value }
    }

    private var details: [Detail] {
        let o = observation
        var out: [Detail] = []
        if let x = o.maxWind, x > (o.wind ?? 0) { out.append(Detail(String(localized: "vento max 1 h"), "\(Fmt.wind(x)) \(Fmt.windUnit)")) }
        if let x = o.humidity { out.append(Detail(String(localized: "umidità"), "\(Int(x.rounded()))%")) }
        if let x = o.dewPoint { out.append(Detail(String(localized: "punto di rugiada"), Fmt.temp(x))) }
        if let x = o.pressure { out.append(Detail(String(localized: "pressione"), "\(Int(x.rounded())) hPa")) }
        if let x = o.precipitation { out.append(Detail(String(localized: "pioggia 1 h"), "\(Fmt.number(x, decimals: 1)) mm")) }
        if let x = o.visibility { out.append(Detail(String(localized: "visibilità"), "\(Fmt.number(x, decimals: x < 10 ? 1 : 0)) km")) }
        if let x = o.cloud { out.append(Detail(String(localized: "nuvolosità"), "\(Int(x.rounded()))%")) }
        if let x = o.snowDepth { out.append(Detail(String(localized: "neve al suolo"), "\(Int(x.rounded())) cm")) }
        if let x = o.snowCover { out.append(Detail(String(localized: "suolo"), x)) }
        if let x = o.sea { out.append(Detail(String(localized: "mare"), x)) }
        return out
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
