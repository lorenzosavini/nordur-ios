import SwiftUI
import WidgetKit

// MARK: - Timeline

/// Today's leg of the trip as the app wrote it (App Group), redrawn every
/// 15 minutes for the daylight left. A tap opens the stop in the app.
struct TripTodayEntry: TimelineEntry {
    enum Status { case leg(TripTodaySnapshot), noTrip, notShared }

    let date: Date
    let status: Status

    static let placeholder = TripTodayEntry(date: Date(), status: .leg(TripTodaySnapshot(
        stopID: UUID(), isToday: true, day: Calendar.iceland.startOfDay(for: Date()),
        fromName: "Selfoss", toName: "Vík", toLat: 63.4186, toLon: -19.006, transport: "car",
        km: 128, driveMinutes: 110, departBy: Date().addingTimeInterval(3 * 3600), departAtDawn: false,
        sunrise: Date().addingTimeInterval(-2 * 3600), sunset: Date().addingTimeInterval(5 * 3600),
        alerts: [.init(title: "Raffiche fino a 24 m/s a Vík", severity: 2)])))
}

struct TripTodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TripTodayEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (TripTodayEntry) -> Void) {
        completion(context.isPreview ? .placeholder : entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TripTodayEntry>) -> Void) {
        let now = Date()
        // Every 15 minutes for 3 hours (daylight left, "leave by"); the app asks
        // for a reload whenever the trip, the warnings or the roads change.
        let entries = (0..<12).map { entry(at: now.addingTimeInterval(Double($0) * 15 * 60)) }
        let midnight = Calendar.iceland.date(byAdding: .day, value: 1, to: Calendar.iceland.startOfDay(for: now)) ?? now.addingTimeInterval(3 * 3600)
        completion(Timeline(entries: entries, policy: .after(min(now.addingTimeInterval(3 * 3600), midnight.addingTimeInterval(60)))))
    }

    private func entry(at date: Date) -> TripTodayEntry {
        guard SharedStore.container != nil, let file = SharedStore.readTripToday() else {
            return TripTodayEntry(date: date, status: .notShared)
        }
        guard var snapshot = file.snapshot else { return TripTodayEntry(date: date, status: .noTrip) }
        // Written yesterday: the stop is no longer "today".
        if snapshot.isToday, !Calendar.iceland.isDate(snapshot.day, inSameDayAs: date) {
            if snapshot.day < Calendar.iceland.startOfDay(for: date) { return TripTodayEntry(date: date, status: .noTrip) }
            snapshot.isToday = false
        }
        return TripTodayEntry(date: date, status: .leg(snapshot))
    }
}

// MARK: - Views

