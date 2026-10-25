import Foundation

/// When an alert found by the engine becomes a notification. An alert has a
/// life: it appears, may get worse or start earlier, and ends. Only the first
/// two are worth a banner; the same alert seen again (after a move of a few
/// kilometres, on reopening the app, with a reworded update) goes quietly in
/// the inbox, replacing its previous version.
enum AlertLifecycle {
    enum Decision: Equatable {
        /// Already handled under this exact key.
        case skip
        /// New, worse than before, or starting earlier: a notification.
        case notify
        /// Same alert, no worse: the inbox entry is updated, no banner.
        case quiet
    }

    /// The last version notified of an alert (its group): how bad it was and when it started.
    struct Seen: Codable, Equatable {
        var severity: Int
        var starts: Date?
        var at: Date
    }

    /// A group is remembered this long after its last sighting: an alert that
    /// comes back after a quiet day and a half is new again.
    static let memory: TimeInterval = 36 * 3600

    static func decide(id: String, group: String, severity: Int, starts: Date?,
                       fired: [String: Date], seen: [String: Seen], now: Date) -> Decision {
        if fired[id] != nil { return .skip }
        guard let last = seen[group], now.timeIntervalSince(last.at) < memory else { return .notify }
        if severity > last.severity { return .notify }
        if let starts, let before = last.starts, starts < before.addingTimeInterval(-3600) { return .notify }
        return .quiet
    }

    /// How a notification sounds. At night (22:30–07:00 on the phone's clock) only
    /// danger keeps its sound and breaks through Focus; orange arrives silently,
    /// the rest is delivered quietly to the notification centre.
    struct Delivery: Equatable {
        var sound: Bool
        var urgent: Bool
        var passive: Bool
    }

    static func delivery(risk: Int, at date: Date, quietNights: Bool, calendar: Calendar = .current) -> Delivery {
        let danger = 3, warning = 2
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let night = quietNights && (minutes >= 22 * 60 + 30 || minutes < 7 * 60)
        if !night { return Delivery(sound: true, urgent: risk >= warning, passive: false) }
        if risk >= danger { return Delivery(sound: true, urgent: true, passive: false) }
        if risk >= warning { return Delivery(sound: false, urgent: false, passive: false) }
        return Delivery(sound: false, urgent: false, passive: true)
    }

    /// The three parts of the inbox.
    enum Phase: Int, CaseIterable { case now, upcoming, ended }

    /// Ended when past its end, or a day old without one (a closure, a quake);
    /// upcoming while it has not started yet.
    static func phase(starts: Date?, expires: Date?, noticed: Date, now: Date) -> Phase {
        if let expires { if expires <= now { return .ended } } else if now.timeIntervalSince(noticed) > 24 * 3600 { return .ended }
        if let starts, starts > now { return .upcoming }
        return .now
    }
}
