import Foundation

/// One plain answer to "do I go out?", from everything the app knows: the
/// aurora engine's hours here (activity × clouds × darkness × Moon), the solar
/// wind measured at L1 (it reaches the Earth 30–90 minutes later, so it tells
/// what is coming) and the best window of the night.
struct AuroraVerdict: Equatable {
    enum Level: Int, Comparable {
        case no, later, soon, now
        static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }
    }

    let level: Level
    let title: String
    let detail: String
    /// When it should start (soon) or the best moment (later).
    let at: Date?

    /// `darker`: a place near with better observability now (name, km), for when the
    /// aurora is on but cannot be seen from here (city lights, twilight).
    static func make(slots: [AuroraSlot], state: AuroraState?, zone: TimeZone, now: Date = Date(),
                     darker: (name: String, km: Double)? = nil) -> AuroraVerdict {
        let current = slots.first { abs($0.date.timeIntervalSince(now)) < 1800 } ?? slots.first
        let sw = state?.source("solarWind")?.isOK == true ? state?.solarWind : nil
        let bz15 = sw?.average(15)?.bz
        let south = sw?.bzSouth.continuousMinutes ?? 0
        let speed = sw?.average(15)?.v ?? sw?.latest.v
        let lead = sw?.propagation?.minutes ?? 45
        let look = current?.lookAzimuth.map { String(localized: " Guarda verso \(Fmt.compass($0)).") } ?? String(localized: " Guarda verso nord.")

        // 1. Now: it can be seen from here (observability at least moderate), with a clear sky.
        if let s = current, s.darkness >= .nautical, (s.clear ?? 0) >= 0.5, s.observability >= .moderate {
            return AuroraVerdict(level: .now, title: String(localized: "Esci adesso"),
                                 detail: String(localized: "Osservabilità \(s.observability.label.lowercased()): attività in corso e cielo \(Int(((s.clear ?? 0) * 100).rounded()))% sereno.") + look,
                                 at: now)
        }
        // 1b. Strong aurora shows through city lights and nautical twilight: the
        //     observability index rates the conditions, but a bright display still
        //     reads overhead and on the northern horizon, only less vivid.
        if let s = current, s.darkness >= .nautical, (s.clear ?? 0) >= 0.5,
           (s.ovationValue ?? 0) >= 30 || (s.kp ?? 0) >= 5 {
            let strength = s.ovationValue.map { "OVATION \(Int($0.rounded()))" } ?? "Kp \(Fmt.number(s.kp ?? 0, decimals: 1))"
            return AuroraVerdict(level: .now, title: String(localized: "Esci adesso: visibile anche da qui"),
                                 detail: String(localized: "Aurora forte (\(strength)) e cielo \(Int(((s.clear ?? 0) * 100).rounded()))% sereno: si vede anche con le luci e il crepuscolo, più bella lontano dalle luci.") + look,
                                 at: now)
        }
        // 1c. The aurora is on and the sky clear, but not strong enough to beat the
        //     light here (city lights, twilight, Moon): go somewhere darker.
        if let s = current, s.activityFactor >= 0.5, (s.clear ?? 0) >= 0.5 {
            let why = s.reasons.first.map { $0 + ". " } ?? ""
            let whereTo = darker.map { String(localized: "Più buio vicino: \($0.name), \(Int($0.km.rounded())) km.") }
                ?? String(localized: "Allontanati dalle luci della città, verso un posto buio con l'orizzonte libero a nord.")
            return AuroraVerdict(level: .soon, title: String(localized: "Aurora attiva: allontanati dalle luci"),
                                 detail: why + whereTo + look, at: now)
        }

        // 2. Soon: the solar wind on its way is geo-effective (Bz south for a while),
        //    and here it will be dark and clear enough when it arrives.
        let arrival = now.addingTimeInterval(lead * 60)
        let then = slots.first { abs($0.date.timeIntervalSince(arrival)) < 1800 } ?? current
        if let bz15, bz15 <= -5, south >= 15, (speed ?? 400) >= 380,
           let t = then, t.darkness >= .nautical, (t.clear ?? 0) >= 0.4 {
            let minutes = Int((lead / 5).rounded() * 5)
            return AuroraVerdict(level: .soon, title: String(localized: "Preparati: probabile tra ~\(minutes) min"),
                                 detail: String(localized: "Il vento solare in arrivo è favorevole (Bz \(Fmt.number(bz15, decimals: 0)) nT da \(south) min\(speed.map { ", \(Int($0)) km/s" } ?? "")). Verso le \(Fmt.time(arrival, in: zone)) qui sarà buio e sereno al \(Int(((t.clear ?? 0) * 100).rounded()))%.") + look,
                                 at: arrival)
        }

        // 3. Later tonight: the best hour of the next 12 with a fair chance.
        if let best = AuroraEngine.best(slots, within: 12, now: now), best.observability >= .moderate {
            return AuroraVerdict(level: .later, title: String(localized: "Stanotte, verso le \(Fmt.time(best.date, in: zone))"),
                                 detail: String(localized: "L'ora migliore: \(best.observability.label.lowercased()). Ti avviso quando è il momento: tieni attiva la sorveglianza aurora."),
                                 at: best.date)
        }

        // 4. No: the main reason, in words.
        let reason: String
        if let s = current, s.darkness < .nautical, let next = slots.first(where: { $0.date > now && $0.darkness >= .nautical }) {
            reason = String(localized: "È ancora chiaro: il buio arriva verso le \(Fmt.time(next.date, in: zone)).")
        } else if let s = current, (s.clear ?? 1) < 0.3 {
            reason = String(localized: "Cielo coperto: anche con l'aurora non si vedrebbe.")
        } else if let s = current, s.activityFactor < 0.25 {
            reason = String(localized: "Attività prevista debole nelle prossime ore.")
        } else {
            reason = current?.reasons.first ?? String(localized: "Condizioni sfavorevoli nelle prossime 12 ore.")
        }
        return AuroraVerdict(level: .no, title: String(localized: "Non adesso"), detail: reason, at: nil)
    }
}
