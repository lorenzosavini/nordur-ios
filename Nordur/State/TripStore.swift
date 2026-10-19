import Foundation
import Observation

@MainActor
@Observable
final class TripStore {
    private(set) var stops: [TripStop] = []
    private(set) var forecasts: [String: Forecast] = [:]
    private(set) var marines: [String: Marine] = [:]

    init() {
        stops = Self.loadFromDisk()
        // Demo video only (`-ciDemoTrip YES`): a ring-road itinerary to show the Trip tab filled in.
        if stops.isEmpty, UserDefaults.standard.bool(forKey: "ciDemoTrip") {
            stops = Self.demoTrip()
        }
    }

    private static func demoTrip() -> [TripStop] {
        let start = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!.addingTimeInterval(10 * 3600)
        let plan: [(String, Int)] = [("Reykjavík", 2), ("Vík í Mýrdal", 1), ("Höfn", 1), ("Akureyri", 2)]
        var date = start
        var result: [TripStop] = []
        for (name, nights) in plan {
            guard let place = ([Place.reykjavik] + Place.presets).first(where: { $0.name.hasPrefix(name) }) else { continue }
            var stop = TripStop(place: place, date: date, nights: nights)
            // Sights along the way on the arrival day.
            let sights: [String: [String]] = [
                "Vík í Mýrdal": ["Seljalandsfoss", "Skógafoss", "Reynisfjara"],
                "Höfn": ["Fjaðrárgljúfur", "Jökulsárlón", "Diamond Beach"],
                "Akureyri": ["Dettifoss", "Hverir", "Goðafoss"],
            ]
            for name in sights.first(where: { name.hasPrefix($0.key) || $0.key.hasPrefix(name) })?.value ?? [] {
                if let a = Attraction.named(name) {
                    stop.visits.append(.next(at: a.place, kind: a.kind, minutes: a.minutes, in: stop))
                }
            }
            result.append(stop)
            date = Calendar.current.date(byAdding: .day, value: nights, to: date) ?? date
        }
        return result
    }

    func reload() { stops = Self.loadFromDisk() }

    nonisolated static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("trip.json")
    }

    nonisolated static func loadFromDisk() -> [TripStop] {
        guard let data = try? Data(contentsOf: fileURL),
              let stops = try? JSONDecoder().decode([TripStop].self, from: data) else { return [] }
        return stops.sorted { $0.date < $1.date }
    }

    private func save() {
        stops.sort { $0.date < $1.date }
        if let data = try? JSONEncoder().encode(stops) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    func upsert(_ stop: TripStop) {
        if let index = stops.firstIndex(where: { $0.id == stop.id }) {
            stops[index] = stop
        } else {
            stops.append(stop)
        }
        save()
    }

    func delete(_ stop: TripStop) {
        stops.removeAll { $0.id == stop.id }
        save()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) { stops.remove(at: index) }
        save()
    }

    /// Next stop after `stop`, i.e. the leg you travel from it.
    func next(after stop: TripStop) -> TripStop? {
        guard let index = stops.firstIndex(where: { $0.id == stop.id }), index + 1 < stops.count else { return nil }
        return stops[index + 1]
    }

    func previous(before stop: TripStop) -> TripStop? {
        guard let index = stops.firstIndex(where: { $0.id == stop.id }), index > 0 else { return nil }
        return stops[index - 1]
    }

    // MARK: Visits (attractions)

    func upsert(_ visit: TripVisit, in stopID: UUID) {
        guard let index = stops.firstIndex(where: { $0.id == stopID }) else { return }
        if let v = stops[index].visits.firstIndex(where: { $0.id == visit.id }) {
            stops[index].visits[v] = visit
        } else {
            stops[index].visits.append(visit)
        }
        save()
    }

    func delete(_ visit: TripVisit, in stopID: UUID) {
        guard let index = stops.firstIndex(where: { $0.id == stopID }) else { return }
        stops[index].visits.removeAll { $0.id == visit.id }
        save()
    }

    func forecast(at c: Coordinate) -> Forecast? { forecasts[c.key] }

    func forecast(for stop: TripStop) -> Forecast? { forecasts[stop.place.coordinate.key] }
    func marine(for stop: TripStop) -> Marine? { marines[stop.place.coordinate.key] }

    func loadForecasts() async {
        // Stops and the attractions to see: the weather at the time of each visit.
        let coordinates = Array(Set(stops.map(\.place.coordinate) + stops.flatMap { $0.visits.map(\.place.coordinate) }))
        await withTaskGroup(of: (String, Forecast?, Marine?).self) { group in
            for c in coordinates {
                group.addTask {
                    let f = try? await WeatherService.forecast(c).value
                    let m = try? await OpenMeteo.marine(c).value
                    return (c.key, f, m)
                }
            }
            for await (key, forecast, marine) in group {
                if let forecast { forecasts[key] = forecast }
                if let marine { marines[key] = marine }
            }
        }
    }
}
