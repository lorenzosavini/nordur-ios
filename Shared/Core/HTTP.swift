import Foundation

/// A value downloaded from a remote source, with the time it was obtained.
/// `isStale` is true when the network failed and the value comes from the
/// on-device cache — useful in the many Icelandic areas without coverage.
struct Fetched<Value> {
    let value: Value
    let date: Date
    let isStale: Bool

    func map<T>(_ transform: (Value) throws -> T) rethrows -> Fetched<T> {
        Fetched<T>(value: try transform(value), date: date, isStale: isStale)
    }
}

/// Last good response of every request, kept in Caches so the app still shows
/// something useful offline.
enum DiskCache {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NordurCache", isDirectory: true)
    }

    private static func fileURL(_ key: String) -> URL {
        let safe = key.map { ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") ? $0 : "_" }
        return directory.appendingPathComponent(String(safe))
    }

    static func write(_ data: Data, key: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(key), options: .atomic)
    }

    static func read(_ key: String) -> (data: Data, date: Date)? {
        let url = fileURL(key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let date = (attributes?[.modificationDate] as? Date) ?? .distantPast
        return (data, date)
    }
}

enum HTTPError: LocalizedError {
    case status(Int)
    case invalidURL
    case notCached

    var errorDescription: String? {
        switch self {
        case .status(let code): return String(localized: "Il server ha risposto con errore \(code)")
        case .invalidURL: return String(localized: "Indirizzo non valido")
        case .notCached: return String(localized: "Nessuna copia salvata sul telefono")
        }
    }
}

enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        // A source that hangs gives way to the saved copy quickly.
        config.timeoutIntervalForRequest = 15
        config.httpMaximumConnectionsPerHost = 8
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    static func url(_ base: String, _ query: [String: String]) throws -> URL {
        guard var components = URLComponents(string: base) else { throw HTTPError.invalidURL }
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw HTTPError.invalidURL }
        return url
    }

    /// Set for a warm start: requests answer from the copy saved on the phone only, with no network.
    @TaskLocal static var cacheOnly = false

    /// Downloads `url`; on failure falls back to the last cached copy.
    static func get(_ url: URL, cacheKey: String) async throws -> Fetched<Data> {
        if cacheOnly {
            guard let cached = DiskCache.read(cacheKey) else { throw HTTPError.notCached }
            // Recent copies are shown as current; older ones carry the offline label until the refresh lands.
            return Fetched(value: cached.data, date: cached.date, isStale: Date().timeIntervalSince(cached.date) > 1800)
        }
        do {
            let data = try await download(url, retries: 2)
            DiskCache.write(data, key: cacheKey)
            return Fetched(value: data, date: Date(), isStale: false)
        } catch {
            let host = (url.host ?? "") + url.path
            if let cached = DiskCache.read(cacheKey) {
                ErrorLog.record("Rete · \(url.host ?? "")", error, detail: "\(host) — mostrata la copia salvata del \(cached.date.formatted(date: .abbreviated, time: .shortened))")
                return Fetched(value: cached.data, date: cached.date, isStale: true)
            }
            ErrorLog.record("Rete · \(url.host ?? "")", error, detail: host)
            throw error
        }
    }

    /// Retries busy/overloaded responses (429, 5xx) and timeouts with a short backoff.
    private static func download(_ url: URL, retries: Int) async throws -> Data {
        var attemptNumber = 0
        while true {
            do {
                var request = URLRequest(url: url)
                request.setValue("Nordur-iOS/1.0 github.com/lorenzosavini/nordur-ios", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw HTTPError.status(http.statusCode)
                }
                return data
            } catch {
                let transient: Bool
                if case HTTPError.status(let code) = error { transient = code == 429 || code >= 500 }
                else if let urlError = error as? URLError { transient = urlError.code == .timedOut || urlError.code == .networkConnectionLost }
                else { transient = false }
                guard transient, attemptNumber < retries else { throw error }
                attemptNumber += 1
                try await Task.sleep(nanoseconds: UInt64(attemptNumber) * 1_500_000_000)
            }
        }
    }

    static func json<T: Decodable>(_ type: T.Type, from url: URL, cacheKey: String) async throws -> Fetched<T> {
        let fetched = try await get(url, cacheKey: cacheKey)
        return try fetched.map { data in
            // Some feeds answer "204 No Content" (an empty body) when there is nothing,
            // e.g. the IMO warnings with no warning in force: that is an empty list.
            if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }),
               let empty = try? JSONDecoder().decode(T.self, from: Data("[]".utf8)) {
                return empty
            }
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                ErrorLog.record("Dati · \(url.host ?? "")", error, detail: (url.host ?? "") + url.path + " · " + String(describing: T.self))
                throw error
            }
        }
    }
}

/// Deterministic (per-launch stable) hash for cache keys; `hashValue` is randomized.
func stableHash(_ text: String) -> String {
    var hash: UInt64 = 5381
    for byte in text.utf8 { hash = (hash &* 33) ^ UInt64(byte) }
    return String(hash, radix: 36)
}

/// Wraps an async throwing call so several can run in parallel with `async let`
/// and fail independently.
func attempt<T>(_ operation: @escaping () async throws -> T) async -> Result<T, Error> {
    do {
        return .success(try await operation())
    } catch {
        return .failure(error)
    }
}
