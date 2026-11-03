#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity shown on the Lock Screen and Dynamic Island while recording a drive.
struct DriveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var km: Double
        var elapsedSeconds: Double
        var speedKmh: Double
        var averageKmh: Double
        var odometer: Double?
        var paused: Bool
        /// Latest alert raised during the drive (gusts, closures, warnings…).
        var alertTitle: String?
        var alertSeverity: Int
        var updated: Date
        /// Next stop: the destination set in the drive screen, or today's trip stop.
        var nextStopName: String?
        var remainingKm: Double?
        var eta: Date?
        /// Next fuel station on the route (or roughly ahead), straight-line distance.
        var fuelName: String?
        var fuelKm: Double?
        /// Toll tunnel or road ahead (within the distance set in the alerts), with its price.
        var tollName: String?
        var tollKm: Double?
        var tollPrice: String?
    }

    var name: String
    var start: Date
}
#endif
