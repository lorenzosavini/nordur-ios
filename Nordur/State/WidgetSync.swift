import Foundation
import WidgetKit

/// Writes today's leg of the trip for the "Tappa di oggi" widget (App Group)
/// and keeps it in memory for the drive Live Activity. Rewritten when the
/// trip, the forecasts, the warnings or the roads change; the widget is asked
/// to redraw only when what it shows has changed.
@MainActor
enum WidgetSync {
    static let tripTodayKind = "NordurTripToday"

    /// The last snapshot computed (also without the App Group).
    private(set) static var tripToday: TripTodaySnapshot?
    private static var lastWritten: TripTodaySnapshot??

    static func update(trip: TripStore, model: AppModel, now: Date = Date()) {
        let snapshot = makeSnapshot(stops: trip.stops, trip: trip, model: model, now: now)
        tripToday = snapshot
        // Same content as the last write: nothing to tell the widget. Rewritten
        // anyway after a day change so the file never says "today" for yesterday.
        if let last = lastWritten, last == snapshot { return }
        lastWritten = .some(snapshot)
        if SharedStore.writeTripToday(TripTodayFile(snapshot: snapshot, written: now)) {
            WidgetCenter.shared.reloadTimelines(ofKind: tripTodayKind)
        }
    }

    static func makeSnapshot(stops: [TripStop], trip: TripStore, model: AppModel, now: Date) -> TripTodaySnapshot? {
        let calendar = Calendar.iceland
        let today = calendar.startOfDay(for: now)
        let sorted = stops.sorted { $0.date < $1.date }
        let arrivingToday = sorted.first { calendar.isDate($0.date, inSameDayAs: now) }
        guard let stop = arrivingToday ?? sorted.first(where: { calendar.startOfDay(for: $0.date) > today }) else { return nil }
        let previous = sorted.last { $0.date < stop.date && $0.id != stop.id }
        let day = calendar.startOfDay(for: stop.date)
        let to = stop.place.coordinate
        let from = previous?.place.coordinate
        let byRoad = stop.transport == .car || stop.transport == .bus

        var km: Double?
        var minutes: Int?
        if let from {
            let straight = Geo.distanceKm(from, to)
            km = straight * (byRoad ? 1.3 : 1)
            if byRoad, let km { minutes = Int((km / 70 * 60).rounded()) }
        }

        // Daylight on the travel day: sunrise where you leave, sunset where you arrive.
        let sunrise = Astro.crossings(of: -0.833, from: day, at: from ?? to).up
        let sunset = Astro.crossings(of: -0.833, from: day, at: to).down
        var departBy: Date?
        var atDawn = false
        if byRoad, let minutes {
            let plan = TripTodaySnapshot.departure(sunrise: sunrise, sunset: sunset, driveMinutes: minutes)
            departBy = plan.date
            atDawn = plan.atDawn
        }

        return TripTodaySnapshot(
            stopID: stop.id,
            isToday: arrivingToday != nil,
            day: day,
            fromName: previous?.place.name,
            toName: stop.place.name,
            toLat: to.lat, toLon: to.lon,
            transport: stop.transport.rawValue,
            km: km,
            driveMinutes: minutes,
            departBy: departBy,
            departAtDawn: atDawn,
            sunrise: sunrise,
            sunset: sunset,
            alerts: alerts(from: from, to: to, toName: stop.place.name, day: day, byRoad: byRoad,
                           forecast: trip.forecast(for: stop), model: model, isToday: arrivingToday != nil, now: now)
        )
    }

    /// IMO warnings along the way on the travel day, the worst road station
    /// near the line (today only: road conditions are live), wind at arrival.
    private static func alerts(from: Coordinate?, to: Coordinate, toName: String, day: Date, byRoad: Bool,
                               forecast: Forecast?, model: AppModel, isToday: Bool, now: Date) -> [TripTodaySnapshot.Alert] {
        var result: [TripTodaySnapshot.Alert] = []
        let samples = from.map { TripLegCheck.samples(from: $0, to: to) } ?? [to]
        let dayEnd = day.addingTimeInterval(24 * 3600)
        var seen = Set<String>()
        for warning in model.warnings?.value ?? [] where warning.overlaps(max(day, now), dayEnd) {
            guard samples.contains(where: { warning.covers($0) }), seen.insert(warning.headline).inserted else { continue }
            result.append(.init(title: warning.headline, severity: warning.color.risk.rawValue))
        }
        if isToday, byRoad, let from, let network = model.roads?.value {
            let worst = network.corridor(from: from, to: to)
                .map { (station: $0, risk: network.worstRisk(of: $0)) }
                .max { $0.risk < $1.risk }
            if let worst, worst.risk > .ok {
                result.append(.init(title: String(localized: "Strada: \(worst.station.name) – \(worst.risk.label.lowercased())"),
                                    severity: worst.risk.rawValue))
            }
        }
        if isToday, let gust = forecast?.upcomingHours(12, from: now).compactMap(\.gust).max() {
            let risk = Risk.wind(mean: nil, gust: gust)
            if risk > .ok {
                result.append(.init(title: String(localized: "Raffiche fino a \(Fmt.ms(gust)) a \(toName)"), severity: risk.rawValue))
            }
        }
        return Array(result.sorted { $0.severity > $1.severity }.prefix(3))
    }
}
