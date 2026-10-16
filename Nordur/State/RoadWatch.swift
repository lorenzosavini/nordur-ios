import Foundation
import Observation
import MapKit

/// One road weather station on the road ahead.
struct AheadItem: Identifiable {
    let station: RoadStation
    let kmAhead: Double
    let etaMinutes: Int
    let segments: [RoadSegment]
    let risk: Risk
    let webcam: WebcamSite?
    var id: Int { station.id }
}

/// Live picture of the road you are driving: stations and segments ahead
/// (along the planned route if a destination is set, otherwise in the
/// direction of travel), refreshed every few minutes while recording, with
/// alerts when something ahead gets worse.
@MainActor
@Observable
final class RoadWatch {
    static let shared = RoadWatch()

    private(set) var destination: Place?
    private(set) var route: [Coordinate] = []
    private(set) var routeKm: [Double] = []
    private(set) var routeTotalKm: Double = 0
    private(set) var routeTravelTime: TimeInterval = 0
    private(set) var remainingKm: Double?
    private(set) var ahead: [AheadItem] = []
    private(set) var warningsAhead: [WeatherWarning] = []
    private(set) var lastUpdate: Date?
    private(set) var lastRoadsFetch: Date?
    private(set) var isPlanning = false
    private(set) var planError: String?
    private(set) var changes: [String] = []

    @ObservationIgnored private var network: RoadNetwork?
    @ObservationIgnored private var lastIndex = 0
    @ObservationIgnored private var previousSegmentRisk: [Int: Risk] = [:]
    @ObservationIgnored private var stationRouteKm: [Int: Double] = [:]
    @ObservationIgnored private var lastCompute = Date.distantPast

    static let lookaheadKm = 150.0

    var nextHazard: AheadItem? { ahead.first { $0.risk >= .warning } }

    // MARK: Destination / route

