import SwiftUI
import MapKit

// The trip day by day, all on one page: where you sleep, the drive of the day,
// the weather and every attraction with its time, without opening each stop.
// And the whole route on a map.

/// One calendar day of the trip (Iceland time).
struct TripDay: Identifiable {
    let date: Date
    let number: Int
    /// The stop you sleep at that night (nil on the day you fly home).
    let night: TripStop?
    /// The stop you reach that day, and where you leave from.
    let arriving: TripStop?
    let from: TripStop?
    let visits: [DayVisit]
    var id: Date { date }

    /// Where the day's plan and new attractions belong.
    var owner: TripStop? { arriving ?? night }
}

struct DayVisit: Identifiable {
    let visit: TripVisit
    let stop: TripStop
    var id: UUID { visit.id }
}

extension TripStore {
    var days: [TripDay] {
        let calendar = Calendar.iceland
        guard let first = stops.first, let lastEnd = stops.map(\.endDate).max() else { return [] }
        var result: [TripDay] = []
        var day = calendar.startOfDay(for: first.date)
        let end = calendar.startOfDay(for: lastEnd)
        var n = 1
        while day <= end && n <= 120 {
            let d = day
            let arriving = stops.last { calendar.isDate($0.date, inSameDayAs: d) }
            let night = stops.last { $0.nights > 0 && calendar.startOfDay(for: $0.date) <= d && d < calendar.startOfDay(for: $0.endDate) }
            let visits = stops.flatMap { stop in stop.visits.filter { calendar.isDate($0.date, inSameDayAs: d) }.map { DayVisit(visit: $0, stop: stop) } }
                .sorted { $0.visit.date < $1.visit.date }
            result.append(TripDay(date: d, number: n, night: night, arriving: arriving,
                                  from: arriving.flatMap { previous(before: $0) }, visits: visits))
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? end.addingTimeInterval(86400)
            n += 1
        }
        return result
    }
}

/// A day chosen to add an attraction to, with the stop it goes under.
struct DayAdd: Identifiable {
    let stop: TripStop
    let day: Date
    var id: Date { day }
}

/// The head of a day: where you go, where you sleep, the weather there.
struct TripDayHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(TripStore.self) private var trip
    let day: TripDay

    var body: some View {
        let place = day.night ?? day.arriving ?? trip.stops.last
        let weather = place.flatMap { trip.forecast(for: $0)?.day(for: day.date) }
        let warnings = place.map { model.warnings(at: $0.place.coordinate, from: day.date, to: day.date.addingTimeInterval(86400)) } ?? []
        // The picture of the day: its best-known sight, else where you sleep.
        let highlight = day.visits.first { Attraction.named($0.visit.place.name) != nil }?.visit.place ?? day.visits.first?.visit.place
        VStack(alignment: .leading, spacing: 8) {
            if let banner = highlight ?? place?.place {
                PlaceBanner(place: banner, height: 150) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.display(26, .bold)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.7)
                        Label(day.night.map { String(localized: "Notte: \($0.place.name)") } ?? String(localized: "Nessun pernottamento: rientro"),
                              systemImage: day.night == nil ? "airplane.departure" : "bed.double.fill")
                            .font(.app(.subheadline, .semibold)).foregroundStyle(.white.opacity(0.92)).lineLimit(1)
                    }
                    .shadow(color: .black.opacity(0.5), radius: 4)
                }
            }
            if let weather {
                let info = WeatherCode.describe(weather.code)
                HStack(spacing: 10) {
                    Label("\(Fmt.temp(weather.minTemp))/\(Fmt.temp(weather.maxTemp))", systemImage: info.symbol).symbolRenderingMode(.multicolor)
                    Text(String(localized: "raff. \(Fmt.ms(weather.maxGust))")).foregroundStyle(weather.windRisk == .ok ? Theme.dim : weather.windRisk.color)
                    if let rise = weather.sunrise, let set = weather.sunset {
                        Label("\(Fmt.time(rise, in: .iceland))–\(Fmt.time(set, in: .iceland))", systemImage: "sun.horizon").foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    RiskBadge(risk: weather.overallRisk)
                }
                .font(.app(.caption))
            } else {
                Text("Meteo disponibile circa 10 giorni prima").font(.app(.caption2)).foregroundStyle(Theme.faint)
            }
            ForEach(warnings.prefix(2)) { warning in
                HStack { WarningBadge(color: warning.color); Text(warning.headline).font(.app(.caption2)).lineLimit(2) }
            }
        }
        .padding(.vertical, 2)
    }

    private var title: String {
        if let arriving = day.arriving, let from = day.from { return "\(from.place.name) → \(arriving.place.name)" }
        if let arriving = day.arriving { return String(localized: "Arrivo a \(arriving.place.name)") }
        if let night = day.night { return String(localized: "A \(night.place.name)") }
        return String(localized: "Rientro")
    }
}

