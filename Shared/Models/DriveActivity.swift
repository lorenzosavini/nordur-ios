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
    }

    var name: String
    var start: Date
}
#endif
