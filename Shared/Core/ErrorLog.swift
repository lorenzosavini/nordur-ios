import Foundation

/// Every error the app meets while running (a source that does not answer, data
/// that cannot be read, a sync that fails, the GPS), kept on the phone for
/// Settings › Registro errori. The same error repeated within 10 minutes counts
/// up instead of filling the list. Thread-safe: called from anywhere.
enum ErrorLog {
    struct Entry: Codable, Identifiable, Hashable {
        var id = UUID()
        var date: Date
        var last: Date
        var count: Int
        var source: String
        var message: String
        var detail: String?
    }

    static let didChange = Notification.Name("nordur.errorLogChanged")
    private static let queue = DispatchQueue(label: "nordur.errorlog")
    private static var cache: [Entry]?
    private static let limit = 400

    private static var url: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("crashes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("errors.json")
    }

    static func record(_ source: String, _ message: String, detail: String? = nil) {
        let now = Date()
        queue.async {
            var list = loaded()
            if let i = list.firstIndex(where: { $0.source == source && $0.message == message && now.timeIntervalSince($0.last) < 600 }) {
                list[i].count += 1
                list[i].last = now
                if let detail { list[i].detail = detail }
                let entry = list.remove(at: i)
                list.insert(entry, at: 0)
            } else {
                list.insert(Entry(date: now, last: now, count: 1, source: source, message: message, detail: detail), at: 0)
            }
            store(Array(list.prefix(limit)))
        }
    }

    /// The error, written plainly: what failed and why.
    static func record(_ source: String, _ error: Error, detail: String? = nil) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        record(source, describe(error), detail: detail)
    }

    static func entries() -> [Entry] { queue.sync { loaded() } }

    static func clear() { queue.sync { store([]) } }

    static func describe(_ error: Error) -> String {
        if let decoding = error as? DecodingError {
            switch decoding {
            case .keyNotFound(let key, let context): return "Dati non leggibili: manca «\(key.stringValue)» (\(path(context)))"
            case .typeMismatch(_, let context), .valueNotFound(_, let context): return "Dati non leggibili: \(context.debugDescription) (\(path(context)))"
            case .dataCorrupted(let context): return "Dati non leggibili: \(context.debugDescription)"
            @unknown default: return "Dati non leggibili"
            }
        }
        if let url = error as? URLError { return "Rete: \(url.localizedDescription) (codice \(url.code.rawValue))" }
        return error.localizedDescription
    }

    private static func path(_ context: DecodingError.Context) -> String {
        context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
    }

    private static func loaded() -> [Entry] {
        if let cache { return cache }
        let list = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        cache = list
        return list
    }

    private static func store(_ list: [Entry]) {
        cache = list
        if let data = try? JSONEncoder().encode(list) { try? data.write(to: url, options: .atomic) }
        DispatchQueue.main.async { NotificationCenter.default.post(name: didChange, object: nil) }
    }
}
