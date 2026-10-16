import SwiftUI
import WidgetKit
import AppIntents
import CoreLocation

// MARK: - Configuration (choose the place shown by the widget)

struct PlaceEntity: AppEntity {
    static let currentID = "current"

    let id: String
    let name: String
    let coordinate: Coordinate?

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Luogo"
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static var defaultQuery = PlaceEntityQuery()

    static let current = PlaceEntity(id: currentID, name: String(localized: "Posizione attuale"), coordinate: nil)
    static var all: [PlaceEntity] {
        [current] + Place.presets.map { PlaceEntity(id: $0.name, name: $0.name, coordinate: $0.coordinate) }
    }
}

struct PlaceEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PlaceEntity] {
        PlaceEntity.all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [PlaceEntity] { PlaceEntity.all }

    func defaultResult() async -> PlaceEntity? { .current }
}

struct SelectPlaceIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Luogo"
    static var description = IntentDescription("Scegli il luogo da mostrare nel widget.")

    @Parameter(title: "Luogo")
    var place: PlaceEntity?
}

// MARK: - Location inside the widget extension

/// Created on the main actor so Core Location can deliver its callbacks.
@MainActor
final class WidgetLocator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Coordinate?, Never>?

    func current() async -> Coordinate? {
        guard manager.isAuthorizedForWidgetUpdates else { return nil }
        if let recent = manager.location, Date().timeIntervalSince(recent.timestamp) < 15 * 60 {
            return Coordinate(recent.coordinate)
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyKilometer
            manager.requestLocation()
            Task {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                self.finish(self.manager.location)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location.map { Coordinate($0.coordinate) })
        continuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.finish(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let fallback = manager.location
        Task { @MainActor in self.finish(fallback) }
    }
}

// MARK: - Timeline

struct ConditionsEntry: TimelineEntry {
    let date: Date
    let placeName: String
    let temperature: Double?
    let code: Int?
    let isDay: Bool
    let wind: Double?
    let gust: Double?
    let windDirection: Double?
    let maxGust12h: Double?
    let warning: WeatherWarning?
    let warningCount: Int
    let auroraScore: Int?
    let auroraTime: Date?
    let zone: TimeZone

    var windRisk: Risk { Risk.wind(mean: wind, gust: gust) }

    static let placeholder = ConditionsEntry(
        date: Date(), placeName: "Reykjavík", temperature: 6, code: 3, isDay: true, wind: 9, gust: 17, windDirection: 200,
        maxGust12h: 22, warning: nil, warningCount: 0, auroraScore: 3, auroraTime: Date(), zone: .iceland)
}

struct ConditionsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ConditionsEntry { .placeholder }

    func snapshot(for configuration: SelectPlaceIntent, in context: Context) async -> ConditionsEntry {
        context.isPreview ? .placeholder : await load(configuration)
    }

    func timeline(for configuration: SelectPlaceIntent, in context: Context) async -> Timeline<ConditionsEntry> {
        let entry = await load(configuration)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60)))
    }

    private func load(_ configuration: SelectPlaceIntent) async -> ConditionsEntry {
        let chosen = configuration.place ?? .current
        var coordinate = chosen.coordinate
        var name = chosen.name
        if chosen.id == PlaceEntity.currentID {
            let locator = await WidgetLocator()
            if let here = await locator.current() {
                coordinate = here
                name = String(localized: "Qui")
            } else {
                coordinate = Place.reykjavik.coordinate
                name = Place.reykjavik.name
            }
        }
        let c = coordinate ?? Place.reykjavik.coordinate

        async let forecastResult = attempt { try await WeatherService.forecast(c).value }
        async let warningsResult = attempt { try await IMO.warnings().value }
        async let stateResult = attempt { try await AuroraStateService.load().value }
        let forecast = try? await forecastResult.get()
        let warnings = ((try? await warningsResult.get()) ?? []).filter { $0.covers(c) }
        let state = try? await stateResult.get()
        var kp: [KpPoint] = []
        if state == nil { kp = (try? await SpaceWeather.kpForecast().value) ?? [] }

        let current = forecast?.current
        let slots = AuroraEngine.forecast(AuroraInputs.make(place: c, forecast: forecast, state: state, kp: kp, ovation: nil), hours: 24)
        let best = AuroraEngine.best(slots, within: 24)
        return ConditionsEntry(
            date: Date(),
            placeName: name,
            temperature: current?.temperature_2m,
            code: current?.weather_code,
            isDay: (current?.is_day ?? 1) == 1,
            wind: current?.wind_speed_10m,
            gust: current?.wind_gusts_10m,
            windDirection: current?.wind_direction_10m,
            maxGust12h: forecast?.upcomingHours(12).compactMap(\.gust).max(),
            warning: warnings.first,
            warningCount: warnings.count,
            auroraScore: best?.observability.rawValue,
            auroraTime: best?.date,
            zone: forecast?.timeZone ?? .iceland
        )
    }
}

// MARK: - Views

