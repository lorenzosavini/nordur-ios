import SwiftUI

/// CI only (the demo video): the recording script drives the app with Darwin
/// notifications (`simctl spawn <udid> notifyutil -p nordur.ci.tab.weather`)
/// instead of reading the screen with idb, whose accessibility queries can
/// hang the app on screens with many map pins.
enum CIRemote {
    static let commands = ["tab.today", "tab.weather", "tab.aurora", "tab.map", "tab.trip",
                           "settings", "dismiss", "night",
                           "screen.sights", "screen.roads", "screen.quakes", "screen.webcams", "screen.sources",
                           "trip.share", "trip.inbox", "trip.drive", "trip.mode.days", "trip.mode.stops", "trip.mode.map",
                           "aurora.mode.live", "aurora.mode.day", "aurora.mode.three", "drive.demo", "drive.share"]
    static let notification = Notification.Name("nordur.ci.command")
    private static var listening = false

    /// Closes whatever sheet or menu is on screen.
    static func dismissAll() {
        let root = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
        root?.dismiss(animated: true)
    }

    /// Turns the Darwin notifications into `notification` posts, in the demo run only.
    static func start() {
        guard !listening, UserDefaults.standard.bool(forKey: "ciDemoTrip") else { return }
        listening = true
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for command in commands {
            CFNotificationCenterAddObserver(center, nil, { _, _, name, _, _ in
                guard let raw = name?.rawValue as String? else { return }
                let command = raw.replacingOccurrences(of: "nordur.ci.", with: "")
                DispatchQueue.main.async { NotificationCenter.default.post(name: CIRemote.notification, object: command) }
            }, "nordur.ci.\(command)" as CFString, nil, .deliverImmediately)
        }
    }
}

extension View {
    /// Reacts to a command of the demo run (see CIRemote).
    func onCICommand(_ perform: @escaping (String) -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: CIRemote.notification)) { note in
            if let command = note.object as? String { perform(command) }
        }
    }
}
