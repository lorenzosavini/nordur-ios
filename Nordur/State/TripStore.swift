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

    /// Saves a stop. When its arrival day changes, its attractions move with it
    /// (same times), and with `shiftingLater` the stops after it slide by the same days.
    func upsert(_ stop: TripStop, shiftingLater: Bool = false) {
        if let index = stops.firstIndex(where: { $0.id == stop.id }) {
            let old = stops[index]
            let shift = Self.dayShift(from: old.date, to: stop.date)
            var stop = stop
            if shift != 0 {
                stop.visits = stop.visits.map { $0.shifted(days: shift) }
                if shiftingLater {
                    for i in stops.indices where stops[i].id != stop.id && stops[i].date > old.date {
                        stops[i].date = Calendar.iceland.date(byAdding: .day, value: shift, to: stops[i].date) ?? stops[i].date
                        stops[i].visits = stops[i].visits.map { $0.shifted(days: shift) }
                    }
                }
            }
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

    /// Whole days between two dates, as days in Iceland.
    static func dayShift(from old: Date, to new: Date) -> Int {
        let calendar = Calendar.iceland
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: old), to: calendar.startOfDay(for: new)).day ?? 0
    }

    /// Moves an attraction to another day, of the same stop or of another one, keeping its time.
    func move(_ visit: TripVisit, from stopID: UUID, to targetID: UUID, day: Date) {
        guard let source = stops.firstIndex(where: { $0.id == stopID }),
              let target = stops.firstIndex(where: { $0.id == targetID }) else { return }
        stops[source].visits.removeAll { $0.id == visit.id }
        stops[target].visits.append(visit.moved(to: day))
        save()
    }

    /// Swaps two days of a stop: the attractions of one go to the other and back
    /// (with an empty day this simply moves the day).
    func swapDays(_ a: Date, _ b: Date, in stopID: UUID) {
        guard let index = stops.firstIndex(where: { $0.id == stopID }) else { return }
        let calendar = Calendar.iceland
        stops[index].visits = stops[index].visits.map { visit in
            if calendar.isDate(visit.date, inSameDayAs: a) { return visit.moved(to: b) }
            if calendar.isDate(visit.date, inSameDayAs: b) { return visit.moved(to: a) }
            return visit
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

// MARK: Import and export (GPX / KML)

extension TripStore {
    /// Builds stops and attractions from a file: stops in the file's order (or by
    /// date), each attraction under the stop whose days cover its date, or the
    /// nearest one, after what is already planned.
    func importItems(_ items: [TripFileItem], start: Date, replacing: Bool) {
        let calendar = Calendar.iceland
        var stopItems = items.filter(\.isStop)
        if stopItems.allSatisfy({ $0.date != nil }) { stopItems.sort { $0.date! < $1.date! } }
        var result: [TripStop] = replacing ? [] : stops
        var date = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: start) ?? start
        if !replacing, let last = stops.last { date = max(date, last.endDate) }
        var added: [TripStop] = []
        for (i, item) in stopItems.enumerated() {
            let arrival = item.date ?? date
            // Nights: given, else until the next dated stop, else one.
            var nights = item.nights ?? 1
            if item.nights == nil, let next = stopItems.dropFirst(i + 1).first?.date, let d = item.date {
                nights = max(0, Self.dayShift(from: d, to: next))
            }
            if i == stopItems.count - 1, item.nights == nil, item.date == nil { nights = max(nights, 1) }
            let place = Place(name: item.name, lat: item.lat, lon: item.lon, subtitle: nil)
            added.append(TripStop(place: place, date: arrival, nights: nights, notes: item.notes ?? ""))
            date = calendar.date(byAdding: .day, value: nights, to: arrival) ?? arrival
        }
        for item in items where !item.isStop {
            let c = Coordinate(lat: item.lat, lon: item.lon)
            let targets = added.isEmpty ? result : added
            guard !targets.isEmpty else { continue }
            // The day you move on belongs to the stop you arrive at (the sights on the way there).
            let byDate = item.date.flatMap { d in
                targets.firstIndex { calendar.isDate($0.date, inSameDayAs: d) } ?? targets.firstIndex { $0.includes(day: d) }
            }
            let index = byDate ?? targets.indices.min { Geo.distanceKm(targets[$0].place.coordinate, c) < Geo.distanceKm(targets[$1].place.coordinate, c) }!
            let known = Attraction.named(item.name)
            var visit = TripVisit.next(at: Place(name: item.name, lat: item.lat, lon: item.lon, subtitle: nil), kind: known?.kind,
                                       minutes: known?.minutes ?? 60, in: targets[index])
            if let d = item.date, targets[index].includes(day: d) { visit.date = d }
            visit.notes = item.notes ?? ""
            if added.isEmpty {
                if let r = result.firstIndex(where: { $0.id == targets[index].id }) { result[r].visits.append(visit) }
            } else {
                added[index].visits.append(visit)
            }
        }
        stops = result + added
        save()
    }

    /// The trip as GPX: stops and attractions as waypoints (with their times),
    /// and the stops again as a route, so other apps show the itinerary.
    func exportGPX() -> URL? {
        guard !stops.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Nordur" xmlns="http://www.topografix.com/GPX/1/1" xmlns:nordur="https://nordur-api.vercel.app/gpx">
          <metadata><name>Nordur – viaggio</name></metadata>

        """
        for stop in stops {
            xml += "  <wpt lat=\"\(stop.place.coordinate.lat)\" lon=\"\(stop.place.coordinate.lon)\"><name>\(esc(stop.place.name))</name>"
            xml += "<time>\(iso.string(from: stop.date))</time><desc>\(stop.nights) notti\(stop.notes.isEmpty ? "" : " · " + esc(stop.notes))</desc>"
            xml += "<sym>Lodging</sym><type>Tappa</type><extensions><nordur:nights>\(stop.nights)</nordur:nights></extensions></wpt>\n"
            for visit in stop.sortedVisits {
                xml += "  <wpt lat=\"\(visit.place.coordinate.lat)\" lon=\"\(visit.place.coordinate.lon)\"><name>\(esc(visit.place.name))</name>"
                xml += "<time>\(iso.string(from: visit.date))</time>\(visit.notes.isEmpty ? "" : "<desc>\(esc(visit.notes))</desc>")"
                xml += "<sym>Scenic Area</sym><type>Attrazione</type></wpt>\n"
            }
        }
        xml += "  <rte><name>Itinerario</name>\n"
        for stop in stops {
            xml += "    <rtept lat=\"\(stop.place.coordinate.lat)\" lon=\"\(stop.place.coordinate.lon)\"><name>\(esc(stop.place.name))</name><type>Tappa</type></rtept>\n"
        }
        xml += "  </rte>\n</gpx>\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Nordur-viaggio.gpx")
        do {
            try Data(xml.utf8).write(to: url, options: .atomic)
            return url
        } catch { return nil }
    }
}
