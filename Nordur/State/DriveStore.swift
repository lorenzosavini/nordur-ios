import Foundation
import Observation

/// Recorded drives on disk: a light index (no GPS points) plus one file per drive.
@MainActor
@Observable
final class DriveStore {
    static let shared = DriveStore()

    private(set) var drives: [DriveSession] = []   // newest first, points stripped

    private init() {
        drives = Self.loadIndex()
        // Demo video only (`-ciDemoTrip YES`): a drive on the south coast to show a route and its sharing.
        if drives.isEmpty, UserDefaults.standard.bool(forKey: "ciDemoTrip") { saveImported(Self.demoDrive()) }
        // CI only (`-ciFlyover YES`): the picture and the 3D flight of the demo drive, written to Documents.
        if UserDefaults.standard.bool(forKey: "ciFlyover") {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                // `-ciFlyoverGPX ring-road`: a route copied into Documents (tools/ci/routes) instead of the demo drive.
                let route = UserDefaults.standard.string(forKey: "ciFlyoverGPX")
                let session: DriveSession
                if let route {
                    do { session = try importGPX(docs.appendingPathComponent(route + ".gpx")) } catch {
                        try? "error import \(error)".write(to: docs.appendingPathComponent("flyover-\(route).txt"), atomically: true, encoding: .utf8)
                        return
                    }
                } else if let first = drives.first, let demo = load(first.id) {
                    session = demo
                } else { return }
                let began = Date()
                if route == nil, let image = try? await RouteTerrain3D.image(session, format: .story) {
                    try? FileManager.default.copyItem(at: image, to: docs.appendingPathComponent("flyover.jpg"))
                }
                do {
                    // The 3D engine directly, so a failure shows in the result instead of the fallback.
                    let video = try await RouteTerrain3D.video(session, format: .story) { _ in }
                    let stem = route.map { "flyover-\($0)" } ?? "flyover"
                    try? FileManager.default.removeItem(at: docs.appendingPathComponent(stem + ".mp4"))
                    try? FileManager.default.copyItem(at: video, to: docs.appendingPathComponent(stem + ".mp4"))
                    try? "ok \(Int(Date().timeIntervalSince(began))) s".write(to: docs.appendingPathComponent(stem + ".txt"), atomically: true, encoding: .utf8)
                } catch {
                    let stem = route.map { "flyover-\($0)" } ?? "flyover"
                    try? "error \(error)".write(to: docs.appendingPathComponent(stem + ".txt"), atomically: true, encoding: .utf8)
                }
            }
        }
    }

    private static func demoDrive() -> DriveSession {
        let way: [(Double, Double)] = [(63.6156, -19.9886), (63.6000, -19.9500), (63.5700, -19.8000), (63.5450, -19.6500), (63.5321, -19.5114),
                                       (63.5150, -19.4000), (63.4700, -19.2500), (63.4300, -19.1000), (63.4186, -19.0060)]
        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(11 * 3600)
        var points: [TrackPoint] = []
        var clock = 0.0
        for i in 0..<(way.count - 1) {
            // Two stops, as a real drive has: Skógafoss (15 min) and before Vík (10 min).
            if i == 4 || i == 7 {
                let minutes = i == 4 ? 15.0 : 10.0
                for _ in 0..<12 {
                    clock += minutes * 60 / 12
                    points.append(TrackPoint(t: start.addingTimeInterval(clock), lat: way[i].0, lon: way[i].1, alt: 40, speed: 0, course: nil, accuracy: 5))
                }
            }
            for k in 0..<50 {
                let f = Double(k) / 50
                let lat = way[i].0 + (way[i + 1].0 - way[i].0) * f, lon = way[i].1 + (way[i + 1].1 - way[i].1) * f
                clock += 9
                points.append(TrackPoint(t: start.addingTimeInterval(clock), lat: lat, lon: lon,
                                         alt: 40 + 60 * sin(Double(points.count) / 40), speed: 21, course: nil, accuracy: 5))
            }
        }
        var session = DriveMath.imported(name: String(localized: "Costa sud: Seljalandsfoss → Vík"), points: points)
        session.importID = "ci-demo-drive"
        return session
    }

    func reload() { drives = Self.loadIndex() }

    nonisolated static var directory: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("drives", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private nonisolated static var indexURL: URL { directory.appendingPathComponent("index.json") }
    nonisolated static var inProgressURL: URL { directory.appendingPathComponent("in-progress.json") }
    private nonisolated static func fileURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }

    private nonisolated static func loadIndex() -> [DriveSession] {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([DriveSession].self, from: data) else { return [] }
        return list.sorted { $0.start > $1.start }
    }

    private func saveIndex() {
        if let data = try? JSONEncoder().encode(drives) {
            try? data.write(to: Self.indexURL, options: .atomic)
        }
    }

    func save(_ session: DriveSession) {
        if let data = try? JSONEncoder().encode(session) {
            try? data.write(to: Self.fileURL(session.id), options: .atomic)
        }
        var light = session
        light.points = []
        drives.removeAll { $0.id == session.id }
        drives.insert(light, at: 0)
        drives.sort { $0.start > $1.start }
        saveIndex()
    }

    /// Updates name/notes/odometer without touching the GPS points.
    func updateMetadata(_ session: DriveSession) {
        guard var full = load(session.id) else { return }
        full.name = session.name
        full.notes = session.notes
        full.odometerStart = session.odometerStart
        save(full)
    }

    func load(_ id: UUID) -> DriveSession? {
        guard let data = try? Data(contentsOf: Self.fileURL(id)) else { return nil }
        return try? JSONDecoder().decode(DriveSession.self, from: data)
    }

    func delete(_ session: DriveSession) {
        try? FileManager.default.removeItem(at: Self.fileURL(session.id))
        drives.removeAll { $0.id == session.id }
        saveIndex()
    }

    /// Totals of the drives (imported runs, rides and hikes are not driving).
    var totalKm: Double { drives.filter(\.isDrive).reduce(0) { $0 + $1.stats.km } }
    var totalSeconds: Double { drives.filter(\.isDrive).reduce(0) { $0 + $1.durationSeconds() } }

    // MARK: Imports (Apple Health, GPX files)

    func hasImported(_ importID: String) -> Bool { drives.contains { $0.importID == importID } }

    /// Saves an imported activity unless it is already in the history.
    @discardableResult
    func saveImported(_ session: DriveSession) -> Bool {
        if let id = session.importID, hasImported(id) { return false }
        save(session)
        return true
    }

    enum ImportError: LocalizedError {
        case unreadable, duplicate
        var errorDescription: String? {
            switch self {
            case .unreadable: return String(localized: "Il file non contiene una traccia GPX leggibile")
            case .duplicate: return String(localized: "Questa traccia è già nello storico")
            }
        }
    }

    /// Imports a GPX file (Files, Garmin Connect, Strava, Komoot… via "Apri con Norður").
    func importGPX(_ url: URL) throws -> DriveSession {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let read = GPXReader.read(data) else { throw ImportError.unreadable }
        let fallback = url.deletingPathExtension().lastPathComponent
        var session = DriveMath.imported(name: read.name ?? fallback, points: read.points)
        session.source = "GPX"
        session.activity = String(localized: "Traccia GPX")
        if let first = read.points.first, let last = read.points.last {
            session.importID = "gpx:\(stableHash("\(first.t.timeIntervalSince1970)|\(first.lat)|\(first.lon)|\(last.lat)|\(last.lon)|\(read.points.count)"))"
        }
        guard saveImported(session) else { throw ImportError.duplicate }
        return session
    }

    // MARK: In-progress drive (crash/kill safe)

    nonisolated static func saveInProgress(_ session: DriveSession) {
        if let data = try? JSONEncoder().encode(session) {
            try? data.write(to: inProgressURL, options: .atomic)
        }
    }

    nonisolated static func loadInProgress() -> DriveSession? {
        guard let data = try? Data(contentsOf: inProgressURL) else { return nil }
        return try? JSONDecoder().decode(DriveSession.self, from: data)
    }

    nonisolated static func clearInProgress() {
        try? FileManager.default.removeItem(at: inProgressURL)
    }

    /// GPX file in the temporary directory, ready to share.
    func exportGPX(_ session: DriveSession) -> URL? {
        guard let full = load(session.id) ?? (session.points.isEmpty ? nil : session) else { return nil }
        let safeName = full.name.replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "_", options: .regularExpression)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName.isEmpty ? "percorso" : safeName).gpx")
        do {
            try DriveMath.gpx(full).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            ErrorLog.record("GPX", error)
            return nil
        }
    }
}
