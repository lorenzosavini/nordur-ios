import UIKit

/// CI only (the demo video): the recording script switches tab with a Darwin
/// notification (`simctl spawn <udid> notifyutil -p nordur.ci.tab.weather`),
/// because taps on the tab bar from idb do not always land.
enum CIRemote {
    static let tabs = ["today", "weather", "aurora", "map", "trip"]
    private static var handler: ((String) -> Void)?

    /// Closes whatever sheet or menu is on screen.
    static func dismissAll() {
        let root = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
        root?.dismiss(animated: true)
    }

    static func listen(_ handle: @escaping (String) -> Void) {
        guard handler == nil else { handler = handle; return }
        handler = handle
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for name in tabs.map({ "nordur.ci.tab.\($0)" }) + ["nordur.ci.settings", "nordur.ci.dismiss"] {
            CFNotificationCenterAddObserver(center, nil, { _, _, name, _, _ in
                guard let raw = name?.rawValue as String? else { return }
                let command = raw.replacingOccurrences(of: "nordur.ci.", with: "")
                DispatchQueue.main.async { CIRemote.handler?(command) }
            }, name as CFString, nil, .deliverImmediately)
        }
    }
}