    func setDestination(_ place: Place?, from start: Coordinate?) async {
        destination = place
        route = []; routeKm = []; routeTotalKm = 0; stationRouteKm = [:]; lastIndex = 0
        planError = nil
        guard let place, let start else { await refresh(position: start, course: nil, speedKmh: 0, force: true); return }
        isPlanning = true
        defer { isPlanning = false }
        do {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: start.clCoordinate))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate.clCoordinate))
            request.transportType = .automobile
            let response = try await MKDirections(request: request).calculate()
            guard let r = response.routes.first else { throw RoutePlanner.PlanError.noRoute }
            let points = r.polyline.points()
            let coords = (0..<r.polyline.pointCount).map { Coordinate(points[$0].coordinate) }
            // Keep ~1 point every 300 m: enough precision, cheap to scan.
            var thinned: [Coordinate] = []
            for c in coords where thinned.last.map({ Geo.distanceKm($0, c) >= 0.3 }) ?? true { thinned.append(c) }
            if let last = coords.last, thinned.last != last { thinned.append(last) }
            route = thinned
            var km: [Double] = [0]
            for i in 1..<max(thinned.count, 1) { km.append(km[i - 1] + Geo.distanceKm(thinned[i - 1], thinned[i])) }
            routeKm = km
            routeTotalKm = km.last ?? 0
            routeTravelTime = r.expectedTravelTime
        } catch {
            planError = error.localizedDescription
        }
        await refresh(position: start, course: nil, speedKmh: 0, force: true)
    }

    // MARK: Updates

    /// Called by the recorder on every fix; recomputes at most every 20 s and
    /// refetches road data every 5 minutes.
    func refresh(position: Coordinate?, course: Double?, speedKmh: Double, force: Bool = false) async {
        let now = Date()
        guard force || now.timeIntervalSince(lastCompute) >= 20, let position else { return }
        lastCompute = now

        if force || network == nil || now.timeIntervalSince(lastRoadsFetch ?? .distantPast) >= 5 * 60 {
            if let fresh = try? await Roads.network() {
                network = fresh.value
                lastRoadsFetch = now
                AlertCenter.shared.model?.roads = fresh
                stationRouteKm = [:]
            } else if network == nil {
                network = AlertCenter.shared.model?.roads?.value
            }
        }
        guard let network else { return }

        let model = AlertCenter.shared.model
        let webcams = model?.webcams?.value ?? []
        let speed = max(speedKmh, 50)
        var items: [AheadItem] = []

        if route.count >= 2 {
            let currentKm = progressKm(at: position)
            remainingKm = max(0, routeTotalKm - currentKm)
            if stationRouteKm.isEmpty { stationRouteKm = mapStationsToRoute(network) }
            for station in network.stations where !station.isOutdated {
                guard let km = stationRouteKm[station.id] else { continue }
                let delta = km - currentKm
                guard delta > -0.5, delta <= Self.lookaheadKm else { continue }
                items.append(item(station, kmAhead: max(0, delta), speed: speed, network: network, webcams: webcams))
            }
            let aheadPoints = route.indices.filter { routeKm[$0] >= currentKm && routeKm[$0] <= currentKm + Self.lookaheadKm }
                .enumerated().filter { $0.offset % 10 == 0 }.map { route[$0.element] }
            warningsAhead = (model?.warnings?.value ?? []).filter { w in w.isActive() && aheadPoints.contains { w.covers($0) } }
        } else {
            remainingKm = nil
            for station in network.stations where !station.isOutdated {
                guard let c = station.coordinate else { continue }
                let km = Geo.distanceKm(position, c)
                guard km <= 60 else { continue }
                if let course, speedKmh > 15 {
                    // In front of us: within ±40° of the heading (or right here).
                    let diff = abs(angleDifference(bearing(position, c), course))
                    guard km < 1.5 || diff <= 40 else { continue }
                }
                items.append(item(station, kmAhead: km, speed: speed, network: network, webcams: webcams))
            }
            warningsAhead = (model?.warnings?.value ?? []).filter { $0.isActive() && $0.covers(position) }
        }
        items.sort { $0.kmAhead < $1.kmAhead }
        ahead = Array(items.prefix(12))
        lastUpdate = now
        detectChanges()
    }

    func clear() {
        ahead = []
        warningsAhead = []
        remainingKm = nil
        previousSegmentRisk = [:]
        changes = []
    }

    private func item(_ station: RoadStation, kmAhead: Double, speed: Double, network: RoadNetwork, webcams: [WebcamSite]) -> AheadItem {
        let webcam = station.coordinate.flatMap { Webcams.nearest(webcams, to: $0, within: 3, limit: 1).first }
        return AheadItem(station: station, kmAhead: kmAhead, etaMinutes: Int((kmAhead / speed * 60).rounded()),
                         segments: network.segments(for: station), risk: network.worstRisk(of: station), webcam: webcam)
    }

    /// Notifies when a segment ahead gets worse or strong gusts are coming up.
    private func detectChanges() {
        let settings = AlertCenter.shared.settings
        for item in ahead {
            for segment in item.segments {
                let risk = segment.risk ?? .ok
                let before = previousSegmentRisk[segment.id]
                previousSegmentRisk[segment.id] = risk
                guard risk >= .caution, before == nil || risk > (before ?? .ok) else { continue }
                // First sighting of a hazard only matters if it is serious; worsening always matters.
                if before == nil && risk < .warning { continue }
                let what = before == nil ? segment.conditionItalian : "peggiorata: \(segment.conditionItalian)"
                let note = "Tra \(Int(item.kmAhead)) km (\(item.etaMinutes) min): \(segment.name) – \(what)"
                changes.insert("\(Fmt.time(Date())) \(note)", at: 0)
                AlertCenter.shared.record(AlertEvent(
                    id: "rw:\(segment.id):\(segment.AstandYfirbord ?? "")", date: Date(), category: .road, severity: risk.rawValue,
                    title: "Strada davanti: \(segment.conditionItalian)",
                    body: note, coordinate: item.station.coordinate), notify: true, speak: settings.spoken)
            }
            if let gust = item.station.Vindhvida, gust >= settings.gustThreshold, item.kmAhead <= 60 {
                let bucket = Int(Date().timeIntervalSince1970 / 3600)
                let note = "Raffiche \(Fmt.ms(gust)) a \(item.station.name) tra \(Int(item.kmAhead)) km (\(item.etaMinutes) min)"
                if !changes.contains(where: { $0.hasSuffix(note) }) { changes.insert("\(Fmt.time(Date())) \(note)", at: 0) }
                AlertCenter.shared.record(AlertEvent(
                    id: "rwg:\(item.station.id):\(bucket)", date: Date(), category: .wind, severity: item.station.windRisk.rawValue,
                    title: "Vento forte sulla strada davanti", body: note, coordinate: item.station.coordinate),
                    notify: true, speak: settings.spoken)
            }
        }
        if changes.count > 30 { changes = Array(changes.prefix(30)) }
    }

    // MARK: Geometry

    private func progressKm(at position: Coordinate) -> Double {
        // Search forward from the last match first (we rarely drive backwards).
        var bestIndex = lastIndex, best = Double.infinity
        let window = max(0, lastIndex - 20)..<min(route.count, lastIndex + 400)
        for i in window {
            let d = Geo.distanceKm(route[i], position)
            if d < best { best = d; bestIndex = i }
        }
        if best > 2 {
            for i in route.indices {
                let d = Geo.distanceKm(route[i], position)
                if d < best { best = d; bestIndex = i }
            }
        }
        lastIndex = bestIndex
        return routeKm.indices.contains(bestIndex) ? routeKm[bestIndex] : 0
    }

    private func mapStationsToRoute(_ network: RoadNetwork) -> [Int: Double] {
        var result: [Int: Double] = [:]
        let step = max(1, route.count / 1500)
        for station in network.stations {
            guard let c = station.coordinate else { continue }
            var best = Double.infinity, bestKm = 0.0
            for i in stride(from: 0, to: route.count, by: step) {
                let d = Geo.distanceKm(route[i], c)
                if d < best { best = d; bestKm = routeKm[i] }
            }
            if best <= 6 { result[station.id] = bestKm }
        }
        return result
    }

    private func bearing(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.lat * .pi / 180, lat2 = b.lat * .pi / 180
        let dLon = (b.lon - a.lon) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private func angleDifference(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }
}
