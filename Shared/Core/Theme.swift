import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Visual identity. Light: warm paper, white cards, deep glacier accent.
/// Dark: ink, graphite cards, bright glacier accent. Risk colours tuned per mode.
enum Theme {
    static let bg = dynamic(0xF1F0EB, 0x0B0D10)
    static let surface = dynamic(0xFFFFFF, 0x15181D)
    static let raised = dynamic(0xEAE9E3, 0x1F232A)
    static let hairline = dynamic(0x000000, 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.08)
    static let text = dynamic(0x14171B, 0xEEF0F3)
    static let dim = dynamic(0x5C646E, 0x9AA3AE)
    static let faint = dynamic(0x979EA6, 0x5E6873)
    static let accent = dynamic(0x0B7A97, 0x72D2EA)
    static let aurora = dynamic(0x12A06C, 0x58E0A0)
    static let ink = dynamic(0x14171B, 0x0B0D10)

    static let ok = dynamic(0x1E9A60, 0x3FCF8E)
    static let caution = dynamic(0xC08600, 0xF2C14E)
    static let warning = dynamic(0xD8641B, 0xF0883E)
    static let danger = dynamic(0xD13B37, 0xEF5350)

    static let radius: CGFloat = 26

    static func dynamic(_ light: UInt32, _ dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: darkAlpha) : UIColor(hex: light, alpha: lightAlpha)
        })
        #else
        return Color(hex: light, opacity: lightAlpha)
        #endif
    }

    /// Temperature colour, used for the daily range bars.
    static func temperature(_ value: Double) -> Color {
        let c = ColorStop.color(for: value, in: [
            .init(-15, 0.50, 0.40, 0.92, 1), .init(-5, 0.36, 0.58, 0.96, 1), .init(0, 0.35, 0.78, 0.92, 1),
            .init(5, 0.40, 0.80, 0.60, 1), .init(10, 0.95, 0.78, 0.30, 1), .init(16, 0.97, 0.55, 0.25, 1),
            .init(22, 0.92, 0.32, 0.30, 1),
        ])
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    /// Sky gradient for the hero card, from the weather code and day/night.
    static func sky(code: Int?, isDay: Bool) -> [Color] {
        let c = code ?? 3
        if !isDay {
            if c >= 61 { return [Color(hex: 0x1B2433), Color(hex: 0x2B3A4E)] }
            return [Color(hex: 0x0E1730), Color(hex: 0x263866)]
        }
        switch c {
        case 0, 1: return [Color(hex: 0x2F7FC8), Color(hex: 0x7DBDEB)]
        case 2: return [Color(hex: 0x4A7FA8), Color(hex: 0x9CC0DA)]
        case 3, 45, 48: return [Color(hex: 0x5E6E7E), Color(hex: 0x9AA8B5)]
        case 71...77, 85, 86: return [Color(hex: 0x7C93AA), Color(hex: 0xC7D6E3)]
        case 95...99: return [Color(hex: 0x2E3446), Color(hex: 0x5B5F79)]
        default: return [Color(hex: 0x3F5466), Color(hex: 0x7891A5)]
        }
    }
}

#if canImport(UIKit)
extension UIColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: CGFloat(alpha))
    }
}
#endif

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Typography (Geist for text, Bricolage Grotesque for display and numbers)

enum AppFontName {
    static func geist(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: return "Geist-Bold"
        case .semibold: return "Geist-SemiBold"
        case .medium: return "Geist-Medium"
        default: return "Geist-Regular"
        }
    }

    static func display(_ weight: Font.Weight) -> String {
        switch weight {
        case .heavy, .black: return "BricolageGrotesque-ExtraBold"
        case .bold: return "BricolageGrotesque-Bold"
        default: return "BricolageGrotesque-SemiBold"
        }
    }
}

extension Font {
    /// Body/UI text in Geist.
    static func geist(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(AppFontName.geist(weight), size: size, relativeTo: style)
    }

    /// Headlines in Bricolage Grotesque.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .custom(AppFontName.display(weight), size: size, relativeTo: .largeTitle)
    }

    /// Big numbers: Bricolage Grotesque, tabular digits.
    static func metric(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .custom(AppFontName.display(weight == .regular || weight == .medium || weight == .light || weight == .thin ? .semibold : weight),
                size: size, relativeTo: .title).monospacedDigit()
    }

    /// Text styles mapped onto Geist.
    static func app(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> Font {
        switch style {
        case .largeTitle: return .display(34, weight ?? .bold)
        case .title: return .display(28, weight ?? .bold)
        case .title2: return .display(22, weight ?? .semibold)
        case .title3: return .geist(20, weight ?? .semibold, relativeTo: style)
        case .headline: return .geist(17, weight ?? .semibold, relativeTo: style)
        case .callout: return .geist(16, weight ?? .regular, relativeTo: style)
        case .subheadline: return .geist(15, weight ?? .regular, relativeTo: style)
        case .footnote: return .geist(13, weight ?? .regular, relativeTo: style)
        case .caption: return .geist(12, weight ?? .regular, relativeTo: style)
        case .caption2: return .geist(11, weight ?? .regular, relativeTo: style)
        default: return .geist(16, weight ?? .regular, relativeTo: style)
        }
    }

    static let eyebrow = Font.geist(11, .semibold, relativeTo: .caption2)
}

extension View {
    /// Uppercase, tracked, dim label.
    func eyebrow(_ color: Color = Theme.dim) -> some View {
        font(.eyebrow).tracking(1.1).textCase(.uppercase).foregroundStyle(color)
    }

    /// List styling for secondary screens.
    func themedList() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.bg)
    }

    /// Card surface: soft shadow in light mode, hairline in dark mode.
    func panel(padding: CGFloat = 18, radius: CGFloat = Theme.radius) -> some View {
        modifier(PanelModifier(padding: padding, radius: radius))
    }
}

struct PanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let padding: CGFloat
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.05), radius: 14, x: 0, y: 6)
    }
}
