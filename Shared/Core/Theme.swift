import SwiftUI

/// Visual identity: "Nordic night" — ink background, graphite surfaces with
/// hairline borders, one glacier accent, risk colours tuned for dark UI.
enum Theme {
    static let bg = Color(hex: 0x080B10)
    static let surface = Color(hex: 0x10161E)
    static let raised = Color(hex: 0x18212C)
    static let hairline = Color.white.opacity(0.07)
    static let text = Color(hex: 0xE8EDF3)
    static let dim = Color(hex: 0x8E9BAC)
    static let faint = Color(hex: 0x566373)
    static let accent = Color(hex: 0x7CCFE6)
    static let aurora = Color(hex: 0x58E0A0)

    static let ok = Color(hex: 0x3FCF8E)
    static let caution = Color(hex: 0xF2C14E)
    static let warning = Color(hex: 0xF0883E)
    static let danger = Color(hex: 0xEF5350)

    static let radius: CGFloat = 22

    /// Temperature colour, used for the daily range bars.
    static func temperature(_ value: Double) -> Color {
        let c = ColorStop.color(for: value, in: [
            .init(-15, 0.55, 0.45, 0.95, 1), .init(-5, 0.45, 0.65, 0.98, 1), .init(0, 0.55, 0.85, 0.95, 1),
            .init(5, 0.55, 0.88, 0.70, 1), .init(10, 0.95, 0.85, 0.45, 1), .init(16, 0.98, 0.62, 0.35, 1),
            .init(22, 0.95, 0.40, 0.35, 1),
        ])
        return Color(red: c.r, green: c.g, blue: c.b)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension Font {
    /// Big numbers: rounded, fixed-width digits.
    static func metric(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    /// Small uppercase section labels.
    static let eyebrow = Font.system(size: 11, weight: .semibold).width(.expanded)
}

extension View {
    /// Uppercase, tracked, dim label.
    func eyebrow(_ color: Color = Theme.dim) -> some View {
        font(.eyebrow).tracking(0.8).textCase(.uppercase).foregroundStyle(color)
    }

    /// Dark list styling for secondary screens.
    func themedList() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.bg)
    }

    /// Surface panel with a hairline border.
    func panel(padding: CGFloat = 16, radius: CGFloat = Theme.radius) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}