struct TripTodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TripTodayEntry

    var body: some View {
        switch entry.status {
        case .leg(let leg): legView(leg)
        case .noTrip: message(String(localized: "Nessuna tappa in programma"), String(localized: "Aggiungi le tappe nella scheda Viaggio."), symbol: "suitcase.rolling")
        case .notShared: message(String(localized: "Apri Norður"), String(localized: "Il widget mostra la tappa dopo il primo avvio dell'app."), symbol: "arrow.up.forward.app")
        }
    }

    @ViewBuilder private func message(_ title: String, _ detail: String, symbol: String) -> some View {
        switch family {
        case .accessoryInline:
            Label(title, systemImage: symbol)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label(title, systemImage: symbol).font(.app(.headline)).widgetAccentable()
                Text(detail).font(.app(.caption2)).lineLimit(2)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol).font(.title3).foregroundStyle(Theme.accent)
                Text(title).font(.app(.headline))
                Text(detail).font(.app(.caption2)).foregroundStyle(.secondary).lineLimit(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder private func legView(_ leg: TripTodaySnapshot) -> some View {
        switch family {
        case .accessoryInline:
            Text(inlineText(leg))
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("→ \(leg.toName)").font(.app(.headline)).lineLimit(1).widgetAccentable()
                Text(distanceText(leg)).font(.app(.caption)).lineLimit(1)
                if let alert = leg.alerts.first {
                    Label(alert.title, systemImage: "exclamationmark.triangle.fill").font(.app(.caption2)).lineLimit(1)
                } else if let depart = departShort(leg) {
                    Text(depart).font(.app(.caption2))
                } else {
                    Text(dayLabel(leg)).font(.app(.caption2))
                }
            }
        case .systemMedium:
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    header(leg)
                    Spacer(minLength: 0)
                    lightBlock(leg)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 5) {
                    if leg.alerts.isEmpty {
                        Label("Nessuna allerta sul percorso", systemImage: "checkmark.seal").font(.app(.caption2)).foregroundStyle(.green)
                    } else {
                        ForEach(leg.alerts.prefix(3), id: \.self) { alert in
                            HStack(alignment: .top, spacing: 4) {
                                Circle().fill((Risk(rawValue: alert.severity) ?? .caution).color).frame(width: 7, height: 7).padding(.top, 4)
                                Text(alert.title).font(.app(.caption2)).lineLimit(2)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .widgetURL(leg.deepLink)
        default:
            VStack(alignment: .leading, spacing: 4) {
                header(leg)
                Spacer(minLength: 0)
                if let alert = leg.alerts.first {
                    HStack(spacing: 4) {
                        Circle().fill((Risk(rawValue: alert.severity) ?? .caution).color).frame(width: 7, height: 7)
                        Text(alert.title).font(.app(.caption2)).lineLimit(2)
                    }
                } else {
                    lightBlock(leg)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(leg.deepLink)
        }
    }

    private func header(_ leg: TripTodaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dayLabel(leg).uppercased()).font(.mono(9.5, .semibold)).foregroundStyle(Theme.accent).lineLimit(1)
            if let from = leg.fromName {
                Text("da \(from)").font(.app(.caption2)).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(leg.toName).font(.display(22, .bold)).lineLimit(1).minimumScaleFactor(0.6)
            Text(distanceText(leg)).font(.app(.caption, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    @ViewBuilder private func lightBlock(_ leg: TripTodaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let depart = departLong(leg) {
                Label(depart, systemImage: "clock").font(.app(.caption2, .semibold)).lineLimit(2)
            }
            if leg.isToday, let light = lightText(leg) {
                Label(light, systemImage: "sun.horizon").font(.app(.caption2)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    // MARK: Text

    private func inlineText(_ leg: TripTodaySnapshot) -> String {
        var parts = ["→ " + leg.toName]
        if let km = leg.km { parts.append("\(Int(km.rounded())) km") }
        if let depart = departShort(leg) { parts.append(depart) }
        return parts.joined(separator: " · ")
    }

    private func dayLabel(_ leg: TripTodaySnapshot) -> String {
        leg.isToday ? String(localized: "Tappa di oggi") : String(localized: "Prossima tappa · \(Fmt.day(leg.day, in: .iceland))")
    }

    private func distanceText(_ leg: TripTodaySnapshot) -> String {
        guard let km = leg.km else { return Transport(rawValue: leg.transport)?.label ?? "" }
        if let minutes = leg.driveMinutes {
            return String(localized: "~\(Int(km.rounded())) km · ~\(Fmt.duration(Double(minutes) * 60))")
        }
        return String(localized: "~\(Int(km.rounded())) km in linea d'aria")
    }

    private func departShort(_ leg: TripTodaySnapshot) -> String? {
        guard leg.isToday, let depart = leg.departBy, depart > entry.date else { return nil }
        return String(localized: "parti entro le \(Fmt.time(depart, in: .iceland))")
    }

    private func departLong(_ leg: TripTodaySnapshot) -> String? {
        guard leg.isToday, let depart = leg.departBy else { return nil }
        if leg.departAtDawn { return String(localized: "Viaggio più lungo della luce: parti all'alba (\(Fmt.time(depart, in: .iceland)))") }
        guard depart > entry.date else { return String(localized: "Arriverai col buio: guida con prudenza") }
        return String(localized: "Parti entro le \(Fmt.time(depart, in: .iceland)) per arrivare con la luce")
    }

    private func lightText(_ leg: TripTodaySnapshot) -> String? {
        let now = entry.date
        if let sunrise = leg.sunrise, now < sunrise { return String(localized: "Alba alle \(Fmt.time(sunrise, in: .iceland))") }
        guard let sunset = leg.sunset else { return nil }
        if now >= sunset { return String(localized: "Già buio (tramonto \(Fmt.time(sunset, in: .iceland)))") }
        let minutes = Int(sunset.timeIntervalSince(now) / 60)
        return String(localized: "Luce ancora \(minutes / 60) h \(minutes % 60) min")
    }
}

struct TripTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NordurTripToday", provider: TripTodayProvider()) { entry in
            TripTodayWidgetView(entry: entry)
                .containerBackground(Theme.bg, for: .widget)
        }
        .configurationDisplayName(String(localized: "Tappa di oggi"))
        .description(String(localized: "Da dove a dove, km, quando partire per arrivare con la luce e le allerte sul percorso."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
