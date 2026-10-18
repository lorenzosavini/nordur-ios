import CoreLocation
import Foundation
import HealthKit

/// Activities from Apple Health: Garmin Connect, Apple Watch, Strava, Polar,
/// Suunto… write their workouts (with the GPS route and heart rate) there, and
/// Norður imports the ones you pick into the history of routes. Read only.
@MainActor
final class HealthImport {
    static let shared = HealthImport()
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    struct Workout: Identifiable {
        let workout: HKWorkout
        var id: String { workout.uuid.uuidString }
        var activity: String { HealthImport.activityName(workout.workoutActivityType) }
        var symbol: String { HealthImport.activitySymbol(workout.workoutActivityType) }
        var source: String { HealthImport.sourceName(workout.sourceRevision.source) }
        var km: Double? { workout.totalDistance.map { $0.doubleValue(for: .meter()) / 1000 } }
    }

    private var readTypes: Set<HKObjectType> {
        [HKObjectType.workoutType(), HKSeriesType.workoutRoute(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
    }

    func requestAccess() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Workouts of the last `days` days, newest first.
    func recentWorkouts(days: Int = 120) async throws -> [Workout] {
        try await requestAccess()
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: since, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 200)
        return try await descriptor.result(for: store).map(Workout.init)
    }

    /// The workout as a Norður route (GPS points, statistics, heart rate, energy).
    func session(for item: Workout) async throws -> DriveSession {
        let workout = item.workout
        let locations = try await route(of: workout)
        let points = locations.map { loc in
            TrackPoint(t: loc.timestamp, lat: loc.coordinate.latitude, lon: loc.coordinate.longitude,
                       alt: loc.verticalAccuracy >= 0 ? loc.altitude : nil, speed: loc.speed,
                       course: loc.course >= 0 ? loc.course : nil, accuracy: max(0, loc.horizontalAccuracy))
        }
        let name = "\(item.activity) · \(Fmt.dayTime(workout.startDate))"
        var session = DriveMath.imported(name: name, points: points, start: workout.startDate, end: workout.endDate)
        // The device's own totals are more accurate than the recomputed ones.
        if let meters = workout.totalDistance?.doubleValue(for: .meter()), meters > 0 { session.stats.distanceMeters = meters }
        session.pausedSeconds = max(0, workout.endDate.timeIntervalSince(workout.startDate) - workout.duration)
        if session.stats.movingSeconds == 0 { session.stats.movingSeconds = workout.duration }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let heart = workout.statistics(for: HKQuantityType(.heartRate))
        session.heartRateAvg = heart?.averageQuantity()?.doubleValue(for: bpm)
        session.heartRateMax = heart?.maximumQuantity()?.doubleValue(for: bpm)
        session.energyKcal = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        session.source = item.source
        session.activity = item.activity
        session.importID = "health:\(item.id)"
        return session
    }

    private func route(of workout: HKWorkout) async throws -> [CLLocation] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workout))],
            sortDescriptors: [])
        var all: [CLLocation] = []
        for case let route as HKWorkoutRoute in try await descriptor.result(for: store) {
            all += try await locations(route)
        }
        return all.sorted { $0.timestamp < $1.timestamp }
    }

    private func locations(_ route: HKWorkoutRoute) async throws -> [CLLocation] {
        // HealthKit delivers the points in batches, on its own queue.
        final class Batches: @unchecked Sendable {
            let lock = NSLock()
            var points: [CLLocation] = []
            var finished = false
        }
        let batches = Batches()
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKWorkoutRouteQuery(route: route) { _, batch, done, error in
                batches.lock.lock()
                defer { batches.lock.unlock() }
                guard !batches.finished else { return }
                if let error {
                    batches.finished = true
                    continuation.resume(throwing: error)
                    return
                }
                batches.points += batch ?? []
                if done {
                    batches.finished = true
                    continuation.resume(returning: batches.points)
                }
            }
            store.execute(query)
        }
    }

    // MARK: Names

    nonisolated private static func sourceName(_ source: HKSource) -> String {
        let bundle = source.bundleIdentifier.lowercased()
        if bundle.contains("garmin") { return "Garmin Connect" }
        if bundle.hasPrefix("com.apple.health") { return "Apple Watch" }
        if bundle.contains("strava") { return "Strava" }
        if bundle.contains("polar") { return "Polar" }
        if bundle.contains("suunto") { return "Suunto" }
        if bundle.contains("komoot") { return "Komoot" }
        return source.name
    }

    nonisolated static func activityName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return String(localized: "Corsa")
        case .walking: return String(localized: "Camminata")
        case .hiking: return String(localized: "Escursione")
        case .cycling: return String(localized: "Bici")
        case .crossCountrySkiing: return String(localized: "Sci di fondo")
        case .downhillSkiing: return String(localized: "Sci")
        case .snowboarding: return String(localized: "Snowboard")
        case .swimming: return String(localized: "Nuoto")
        case .paddleSports: return String(localized: "Kayak e canoa")
        case .climbing: return String(localized: "Arrampicata")
        case .equestrianSports: return String(localized: "Equitazione")
        default: return String(localized: "Attività")
        }
    }

    nonisolated static func activitySymbol(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .hiking: return "figure.hiking"
        case .cycling: return "figure.outdoor.cycle"
        case .crossCountrySkiing: return "figure.skiing.crosscountry"
        case .downhillSkiing: return "figure.skiing.downhill"
        case .snowboarding: return "figure.snowboarding"
        case .swimming: return "figure.pool.swim"
        case .paddleSports: return "figure.outdoor.rowing"
        case .climbing: return "figure.climbing"
        case .equestrianSports: return "figure.equestrian.sports"
        default: return "figure.mixed.cardio"
        }
    }
}
