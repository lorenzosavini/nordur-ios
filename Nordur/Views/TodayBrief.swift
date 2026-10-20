import SwiftUI

/// "In breve": the answers first, in plain words, each a tap away from its
/// section — the aurora tonight, the next hours, the roads around, warnings.
struct TodayBrief: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let lines = brief
        VStack(alignment: .leading, spacing: 0) {
            Text("In breve").font(.app(.title3, .semibold)).foregroundStyle(Theme.text).padding(.bottom, 8)
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                Button {
                    Haptics.tap()
                    line.action()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: line.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(line.color)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.title).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text)
                            Text(line.text).font(.app(.subheadline)).foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.faint)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < lines.count - 1 { Rule() }
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("today.brief")
    }

    private struct Line {
        let symbol: String
        let color: Color
        let title: String
        let text: String
        let action: () -> Void
    }

    private var brief: [Line] {
        var lines: [Line] = []
        // Warnings first when there are any.
        let warnings = model.warningsHere
        if let worst = warnings.max(by: { $0.color < $1.color }) {
            lines.append(Line(symbol: "exclamationmark.triangle.fill", color: worst.color.color,
                              title: warnings.count == 1 ? String(localized: "Allerta IMO") : String(localized: "\(warnings.count) allerte IMO"),
                              text: worst.headline, action: { model.requestedTab = "weather" }))
        }
        // Aurora tonight.
        if let best = model.auroraBestTonight {
            let good = best.observability >= .good, fair = best.observability == .moderate
            lines.append(Line(symbol: "sparkles", color: good ? Theme.aurora : fair ? Theme.caution : Theme.dim,
                              title: String(localized: "Aurora stanotte: \(best.observability.label.lowercased())"),
                              text: String(localized: "Il momento migliore verso le \(Fmt.time(best.date, in: .iceland))") + (best.reasons.first.map { " · " + $0.loc } ?? ""),
                              action: { model.requestedTab = "aurora" }))
        }
        // The next 12 hours.
        let hours = (model.forecast?.value.hours ?? []).filter { $0.date > Date().addingTimeInterval(-1800) }.prefix(12)
        if !hours.isEmpty {
            let temps = hours.compactMap(\.temperature)
            let gust = hours.compactMap(\.gust).max()
            let rain = hours.compactMap(\.precipitation).reduce(0, +)
            let risk = hours.map(\.windRisk).max() ?? .ok
            var parts = [String]()
            if let lo = temps.min(), let hi = temps.max() { parts.append("\(Fmt.temp(lo))…\(Fmt.temp(hi))") }
            if let gust { parts.append(String(localized: "raffiche fino a \(Fmt.ms(gust))")) }
            parts.append(rain >= 0.5 ? String(localized: "pioggia \(Fmt.number(rain, decimals: 0)) mm") : String(localized: "asciutto"))
            lines.append(Line(symbol: "cloud.sun.fill", color: risk == .ok ? Theme.dim : risk.color,
                              title: String(localized: "Prossime 12 ore"), text: parts.joined(separator: " · "),
                              action: { model.requestedTab = "weather" }))
        }
        // Roads within 60 km.
        if model.inIceland, let info = model.roadInfo?.value {
            let c = model.activePlace.coordinate
            let near = info.sections.filter { ($0.distanceKm(to: c) ?? .infinity) < 60 }
            let closed = near.filter(\.isClosed)
            let hard = near.filter { !$0.isClosed && ($0.risk ?? .ok) >= .warning }
            let text: String
            if closed.isEmpty && hard.isEmpty {
                text = String(localized: "Percorribili nel raggio di 60 km")
            } else {
                var parts = [String]()
                if !closed.isEmpty { parts.append(String(localized: "\(closed.count) chiuse")) }
                if !hard.isEmpty { parts.append(String(localized: "\(hard.count) difficili")) }
                text = parts.joined(separator: ", ") + ((closed.first ?? hard.first).map { " · " + $0.name } ?? "")
            }
            lines.append(Line(symbol: "road.lanes", color: !closed.isEmpty ? Theme.danger : !hard.isEmpty ? Theme.warning : Theme.dim,
                              title: String(localized: "Strade vicine"), text: text, action: { model.requestedTab = "map" }))
        }
        if warnings.isEmpty {
            lines.append(Line(symbol: "checkmark.shield", color: Theme.dim, title: String(localized: "Nessuna allerta IMO qui"),
                              text: String(localized: "Meteo, vulcani e terremoti: tutto tranquillo"), action: { model.requestedTab = "weather" }))
        }
        return lines
    }
}

/// During the trip: where you are, where today goes, the next thing to see.
struct TodayTripCard: View {
    @Environment(AppModel.self) private var model
    @Environment(TripStore.self) private var trip

    var body: some View {
        let today = Calendar.iceland.startOfDay(for: Date())
        if let day = trip.days.first(where: { $0.date == today }) {
            let next = day.visits.first { $0.visit.end > Date() }
            Button { model.requestedTab = "trip" } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(String(localized: "Il viaggio di oggi · giorno \(day.number)")).font(.app(.title3, .semibold)).foregroundStyle(Theme.text)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.faint)
                    }
                    if let a = day.arriving, let f = day.from {
                        Label("\(f.place.name) → \(a.place.name)", systemImage: a.transport.symbol).font(.app(.headline)).foregroundStyle(Theme.text)
                    }
                    if let next {
                        HStack(spacing: 12) {
                            PlaceThumb(place: next.visit.place, kind: next.visit.kind ?? Attraction.named(next.visit.place.name)?.kind, size: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(next.visit.date > Date() ? String(localized: "Prossima alle \(Fmt.time(next.visit.date, in: .iceland))") : String(localized: "Adesso"))
                                    .font(.app(.caption, .semibold)).foregroundStyle(Theme.accent)
                                Text(next.visit.place.name).font(.app(.headline)).foregroundStyle(Theme.text)
                            }
                        }
                    } else if !day.visits.isEmpty {
                        Text("Attrazioni di oggi finite").font(.app(.subheadline)).foregroundStyle(Theme.dim)
                    }
                    if let night = day.night {
                        Label(String(localized: "Notte: \(night.place.name)"), systemImage: "bed.double.fill").font(.app(.subheadline)).foregroundStyle(Theme.dim)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today.trip")
        }
    }
}
