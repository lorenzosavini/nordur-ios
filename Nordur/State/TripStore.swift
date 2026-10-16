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
    }

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

    func forecast(for stop: TripStop) -> Forecast? { forecasts[stop.place.coordinate.key] }
    func marine(for stop: TripStop) -> Marine? { marines[stop.place.coordinate.key] }

    func loadForecasts() async {
        let coordinates = Array(Set(stops.map(\.place.coordinate)))
        await withTaskGroup(of: (String, Forecast?, Marine?).self) { group in
            for c in coordinates {
                group.addTask {
                    let f = try? await OpenMeteo.forecast(c).value
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
