import Foundation
import UserNotifications

/// Tolls and paid parking around you while driving (drive recording, or the
/// position used by the background alerts):
/// - approaching a toll tunnel or road (within the distance set in the alerts,
///   10 km by default): what it costs, how to pay, the free alternative;
/// - after passing it (both gates within half an hour): "pay within 24 hours",
///   with the link, and a reminder a few hours before the window closes;
/// - arriving at a paid car park: about how much and how to pay.
/// The same toll or car park is notified once a day; the Live Activity shows
/// the toll ahead.
@MainActor
final class TollWatch {
    static let shared = TollWatch()

    /// The toll ahead for the Live Activity: name, km, price.
    struct Ahead: Equatable {
        let id: String
        let name: String
        let km: Double
        let price: String?
    }

    private(set) var ahead: Ahead?
    private var lastDistance: [String: Double] = [:]
    /// Gate index and time of the last fix near each gate, per toll.
    private var gateHits: [String: (index: Int, at: Date)] = [:]

    private init() {}

    private var entries: [TollEntry] { AlertCenter.shared.model?.tolls?.value ?? [] }

    private var enabled: Bool { Entitlements.shared.shows(.tolls) && AlertCenter.shared.settings.tolls }

    func handle(_ position: Coordinate, speedKmh: Double?, now: Date = Date()) {
        guard enabled, !entries.isEmpty else { ahead = nil; return }
        let radius = AlertCenter.shared.settings.tollRadiusKm
        var nearest: Ahead?
        for entry in entries where entry.isActive(at: now) {
            guard let km = entry.distanceKm(from: position) else { continue }
            if entry.isToll {
                let before = lastDistance[entry.id]
                lastDistance[entry.id] = km
                let approaching = before.map { km < $0 - 0.05 } ?? false
                if km <= radius, km > 0.4, approaching {
                    if nearest == nil || km < nearest!.km {
                        nearest = Ahead(id: entry.id, name: entry.name, km: km, price: entry.price()?.iskText)
                    }
                    notifyApproach(entry, km: km, now: now)
                }
                checkPassage(entry, position: position, now: now)
            } else if entry.isParking, km <= entry.areaKm, (speedKmh ?? 0) < 25 {
                notifyParking(entry, now: now)
            }
        }
        ahead = nearest
    }

    // MARK: Notifications

    private func dayStamp(_ date: Date) -> String {
        let c = Calendar.iceland.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func priceLine(_ entry: TollEntry) -> String? {
        guard let price = entry.price() else { return nil }
        var line = "\(price.iskText) \(price.unitLabel)"
        if let other = Tolls.converted(price.isk, rates: AlertCenter.shared.model?.rates?.value) { line += " (\(other))" }
        return line
    }

    private func notifyApproach(_ entry: TollEntry, km: Double, now: Date) {
        let text = entry.text
        var body: [String] = []
        if let price = priceLine(entry) { body.append(String(localized: "Circa \(price), prezzo indicativo.")) }
        if let payment = text.payment { body.append(payment) }
        if let window = text.window { body.append(window) }
        if let alternative = text.alternative { body.append(alternative) }
        let event = AlertEvent(
            id: "toll-near:\(entry.id):\(dayStamp(now))", date: now, category: .toll, severity: Risk.ok.rawValue,
            title: String(localized: "\(entry.kindLabel) tra \(Int(km.rounded())) km: \(entry.name)"),
            body: body.joined(separator: " "),
            coordinate: entry.coordinate, expires: now.addingTimeInterval(6 * 3600))
        AlertCenter.shared.record(event, notify: true, speak: false)
    }

    /// Through both gates within 45 minutes: a trip that must be paid.
    private func checkPassage(_ entry: TollEntry, position: Coordinate, now: Date) {
        let gates = entry.pointCoordinates
        guard gates.count >= 2, entry.windowAfterH != nil || entry.payUrl != nil else { return }
        guard let index = gates.indices.first(where: { Geo.distanceKm(position, gates[$0]) <= 0.6 }) else { return }
        if let hit = gateHits[entry.id], hit.index != index, now.timeIntervalSince(hit.at) < 45 * 60 {
            gateHits[entry.id] = nil
            notifyPassage(entry, now: now)
        } else {
            gateHits[entry.id] = (index, now)
        }
    }

    private func notifyPassage(_ entry: TollEntry, now: Date) {
        let hours = entry.windowAfterH ?? 24
        let deadline = now.addingTimeInterval(Double(hours) * 3600)
        let text = entry.text
        var body: [String] = []
        if let price = priceLine(entry) { body.append(String(localized: "Circa \(price), prezzo indicativo.")) }
        body.append(String(localized: "Scadenza: \(Fmt.dayTime(deadline, in: .Iceland))."))
        if let payment = text.payment { body.append(payment) }
        if let rental = text.rental { body.append(rental) }
        let id = "toll-paid:\(entry.id):\(Int(now.timeIntervalSince1970 / 3600))"
        let event = AlertEvent(
            id: id, date: now, category: .toll, severity: Risk.caution.rawValue,
            title: String(localized: "Paga \(entry.name) entro \(hours) ore"),
            body: body.joined(separator: " "),
            coordinate: entry.coordinate, expires: deadline)
        AlertCenter.shared.record(event, notify: true, speak: AlertCenter.shared.settings.spoken)
        scheduleReminder(entry, eventID: id, deadline: deadline, now: now)
    }

    /// A second nudge four hours before the window closes (if still within it).
    private func scheduleReminder(_ entry: TollEntry, eventID: String, deadline: Date, now: Date) {
        let at = deadline.addingTimeInterval(-4 * 3600)
        guard at > now.addingTimeInterval(600) else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Promemoria: pedaggio \(entry.name)")
        content.subtitle = AlertCategory.toll.shortLabel
        content.body = String(localized: "Se non l'hai già fatto, paga entro le \(Fmt.time(deadline, in: .Iceland)): \(entry.payUrl ?? entry.sourceUrl)")
        content.sound = .default
        content.threadIdentifier = AlertCategory.toll.rawValue
        content.userInfo = ["alertID": eventID]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: at.timeIntervalSince(now), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: eventID + ":reminder", content: content, trigger: trigger))
    }

    private func notifyParking(_ entry: TollEntry, now: Date) {
        let text = entry.text
        var body: [String] = []
        if let payment = text.payment { body.append(payment) }
        if let window = text.window { body.append(window) }
        let title: String
        if let price = priceLine(entry) {
            title = String(localized: "Parcheggio a pagamento, circa \(price)")
        } else {
            title = String(localized: "Parcheggio a pagamento: verifica il prezzo sul posto")
        }
        let event = AlertEvent(
            id: "toll-park:\(entry.id):\(dayStamp(now))", date: now, category: .toll, severity: Risk.ok.rawValue,
            title: "\(entry.name) · \(title)",
            body: body.joined(separator: " "),
            coordinate: entry.coordinate, expires: now.addingTimeInterval(12 * 3600))
        AlertCenter.shared.record(event, notify: true, speak: false)
    }

    /// The toll entry an alert is about ("toll-near:<id>:…").
    static func entryID(of event: AlertEvent) -> String? {
        let parts = event.id.split(separator: ":")
        guard parts.count >= 2, parts[0].hasPrefix("toll-") else { return nil }
        return String(parts[1])
    }
}