struct ConditionsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ConditionsEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: min(entry.gust ?? 0, 40), in: 0...40) {
                Image(systemName: "wind")
            } currentValueLabel: {
                Text("\(Int((entry.gust ?? 0).rounded()))")
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("\(entry.placeName) \(Fmt.temp(entry.temperature))").font(.app(.headline)).widgetAccentable()
                Text("Vento \(Fmt.ms(entry.wind)) · raff. \(Fmt.ms(entry.gust))").font(.app(.caption))
                if let warning = entry.warning {
                    Text(warning.color.label).font(.app(.caption2))
                } else {
                    Text("Nessuna allerta").font(.app(.caption2))
                }
            }
        case .accessoryInline:
            Text("\(Fmt.temp(entry.temperature)) · raff. \(Fmt.ms(entry.gust))\(entry.warning != nil ? String(localized: " · allerta") : "")")
        case .systemMedium:
            HStack(alignment: .top) {
                mainBlock
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    warningBlock
                    if let raw = entry.auroraScore, let cls = ObservabilityClass(rawValue: raw) {
                        Label("Aurora: \(cls.label.lowercased())\(entry.auroraTime.map { " · \(Fmt.time($0, in: entry.zone))" } ?? "")", systemImage: "moon.stars.fill")
                            .font(.app(.caption)).foregroundStyle(.secondary)
                    }
                    Label("Raffica max 12 h: \(Fmt.ms(entry.maxGust12h))", systemImage: "wind")
                        .font(.app(.caption))
                        .foregroundStyle(Risk.wind(mean: nil, gust: entry.maxGust12h).color)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                mainBlock
                warningBlock
            }
        }
    }

    private var mainBlock: some View {
        let info = WeatherCode.describe(entry.code, isDay: entry.isDay)
        return VStack(alignment: .leading, spacing: 4) {
            Text(entry.placeName).font(.app(.caption, .semibold)).lineLimit(1)
            HStack {
                Image(systemName: info.symbol).symbolRenderingMode(.hierarchical)
                Text(Fmt.temp(entry.temperature)).font(.app(.title, .semibold))
            }
            HStack(spacing: 3) {
                WidgetWindArrow(degrees: entry.windDirection)
                Text("\(Int((entry.wind ?? 0).rounded()))/\(Int((entry.gust ?? 0).rounded())) m/s")
                    .font(.app(.caption, .semibold))
                    .foregroundStyle(entry.windRisk == .ok ? Color.primary : entry.windRisk.color)
            }
            Text("agg. \(Fmt.time(entry.date))").font(.app(.caption2)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var warningBlock: some View {
        if let warning = entry.warning {
            HStack(spacing: 4) {
                Circle().fill(warning.color.color).frame(width: 8, height: 8)
                Text(warning.headline).font(.app(.caption2)).lineLimit(2)
            }
        } else {
            Label("Nessuna allerta", systemImage: "checkmark.seal").font(.app(.caption2)).foregroundStyle(.green)
        }
    }
}

struct WidgetWindArrow: View {
    let degrees: Double?
    var body: some View {
        Image(systemName: "location.north.fill")
            .font(.app(.caption2))
            .rotationEffect(.degrees((degrees ?? 0) + 180))
    }
}

struct ConditionsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NordurConditions", intent: SelectPlaceIntent.self, provider: ConditionsProvider()) { entry in
            ConditionsWidgetView(entry: entry)
                .containerBackground(Theme.bg, for: .widget)
        }
        .configurationDisplayName(String(localized: "Condizioni Norður"))
        .description(String(localized: "Temperatura, vento, raffiche e allerte IMO per un luogo."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Aurora widget

struct AuroraWidgetView: View {
    let entry: ConditionsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Aurora", systemImage: "moon.stars.fill").font(.app(.caption, .semibold)).foregroundStyle(.secondary)
            if let raw = entry.auroraScore, let cls = ObservabilityClass(rawValue: raw) {
                Text(cls.label.uppercased()).font(.display(18, .bold)).lineLimit(2).minimumScaleFactor(0.7)
                Gauge(value: Double(raw), in: 0...4) { Text("") }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(Theme.aurora)
                if let time = entry.auroraTime {
                    Text("Meglio verso le \(Fmt.time(time, in: entry.zone))").font(.app(.caption2))
                }
            } else {
                Text("Niente buio stanotte").font(.app(.caption2)).foregroundStyle(.secondary)
            }
            Text(entry.placeName).font(.app(.caption2)).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

struct AuroraWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NordurAurora", intent: SelectPlaceIntent.self, provider: ConditionsProvider()) { entry in
            AuroraWidgetView(entry: entry)
                .containerBackground(Theme.bg, for: .widget)
        }
        .configurationDisplayName(String(localized: "Aurora stanotte"))
        .description(String(localized: "Classe di osservabilità dell’aurora stanotte: attività prevista, nuvole, buio e Luna."))
        .supportedFamilies([.systemSmall])
    }
}
