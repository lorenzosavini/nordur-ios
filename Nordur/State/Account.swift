import Foundation
import Observation
import Security

/// Norður account: everything the app keeps on the device (trip, recorded
/// drives, alert inbox, settings) is backed up, encrypted, to nordur-api and
/// restored after a reinstall or on a new iPhone.
@MainActor
@Observable
final class Account {
    static let shared = Account()
    static let api = URL(string: "https://nordur-api.vercel.app/api")!

    private(set) var email: String?
    private(set) var lastSync: Date?
    private(set) var isSyncing = false
    private(set) var lastError: String?

    var isSignedIn: Bool { token != nil }

    @ObservationIgnored private var token: String? {
        get { Keychain.read("token") }
        set { if let newValue { Keychain.write("token", newValue) } else { Keychain.delete("token") } }
    }

    private init() {
        email = Keychain.read("email")
        lastSync = UserDefaults.standard.object(forKey: "sync.last") as? Date
    }

    // MARK: Auth

    struct AuthResponse: Decodable { let token: String; let userId: String; let email: String; let recoveryCode: String? }
    struct ErrorResponse: Decodable { let error: String }
    struct RecoveryResponse: Decodable { let recoveryCode: String }

    /// One-time recovery code to show the user (after sign-up, reset or regeneration).
    var pendingRecoveryCode: String?

    /// Signs in or creates the account, then restores what is stored online.
    func authenticate(email: String, password: String, register: Bool) async throws -> Int {
        let body = try JSONSerialization.data(withJSONObject: ["mode": register ? "register" : "login", "email": email, "password": password, "lang": lang])
        return try await signIn(with: try await request("auth", method: "POST", body: body, authorized: false))
    }

    /// Language of the account e-mails: the app's.
    private var lang: String { Bundle.main.preferredLocalizations.first == "en" ? "en" : "it" }

