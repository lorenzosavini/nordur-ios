import Foundation
import UserNotifications
import BackgroundTasks

/// Background checks that raise local notifications for new orange/red IMO
/// warnings at your position or upcoming trip stops, and for good aurora nights.
enum Notifier {
    static let refreshTaskID = "it.lorenzosavini.nordur.refresh"

    enum Key {
        static let warnings = "notifyWarnings"
        static let includeYellow = "notifyYellowWarnings"
        static let aurora = "notifyAurora"
        static let notifiedWarnings = "notifiedWarningIDs"
        static let lastAuroraNight = "lastAuroraNotificationNight"
    }

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 45 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func runChecks() async {
        let defaults = UserDefaults.standard
        let wantsWarnings = defaults.bool(forKey: Key.warnings)
        let wantsAurora = defaults.bool(forKey: Key.aurora)
        guard wantsWarnings || wantsAurora else { return }

        let now = Date()
        let soon = now.addingTimeInterval(3 * 24 * 3600)
        var places = TripStore.loadFromDisk()
            .filter { $0.endDate >= now && $0.date <= soon }
            .map(\.place)
        places.insert(AppModel.monitoredPlace, at: 0)

        if wantsWarnings { await checkWarnings(places: places, includeYellow: defaults.bool(forKey: Key.includeYellow)) }
        if wantsAurora, let place = places.first { await checkAurora(place: place) }
    }

    private static func checkWarnings(places: [Place], includeYellow: Bool) async {
        guard let warnings = try? await IMO.warnings(), !warnings.isStale else { return }
        let defaults = UserDefaults.standard
        var notified = Set(defaults.stringArray(forKey: Key.notifiedWarnings) ?? [])
        let minimum: WarningColor = includeYellow ? .yellow : .orange
        for warning in warnings.value where warning.color >= minimum && !notified.contains(warning.id) {
            guard let place = places.first(where: { warning.covers($0.coordinate) }) else { continue }
            let when = Fmt.dayTime(warning.onset, in: .iceland)
            await post(
                id: warning.id,
                title: "\(warning.color.label): \(warning.headline)",
                body: "\(place.name) · \(warning.region) · dalle \(when)"
            )
            notified.insert(warning.id)
        }
        defaults.set(Array(notified.suffix(200)), forKey: Key.notifiedWarnings)
    }

    private static func checkAurora(place: Place) async {
        let night = Fmt.day(Date(), in: .iceland)
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Key.lastAuroraNight) != night else { return }
        guard let forecast = try? await OpenMeteo.forecast(place.coordinate).value,
              let kp = try? await SpaceWeather.kpForecast().value else { return }
        let outlook = AuroraCalc.outlook(forecast: forecast, kp: kp, ovation: nil)
        guard let best = outlook.best, best.score >= 45 else { return }
        await post(
            id: "aurora-\(night)",
            title: "Possibile aurora stanotte 🌌",
            body: "\(place.name): punteggio \(best.score)/100 verso le \(Fmt.time(best.date, in: forecast.timeZone)), nuvole \(Fmt.percent(best.cloudCover))."
        )
        defaults.set(night, forKey: Key.lastAuroraNight)
    }

    private static func post(id: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
