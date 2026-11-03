import Foundation

/// What Veðurstofa Íslands published last, from nordur-api `/api/live` (checked
/// there at most once a minute for everyone): issue time of the station
/// forecasts, time of the latest hourly observation and 10-minute measurement,
/// a fingerprint of the written forecasts and the version of the corrected map
/// grid. The app fetches IMO data again exactly when one of these changes, not
/// on a timer; without the service it falls back to the usual freshness times.
enum IMOLive {
    struct Stamps: Decodable, Equatable {
        let forecast: String?
        let obsHour: String?
        let obs10: String?
        let texts: String?
        let grid: String?
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var stamps: Stamps?
        private var at: Date?

        /// Synchronous, so the lock is never held across an await.
        func read() -> (stamps: Stamps?, at: Date?) {
            lock.lock(); defer { lock.unlock() }
            return (stamps, at)
        }

        func write(_ new: Stamps) {
            lock.lock(); defer { lock.unlock() }
            stamps = new
            at = Date()
        }
    }
    private static let box = Box()

    static var current: Stamps? {
        let (stamps, at) = box.read()
        // An answer older than 10 minutes says nothing about now.
        guard let at, Date().timeIntervalSince(at) < 600 else { return nil }
        return stamps
    }

    /// Asks the service (at most every 50 seconds); nil when it does not answer.
    @discardableResult
    static func refresh(force: Bool = false) async -> Stamps? {
        let (cached, at) = box.read()
        let recent = at.map { Date().timeIntervalSince($0) < 50 } ?? false
        if recent && !force { return cached }
        guard let url = URL(string: "https://nordur-api.vercel.app/api/live"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let stamps = try? JSONDecoder().decode(Stamps.self, from: data) else { return nil }
        box.write(stamps)
        return stamps
    }

    /// The stamp an xmlweather answer of this type depends on.
    static func stamp(for type: String) -> String? {
        guard let s = current else { return nil }
        switch type {
        case "forec": return s.forecast
        case "obs": return s.obsHour.map { "\($0)|\(s.obs10 ?? "")" }
        case "txt": return s.texts
        default: return nil
        }
    }

    // The stamp each cached answer was fetched under.
    private static let defaults = UserDefaults.standard
    static func storedStamp(_ key: String) -> String? { defaults.string(forKey: "imo.stamp.\(key)") }
    static func store(_ stamp: String?, for key: String) { defaults.set(stamp, forKey: "imo.stamp.\(key)") }

    /// Whether a cached answer can be used: same stamp as IMO's latest publication
    /// (up to 6 hours), or — without stamps — younger than `fresh`.
    static func useCached(key: String, type: String, age: TimeInterval, fresh: TimeInterval) -> Bool {
        if let want = stamp(for: type) {
            return storedStamp(key) == want && age < 6 * 3600
        }
        return age < fresh
    }
}