    /// E-mails a 6-digit code (valid 15 minutes) to reset the password.
    func requestResetCode(email: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["mode": "forgot", "email": email, "lang": lang])
        _ = try await request("auth", method: "POST", body: body, authorized: false)
    }

    /// Sets a new password with the code received by e-mail, then signs in.
    func resetPassword(email: String, emailCode: String, newPassword: String) async throws -> Int {
        let body = try JSONSerialization.data(withJSONObject: ["mode": "reset", "email": email, "emailCode": emailCode, "password": newPassword, "lang": lang])
        return try await signIn(with: try await request("auth", method: "POST", body: body, authorized: false))
    }

    /// Sets a new password with the recovery code shown at sign-up, then signs in.
    func resetPassword(email: String, recoveryCode: String, newPassword: String) async throws -> Int {
        let body = try JSONSerialization.data(withJSONObject: ["mode": "reset", "email": email, "recoveryCode": recoveryCode, "password": newPassword, "lang": lang])
        return try await signIn(with: try await request("auth", method: "POST", body: body, authorized: false))
    }

    private func signIn(with data: Data) async throws -> Int {
        let response = try JSONDecoder().decode(AuthResponse.self, from: data)
        token = response.token
        Keychain.write("email", response.email)
        self.email = response.email
        if let code = response.recoveryCode { pendingRecoveryCode = code }
        UserDefaults.standard.removeObject(forKey: Self.manifestKey)
        let restored = try await restore()
        await sync()
        return restored
    }

    func changePassword(current: String, new: String) async throws {
        guard let email else { throw AccountError.message(String(localized: "Accedi al tuo account")) }
        let body = try JSONSerialization.data(withJSONObject: ["mode": "change", "email": email, "password": current, "newPassword": new, "lang": lang])
        _ = try await request("auth", method: "POST", body: body)
    }

    /// Replaces the recovery code (the old one stops working).
    func regenerateRecoveryCode(password: String) async throws {
        guard let email else { throw AccountError.message(String(localized: "Accedi al tuo account")) }
        let body = try JSONSerialization.data(withJSONObject: ["mode": "recovery", "email": email, "password": password, "lang": lang])
        pendingRecoveryCode = try JSONDecoder().decode(RecoveryResponse.self, from: try await request("auth", method: "POST", body: body)).recoveryCode
    }

    /// Permanently deletes the account, its backup and its sightings. Local data stays on the phone.
    func deleteAccount(password: String) async throws {
        guard let email else { throw AccountError.message(String(localized: "Accedi al tuo account")) }
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password, "lang": lang])
        _ = try await request("auth", method: "DELETE", body: body)
        signOut()
    }

    func signOut() {
        token = nil
        Keychain.delete("email")
        email = nil
        lastSync = nil
        UserDefaults.standard.removeObject(forKey: Self.manifestKey)
        UserDefaults.standard.removeObject(forKey: "sync.last")
    }

    /// Reports an aurora sighting (or its absence) at the given position (rounded to ~1 km by the server).
    /// `seen: false` is a negative report ("looking, no aurora") with the sky as seen.
    func reportSighting(at c: Coordinate, seen: Bool, nakedEye: Bool, camera: Bool, strength: String?, sky: String?) async throws {
        var body: [String: Any] = ["lat": c.lat, "lon": c.lon, "seen": seen, "nakedEye": nakedEye, "camera": camera]
        if let strength { body["strength"] = strength }
        if let sky { body["sky"] = sky }
        _ = try await request("sightings", method: "POST", body: try JSONSerialization.data(withJSONObject: body))
    }

    /// Deletes every document stored online for this account.
    func deleteRemoteData() async throws {
        _ = try await request("data", method: "DELETE")
        UserDefaults.standard.removeObject(forKey: Self.manifestKey)
    }

    // MARK: Sync

    /// Uploads files changed since the last sync and removes deleted ones.
    func sync() async {
        guard isSignedIn, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            var manifest = Self.manifest
            let local = SyncFiles.snapshot()
            for item in local where manifest[item.doc] != item.fingerprint {
                let payload: [String: Any] = ["path": item.path, "data": item.data.base64EncodedString(), "zlib": true]
                let body = try JSONSerialization.data(withJSONObject: ["payload": payload, "updatedAt": ISO8601DateFormatter().string(from: item.modified)])
                _ = try await request("data", method: "PUT", query: item.doc, body: body)
                manifest[item.doc] = item.fingerprint
            }
            let present = Set(local.map(\.doc))
            for doc in manifest.keys where !present.contains(doc) {
                _ = try await request("data", method: "DELETE", query: doc)
                manifest[doc] = nil
            }
            Self.manifest = manifest
            lastSync = Date()
            UserDefaults.standard.set(lastSync, forKey: "sync.last")
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Downloads the account's documents and writes them where the app reads them.
    /// Remote copies win when the local file is missing or older.
    @discardableResult
    func restore() async throws -> Int {
        struct Listing: Decodable { struct Doc: Decodable { let doc: String }; let docs: [Doc] }
        struct Stored: Decodable {
            struct Payload: Decodable { let path: String; let data: String; let zlib: Bool? }
            let payload: Payload
            let updatedAt: String?
        }
        let listing = try JSONDecoder().decode(Listing.self, from: try await request("data", method: "GET"))
        var count = 0
        var manifest = Self.manifest
        for entry in listing.docs {
            let stored = try JSONDecoder().decode(Stored.self, from: try await request("data", method: "GET", query: entry.doc))
            guard let raw = Data(base64Encoded: stored.payload.data) else { continue }
            let remoteDate = stored.updatedAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? .distantPast
            if SyncFiles.write(raw, compressed: stored.payload.zlib ?? false, path: stored.payload.path, remoteDate: remoteDate) {
                count += 1
            }
        }
        // What is on disk now matches the server: no need to upload it again.
        let remote = Set(listing.docs.map(\.doc))
        for item in SyncFiles.snapshot() where remote.contains(item.doc) { manifest[item.doc] = item.fingerprint }
        Self.manifest = manifest
        if count > 0 { NotificationCenter.default.post(name: .accountRestored, object: nil) }
        return count
    }

    /// After a reinstall the Keychain still holds the session while app data is
    /// gone: bring everything back without asking.
    func restoreAfterReinstall() async {
        let key = "sync.installed"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard isSignedIn else { return }
        _ = try? await restore()
    }

    // MARK: Networking

    private func request(_ path: String, method: String, query doc: String? = nil, body: Data? = nil, authorized: Bool = true) async throws -> Data {
        var components = URLComponents(url: Self.api.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if let doc { components.queryItems = [URLQueryItem(name: "doc", value: doc)] }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authorized {
            guard let token else { throw AccountError.message(String(localized: "Accedi al tuo account")) }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // An expired session signs out; a wrong password on account actions does not.
            if status == 401, authorized, path != "auth" { signOut() }
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error ?? String(localized: "Errore \(status)")
            throw AccountError.message(message)
        }
        return data
    }

    private static let manifestKey = "sync.manifest"
    private static var manifest: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: manifestKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: manifestKey) }
    }
}

