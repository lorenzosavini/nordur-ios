import UIKit
import UserNotifications

/// Category picture attached to every alert notification: iOS always shows the
/// app icon on the left, the attachment appears as a thumbnail on the right of
/// the banner (and large when the notification is expanded), so the kind of
/// alert is recognisable at a glance: road, wind, IMO warning, quake, aurora…
enum NotificationIcon {
    static func color(_ category: AlertCategory) -> UIColor {
        switch category {
        case .weatherWarning: return UIColor(red: 0.96, green: 0.70, blue: 0.05, alpha: 1)
        case .wind: return UIColor(red: 0.10, green: 0.62, blue: 0.70, alpha: 1)
        case .road: return UIColor(red: 0.94, green: 0.29, blue: 0.0, alpha: 1)
        case .quake: return UIColor(red: 0.62, green: 0.20, blue: 0.12, alpha: 1)
        case .safeTravel: return UIColor(red: 0.13, green: 0.40, blue: 0.85, alpha: 1)
        case .aurora: return UIColor(red: 0.10, green: 0.72, blue: 0.50, alpha: 1)
        case .flight: return UIColor(red: 0.33, green: 0.30, blue: 0.80, alpha: 1)
        case .ferry: return UIColor(red: 0.08, green: 0.25, blue: 0.50, alpha: 1)
        case .speed: return UIColor(red: 0.85, green: 0.10, blue: 0.15, alpha: 1)
        case .notice: return UIColor(red: 1.0, green: 0.35, blue: 0.12, alpha: 1)
        case .summary: return UIColor(red: 0.18, green: 0.32, blue: 0.55, alpha: 1)
        }
    }

    /// Square picture: category colour, white symbol, a red corner for danger.
    static func image(for event: AlertEvent) -> UIImage {
        let size = CGSize(width: 240, height: 240)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            color(event.category).setFill()
            ctx.fill(rect)
            let config = UIImage.SymbolConfiguration(pointSize: 118, weight: .semibold)
            if let symbol = UIImage(systemName: event.category.symbol, withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let s = symbol.size
                symbol.draw(in: CGRect(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2, width: s.width, height: s.height))
            }
            if event.risk >= .warning {
                UIColor(white: 1, alpha: 0.95).setFill()
                ctx.fill(CGRect(x: 0, y: size.height - 18, width: size.width, height: 18))
                (event.risk == .danger ? UIColor(red: 0.85, green: 0.05, blue: 0.1, alpha: 1) : UIColor(red: 0.98, green: 0.5, blue: 0, alpha: 1)).setFill()
                ctx.fill(CGRect(x: 0, y: size.height - 14, width: size.width, height: 14))
            }
        }
    }

    /// A fresh file each time: the system moves attachments into its own store.
    static func attachment(for event: AlertEvent) -> UNNotificationAttachment? {
        guard let data = image(for: event).pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("alert-\(UUID().uuidString).png")
        do {
            try data.write(to: url)
            return try UNNotificationAttachment(identifier: "category", url: url,
                                                options: [UNNotificationAttachmentOptionsTypeHintKey: "public.png"])
        } catch {
            return nil
        }
    }
}
