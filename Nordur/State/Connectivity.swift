import Foundation
import Network
import Observation

/// Whether the phone is online. The app shows one "offline" strip instead of
/// errors everywhere, and reloads everything as soon as the connection is back.
@MainActor
@Observable
final class Connectivity {
    static let shared = Connectivity()

    private(set) var isOnline = true
    /// Increases each time the connection comes back (to trigger a refresh).
    private(set) var reconnections = 0

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in Connectivity.shared.update(online) }
        }
        monitor.start(queue: DispatchQueue(label: "nordur.connectivity"))
    }

    private func update(_ online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        if online { reconnections += 1 }
    }
}
