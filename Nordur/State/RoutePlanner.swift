import Foundation
import MapKit

/// A driving route with the weather expected along it and the live road picture.
struct RoutePlan {
    let from: Place
    let to: Place
    let departure: Date
    let polyline: [Coordinate]
    let distanceKm: Double
    let travelTime: TimeInterval
    let notices: [String]
    let waypoints: [RouteWaypointWeather]
    let stations: [RoadStation]
    let problemSegments: [RoadSegment]
    let webcams: [WebcamSite]
    let warnings: [WeatherWarning]
    let fuel: [FuelStation]

    var arrival: Date { departure.addingTimeInterval(travelTime) }
    var worstRisk: Risk {
        let weather = waypoints.map(\.risk).max() ?? .ok
        let roads = problemSegments.compactMap(\.risk).max() ?? .ok
        let warning = warnings.map(\.color.risk).max() ?? .ok
        return max(weather, roads, warning)
    }
}

@MainActor
enum RoutePlanner {
    enum PlanError: LocalizedError {
        case noRoute
        var errorDescription: String? { String(localized: "Nessun percorso stradale trovato tra questi luoghi.") }
    }

    static func plan(from: Place, to: Place, departure: Date, model: AppModel) async throws -> RoutePlan {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from.coordinate.clCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to.coordinate.clCoordinate))
        request.transportType = .automobile
        request.departureDate = departure
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw PlanError.noRoute }

        let mapPoints = route.polyline.points()
        let polyline = (0..<route.polyline.pointCount).map { Coordinate(mapPoints[$0].coordinate) }
        guard polyline.count >= 2, let lastPoint = polyline.last else { throw PlanError.noRoute }
        let samples = RouteWeather.sample(polyline, every: 25, departure: departure, travelTime: route.expectedTravelTime)
        let waypoints = (try? await RouteWeather.forecast(for: samples)) ?? samples.map { RouteWaypointWeather(sample: $0, hour: nil) }

        // Coarse copy of the line for proximity tests.
        let coarse = stride(from: 0, to: polyline.count, by: max(1, polyline.count / 400)).map { polyline[$0] } + [lastPoint]
        func distanceToRoute(_ c: Coordinate) -> Double {
            var best = Double.infinity
            for i in 1..<coarse.count {
                best = min(best, Geo.distanceToSegmentKm(c, coarse[i - 1], coarse[i]))
                if best < 0.5 { break }
            }
            return best
        }

        let network = model.roads?.value
        let stations = (network?.stations ?? []).filter { station in
            guard let c = station.coordinate, !station.isOutdated else { return false }
            return distanceToRoute(c) <= 8
        }
        var seen = Set<Int>()
        let problems = stations.flatMap { network?.segments(for: $0) ?? [] }
            .filter { ($0.risk ?? .ok) > .ok && seen.insert($0.id).inserted }
            .sorted { ($0.risk ?? .ok) > ($1.risk ?? .ok) }
        let webcams = (model.webcams?.value ?? []).filter { distanceToRoute($0.coordinate) <= 3 }
        let fuel = (model.fuel?.value ?? []).filter { $0.kind == .fuel && distanceToRoute($0.coordinate) <= 2 }
        let warnings = (model.warnings?.value ?? []).filter { warning in
            samples.contains { warning.covers($0.coordinate) && warning.overlaps($0.eta.addingTimeInterval(-1800), $0.eta.addingTimeInterval(1800)) }
        }

        return RoutePlan(
            from: from, to: to, departure: departure,
            polyline: polyline,
            distanceKm: route.distance / 1000,
            travelTime: route.expectedTravelTime,
            notices: route.advisoryNotices,
            waypoints: waypoints,
            stations: stations,
            problemSegments: problems,
            webcams: webcams,
            warnings: warnings,
            fuel: fuel
        )
    }

    static func openInMaps(from: Place, to: Place) {
        let origin = MKMapItem(placemark: MKPlacemark(coordinate: from.coordinate.clCoordinate))
        origin.name = from.name
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: to.coordinate.clCoordinate))
        destination.name = to.name
        MKMapItem.openMaps(with: [origin, destination], launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}
