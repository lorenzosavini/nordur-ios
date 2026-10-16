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

    var totalKm: Double { drives.reduce(0) { $0 + $1.stats.km } }
    var totalSeconds: Double { drives.reduce(0) { $0 + $1.durationSeconds() } }

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
            return nil
        }
    }
}
