import Foundation
import Observation
import StoreKit

/// What can be sold. The keys are the ones the admin panel lists
/// (backend/lib/features.js): each is free, Pro or off as the backend says.
/// Safety (weather and road warnings, closures, earthquakes, SOS) is never here.
enum Feature: String, CaseIterable, Identifiable {
    case auroraAlerts = "aurora.alerts"
    case auroraFinder = "aurora.finder"
    case auroraLive = "aurora.live"
    case auroraReport = "aurora.report"
    case weatherMap = "weather.map"
    case webcams
    case tripPlanner = "trip.planner"
    case tripShared = "trip.shared"
    case tripFiles = "trip.files"
    case driveRecord = "drive.record"
    case driveFlight3D = "drive.flight3d"
    case driveHealth = "drive.health"
    case offline
    case backup
    case currencyConverter = "currency.converter"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auroraAlerts: return String(localized: "Notifiche aurora")
        case .auroraFinder: return String(localized: "Bussola dell'aurora")
        case .auroraLive: return String(localized: "Mappa dell'ovale e avvistamenti")
        case .auroraReport: return String(localized: "Inviare avvistamenti")
        case .weatherMap: return String(localized: "Mappa meteo a strati")
        case .webcams: return String(localized: "Webcam stradali")
        case .tripPlanner: return String(localized: "Pianificatore di viaggio")
        case .tripShared: return String(localized: "Viaggi condivisi e di gruppo")
        case .tripFiles: return String(localized: "Import ed export GPX / KML")
        case .driveRecord: return String(localized: "Registrazione dei percorsi in auto")
        case .driveFlight3D: return String(localized: "Volo 3D e video del percorso")
        case .driveHealth: return String(localized: "Import da Apple Salute / Garmin")
        case .offline: return String(localized: "Pacchetto offline")
        case .backup: return String(localized: "Backup sul cloud")
        case .currencyConverter: return String(localized: "Convertitore valute")
        }
    }

    var symbol: String {
        switch self {
        case .auroraAlerts: return "bell.badge"
        case .auroraFinder: return "location.north.line"
        case .auroraLive: return "map"
        case .auroraReport: return "eye"
        case .weatherMap: return "square.3.layers.3d"
        case .webcams: return "video"
        case .tripPlanner: return "map.circle"
        case .tripShared: return "person.2"
        case .tripFiles: return "doc.badge.arrow.up"
        case .driveRecord: return "record.circle"
        case .driveFlight3D: return "mountain.2"
        case .driveHealth: return "heart.text.square"
        case .offline: return "arrow.down.circle"
        case .backup: return "icloud.and.arrow.up"
        case .currencyConverter: return "arrow.left.arrow.right.circle"
        }
    }
}

/// Who may use what: the rules from the backend (free / Pro / off for each
/// feature), the App Store purchases (StoreKit 2, verified by Apple on the
/// phone), Pro given from the admin panel to an account, and buyers of the
/// app when it was sold at a price.
///
/// Until the backend says otherwise everything is free, offline too: the last
/// rules received are kept, and an unreachable backend never locks anything new.
@MainActor
@Observable
final class Entitlements {
    static let shared = Entitlements()

    struct Config: Codable, Equatable {
        var mode: String = "free"
        var features: [String: String] = [:]
        var products: [String] = []
        var paidThroughBuild: Int?
        var paywall: [String: Copy]? = [:]
        var announcement: Announcement?
        var updatedAt: String?

        struct Copy: Codable, Equatable { var title: String?; var text: String? }
        struct Announcement: Codable, Equatable, Identifiable {
            var id: String
            var level: String
            var from: String?
            var until: String?
            var url: String?
            var texts: [String: Copy]
        }
    }

    private(set) var config: Config
    private(set) var products: [Product] = []
    /// Product IDs bought and still valid (a subscription not expired, a purchase not refunded).
    private(set) var purchased: Set<String> = []
    /// Pro given by the admin to the signed-in account.
    private(set) var granted = false
    private(set) var grantedUntil: Date?
    /// Bought the app when it had a price (original build up to `paidThroughBuild`).
    private(set) var earlyBuyer = false
    private(set) var purchasing = false
    var lastError: String?
    /// The feature whose purchase screen is showing (set by `check`).
    var paywall: Feature?

    private static let configKey = "entitlements.config"
    private static let grantKey = "entitlements.grant"
    @ObservationIgnored private var updates: Task<Void, Never>?