/// The trip as sections, one per day, for the Trip list.
struct TripDaysSections: View {
    @Environment(TripStore.self) private var trip
    let onEdit: (DayVisit) -> Void
    let onAdd: (DayAdd) -> Void

    var body: some View {
        let today = Calendar.iceland.startOfDay(for: Date())
        ForEach(trip.days) { day in
            Section {
                TripDayHeader(day: day)
                if let arriving = day.arriving, let from = day.from {
                    if arriving.transport == .car || arriving.transport == .bus {
                        NavigationLink {
                            RouteForecastView(from: from.place, to: arriving.place, departure: max(arriving.date, Date()))
                        } label: { LegLine(from: from, to: arriving) }
                    } else {
                        LegLine(from: from, to: arriving)
                    }
                }
                if let owner = day.owner, !day.visits.isEmpty {
                    DayPlanLine(stop: owner, day: day.date, visits: day.visits.map(\.visit), showsDate: false)
                }
                ForEach(day.visits) { item in
                    VisitRow(visit: item.visit)
                        .contentShape(Rectangle())
                        .onTapGesture { onEdit(item) }
                        .contextMenu { VisitMenu(stop: item.stop, visit: item.visit) { onEdit(item) } }
                        .accessibilityIdentifier("trip.visit")
                }
                if let owner = day.owner {
                    HStack(spacing: 8) {
                        Button { onAdd(DayAdd(stop: owner, day: day.date)) } label: {
                            Label(day.visits.isEmpty ? String(localized: "Aggiungi un'attrazione") : String(localized: "Aggiungi"), systemImage: "plus.circle.fill")
                                .font(.app(.subheadline, .semibold)).foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        NavigationLink {
                            StopDetailView(stopID: owner.id, fallback: owner)
                        } label: {
                            Text(String(localized: "Consigli e tappa")).font(.mono(10.5, .semibold)).foregroundStyle(Theme.dim)
                        }
                        .fixedSize()
                    }
                }
            } header: {
                HStack {
                    Text(String(localized: "Giorno \(day.number) · \(Fmt.day(day.date, in: .iceland))")).pinnedHeader()
                    if Calendar.iceland.isDate(day.date, inSameDayAs: today) {
                        Text("OGGI").font(.mono(9, .bold)).foregroundStyle(Theme.onAccent).padding(.horizontal, 5).background(Theme.accent)
                    }
                }
            }
            .id(day.date)
        }
    }
}

/// The whole route: the stops numbered and joined, the attractions around them.
struct TripMap: View {
    @Environment(TripStore.self) private var trip
    let onSelect: (TripStop) -> Void

    var body: some View {
        let stops = trip.stops
        Map(initialPosition: .automatic) {
            if stops.count > 1 {
                MapPolyline(coordinates: stops.map(\.place.coordinate.clCoordinate)).stroke(Theme.accent, lineWidth: 3)
            }
            ForEach(stops) { stop in
                ForEach(stop.visits) { visit in
                    Annotation("", coordinate: visit.place.coordinate.clCoordinate) {
                        let kind = visit.kind ?? Attraction.named(visit.place.name)?.kind ?? .landscape
                        Image(systemName: kind.symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 20, height: 20).background(Circle().fill(kind.tint))
                            .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                    }
                }
            }
            ForEach(Array(stops.enumerated()), id: \.element.id) { i, stop in
                Annotation(stop.place.name, coordinate: stop.place.coordinate.clCoordinate) {
                    Button { onSelect(stop) } label: {
                        Text("\(i + 1)").font(.metric(15, .bold)).foregroundStyle(Theme.onAccent)
                            .frame(width: 28, height: 28).background(Theme.accent)
                            .overlay(Rectangle().strokeBorder(.white, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            UserAnnotation()
        }
        .mapControls { MapCompass(); MapScaleView() }
    }
}