extension Notification.Name {
    static let accountRestored = Notification.Name("nordur.accountRestored")
}

enum AccountError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}

/// The files and preferences that make up an account backup.
enum SyncFiles {
    struct Item {
        let doc: String
        let path: String
        let data: Data        // zlib-compressed
        let modified: Date
        let fingerprint: String
    }

    static let preferenceKeys = ["alertSettings", "driveSettings", "appearance", "chosenPlace", "useCurrentLocation",
                                 "map.layer", "map.warnings", "map.roads", "map.roadInfo", "map.webcams", "map.quakes", "map.fuel",
                                 "map.chargers", "map.trip", "map.particles"]

    private static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    static func snapshot() -> [Item] {
        var items: [Item] = []
        var paths = ["trip.json", "alerts.json"]
        let drives = documents.appendingPathComponent("drives")
        if let names = try? FileManager.default.contentsOfDirectory(atPath: drives.path) {
            paths += names.filter { $0.hasSuffix(".json") && $0 != "in-progress.json" }.map { "drives/\($0)" }
        }
        for path in paths {
            let url = documents.appendingPathComponent(path)
            guard let data = try? Data(contentsOf: url) else { continue }
            let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? Date()
            items.append(item(path: path, raw: data, modified: modified))
        }
        // Preferences travel as one property list.
        var prefs: [String: Any] = [:]
        for key in preferenceKeys { if let value = UserDefaults.standard.object(forKey: key) { prefs[key] = value } }
        if !prefs.isEmpty, let data = try? PropertyListSerialization.data(fromPropertyList: prefs, format: .binary, options: 0) {
            items.append(item(path: "@preferences", raw: data, modified: Date()))
        }
        return items
    }

    private static func item(path: String, raw: Data, modified: Date) -> Item {
        let compressed = (try? (raw as NSData).compressed(using: .zlib) as Data) ?? raw
        let doc = path.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return Item(doc: doc, path: path, data: compressed, modified: modified,
                    fingerprint: "\(raw.count)-\(stableHash(raw.base64EncodedString()))")
    }

    /// Returns true when the local copy was replaced.
    static func write(_ stored: Data, compressed: Bool, path: String, remoteDate: Date) -> Bool {
        guard let raw = compressed ? (try? (stored as NSData).decompressed(using: .zlib) as Data) : stored else { return false }
        if path == "@preferences" {
            guard let prefs = try? PropertyListSerialization.propertyList(from: raw, format: nil) as? [String: Any] else { return false }
            for (key, value) in prefs where preferenceKeys.contains(key) { UserDefaults.standard.set(value, forKey: key) }
            return true
        }
        guard !path.contains(".."), path.hasSuffix(".json") else { return false }
        let url = documents.appendingPathComponent(path)
        if let modified = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date, modified > remoteDate {
            return false
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? raw.write(to: url, options: .atomic)) != nil
    }
}

/// Minimal Keychain wrapper for the session token.
enum Keychain {
    private static let service = "it.lorenzosavini.nordur.account"

    static func write(_ key: String, _ value: String) {
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
    }
}