    private init() {
        config = (UserDefaults.standard.data(forKey: Self.configKey)).flatMap { try? JSONDecoder().decode(Config.self, from: $0) } ?? Config()
        granted = UserDefaults.standard.bool(forKey: Self.grantKey)
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let t) = update { await t.finish() }
                await self?.refreshPurchases()
            }
        }
    }

    var isPro: Bool { !purchased.isEmpty || granted || earlyBuyer }
    var sellsPro: Bool { config.mode == "freemium" }

    enum Rule: String { case free, pro, off }

    func rule(_ feature: Feature) -> Rule {
        guard config.mode == "freemium" else { return .free }
        return Rule(rawValue: config.features[feature.rawValue] ?? "free") ?? .free
    }

    /// The feature can be used now.
    func allows(_ feature: Feature) -> Bool {
        switch rule(feature) {
        case .free: return true
        case .pro: return isPro
        case .off: return false
        }
    }

    /// The feature is part of the app (not switched off for everyone).
    func shows(_ feature: Feature) -> Bool { rule(feature) != .off }

    /// Needs Pro and Pro isn't there yet: the lock is shown next to it.
    func locked(_ feature: Feature) -> Bool { rule(feature) == .pro && !isPro }

    /// For actions: true when allowed, otherwise the purchase screen opens.
    @discardableResult
    func check(_ feature: Feature) -> Bool {
        if allows(feature) { return true }
        if rule(feature) == .pro { paywall = feature }
        return false
    }

    /// For code running in the background (notifications), from the last state saved.
    nonisolated static func allowsInBackground(_ feature: Feature) -> Bool {
        let blocked = UserDefaults.standard.stringArray(forKey: "entitlements.blocked") ?? []
        return !blocked.contains(feature.rawValue)
    }

    private func saveBackgroundState() {
        UserDefaults.standard.set(Feature.allCases.filter { !allows($0) }.map(\.rawValue), forKey: "entitlements.blocked")
    }

    var proFeatures: [Feature] { Feature.allCases.filter { rule($0) == .pro } }

    func paywallText(_ key: KeyPath<Config.Copy, String?>) -> String? {
        let texts = config.paywall ?? [:]
        let value = texts[UILanguage.code]?[keyPath: key] ?? texts["en"]?[keyPath: key] ?? texts["it"]?[keyPath: key]
        return value?.isEmpty == false ? value : nil
    }

    // MARK: Loading

    /// Rules from the backend, the products from the App Store, the purchases and the account's grant.
    func refresh() async {
        await loadConfig()
        await loadProducts()
        await refreshPurchases()
        await refreshEarlyBuyer()
        await refreshGrant()
        saveBackgroundState()
    }

    /// The rules and the notice from the backend (also every few minutes while the app is open).
    func loadConfig() async {
        var components = URLComponents(url: Account.api.appendingPathComponent("health"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "config", value: "1")]
        guard let url = components.url else { return }
        do {
            let (data, response) = try await HTTP.session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let next = try JSONDecoder().decode(Config.self, from: data)
            if next != config {
                config = next
                UserDefaults.standard.set(data, forKey: Self.configKey)
                saveBackgroundState()
            }
            notifyNotice()
        } catch {
            // Offline: the last rules stay.
        }
    }

    /// A new notice from the admin panel also arrives as a notification and in the alerts inbox, once.
    private func notifyNotice() {
        guard let n = announcement else { return }
        var notified = UserDefaults.standard.stringArray(forKey: "entitlements.notifiedNotices") ?? []
        guard !notified.contains(n.id) else { return }
        notified = Array((notified + [n.id]).suffix(30))
        UserDefaults.standard.set(notified, forKey: "entitlements.notifiedNotices")
        let risk: Risk = n.level == "danger" ? .danger : n.level == "warning" ? .warning : .caution
        let until = config.announcement?.until.flatMap(Self.date)
        AlertCenter.shared.record(AlertEvent(id: "notice:\(n.id)", date: Date(), category: .notice, severity: risk.rawValue, title: n.title, body: n.text, expires: until),
                                  notify: true, speak: false)
    }

    private func loadProducts() async {
        guard !config.products.isEmpty else { products = []; return }
        do {
            let found = try await Product.products(for: config.products)
            products = config.products.compactMap { id in found.first { $0.id == id } }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshPurchases() async {
        var owned: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil { owned.insert(t.productID) }
        }
        purchased = owned
        saveBackgroundState()
    }

    /// Apple keeps the build of the first download: whoever bought the app when
    /// it had a price keeps everything after it becomes free with Pro.
    private func refreshEarlyBuyer() async {
        guard let limit = config.paidThroughBuild else { earlyBuyer = false; return }
        guard let result = try? await AppTransaction.shared, case .verified(let app) = result else { return }
        if let build = Int(app.originalAppVersion) { earlyBuyer = build <= limit }
    }

    private func refreshGrant() async {
        guard let status = await Account.shared.status() else { return }
        granted = status.pro
        grantedUntil = status.proUntil.flatMap(Self.date)
        UserDefaults.standard.set(granted, forKey: Self.grantKey)
    }

    // MARK: Buying

    func buy(_ product: Product) async {
        purchasing = true
        defer { purchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let t) = verification { await t.finish() }
                await refreshPurchases()
                if isPro { paywall = nil }
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// "Ripristina acquisti": asks the App Store again (it may ask for the Apple ID password).
    func restore() async {
        purchasing = true
        defer { purchasing = false }
        try? await AppStore.sync()
        await refreshPurchases()
        await refreshEarlyBuyer()
        await refreshGrant()
        if isPro { paywall = nil }
    }

    // MARK: Notice

    /// The backend's dates ("2026-10-25T18:00:00.000Z").
    static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    /// The notice from the admin panel, live and not closed on this phone.
    var announcement: (id: String, level: String, title: String, text: String, url: URL?)? {
        guard let a = config.announcement else { return nil }
        let now = Date()
        if let from = a.from.flatMap(Self.date), from > now { return nil }
        if let until = a.until.flatMap(Self.date), until <= now { return nil }
        guard !closedNotices.contains(a.id) else { return nil }
        let t = a.texts[UILanguage.code] ?? a.texts["en"] ?? a.texts["it"] ?? a.texts.values.first
        guard let title = t?.title, !title.isEmpty else { return nil }
        return (a.id, a.level, title, t?.text ?? "", a.url.flatMap(URL.init(string:)))
    }

    private(set) var closedNotices: [String] = UserDefaults.standard.stringArray(forKey: "entitlements.closedNotices") ?? []

    func closeNotice(_ id: String) {
        closedNotices = Array((closedNotices + [id]).suffix(30))
        UserDefaults.standard.set(closedNotices, forKey: "entitlements.closedNotices")
    }
}
