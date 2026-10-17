import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Visual identity: a field instrument.
/// Paper-white or true black, hairline rules, square corners, and one signal
/// colour (rescue orange) used only where something needs attention.
enum Theme {
    static let bg = dynamic(0xFFFFFF, 0x000000)
    static let surface = dynamic(0xF4F4F2, 0x0F0F0F)
    static let raised = dynamic(0xE9E9E6, 0x1C1C1C)
    static let hairline = dynamic(0x000000, 0xFFFFFF, lightAlpha: 0.13, darkAlpha: 0.16)
    static let rule = dynamic(0x000000, 0xFFFFFF, lightAlpha: 0.9, darkAlpha: 0.85)
    static let text = dynamic(0x0A0A0A, 0xF2F2F0)
    // Secondary text kept above WCAG AA contrast on both backgrounds.
    static let dim = dynamic(0x4F4F4F, 0xA8A8A6)
    static let faint = dynamic(0x767676, 0x8A8A88)
    static let accent = dynamic(0xF04A00, 0xFF5A1F)
    static let onAccent = Color.white
    static let aurora = dynamic(0x00A37A, 0x3DE0A8)
    static let ink = dynamic(0x0A0A0A, 0x000000)

    // Risk: neutral when fine, colour only when it matters.
    static let ok = dynamic(0x8A8A8A, 0x6E6E6C)
    static let caution = dynamic(0xD99A00, 0xF2B807)
    static let warning = accent
    static let danger = dynamic(0xD10000, 0xFF3B30)

    static let radius: CGFloat = 0

    static func dynamic(_ light: UInt32, _ dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: darkAlpha) : UIColor(hex: light, alpha: lightAlpha)
        })
        #else
        return Color(hex: light, opacity: lightAlpha)
        #endif
    }

    /// Temperature scale for range bars: cold steel → neutral → orange.
    static func temperature(_ value: Double) -> Color {
        let c = ColorStop.color(for: value, in: [
            .init(-15, 0.24, 0.36, 0.62, 1), .init(-3, 0.38, 0.55, 0.75, 1), .init(3, 0.56, 0.62, 0.66, 1),
            .init(10, 0.80, 0.60, 0.40, 1), .init(18, 0.94, 0.33, 0.06, 1),
        ])
        return Color(red: c.r, green: c.g, blue: c.b)
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

// MARK: - Typography
// IBM Plex Sans for text, IBM Plex Mono for labels and data, Barlow Condensed for figures.

enum AppFontName {
    static func sans(_ weight: Font.Weight) -> String {
        switch weight {
        case .semibold, .bold, .heavy, .black: return "IBMPlexSansRoman-SemiBold"
        case .medium: return "IBMPlexSansRoman-Medium"
        default: return "IBMPlexSansRoman-Regular"
        }
    }

    static func mono(_ weight: Font.Weight) -> String {
        switch weight {
        case .semibold, .bold, .heavy, .black: return "IBMPlexMono-SemiBold"
        case .medium: return "IBMPlexMono-Medium"
        default: return "IBMPlexMono-Regular"
        }
    }

    static func condensed(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: return "BarlowCondensed-Bold"
        case .semibold: return "BarlowCondensed-SemiBold"
        default: return "BarlowCondensed-Medium"
        }
    }
}

extension Font {
    /// Body/UI text.
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(AppFontName.sans(weight), size: size, relativeTo: style)
    }

    /// Labels, codes, tables.
    /// Labels, codes, tables. Very small sizes are raised by one point: below
    /// ~10.5 pt the mono labels were hard to read on a phone held at arm's length.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium, relativeTo style: Font.TextStyle = .caption) -> Font {
        .custom(AppFontName.mono(weight), size: size < 10.5 ? size + 1 : size, relativeTo: style)
    }

    /// Headlines: condensed, set in capitals by the caller when needed.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .custom(AppFontName.condensed(weight), size: size, relativeTo: .largeTitle)
    }

    /// Figures: condensed, tabular.
    static func metric(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .custom(AppFontName.condensed(weight), size: size, relativeTo: .title).monospacedDigit()
    }

    static func app(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> Font {
        switch style {
        case .largeTitle: return .display(40, weight ?? .bold)
        case .title: return .display(32, weight ?? .bold)
        case .title2: return .display(26, weight ?? .semibold)
        case .title3: return .sans(19, weight ?? .semibold, relativeTo: style)
        case .headline: return .sans(16, weight ?? .semibold, relativeTo: style)
        case .callout: return .sans(15.5, weight ?? .regular, relativeTo: style)
        case .subheadline: return .sans(14.5, weight ?? .regular, relativeTo: style)
        case .footnote: return .sans(13, weight ?? .regular, relativeTo: style)
        case .caption: return .sans(12, weight ?? .regular, relativeTo: style)
        case .caption2: return .sans(11, weight ?? .regular, relativeTo: style)
        default: return .sans(15.5, weight ?? .regular, relativeTo: style)
        }
    }

    static let eyebrow = Font.mono(10.5, .medium, relativeTo: .caption2)
}

extension View {
    /// Uppercase mono label.
    func eyebrow(_ color: Color = Theme.dim) -> some View {
        font(.eyebrow).tracking(0.8).textCase(.uppercase).foregroundStyle(color)
    }

    /// Plain list on the app background for secondary screens.
    func themedList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .listRowSeparatorTint(Theme.hairline)
            .listSectionSeparator(.hidden)
    }

    /// List section header on the app background: plain lists keep the header
    /// pinned at the top while scrolling, and a transparent one overlaps the rows.
    func pinnedHeader() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 24)
            .background(Theme.bg)
            .padding(.horizontal, -24)
    }

    /// Instrument panel: square, ruled, no fill, no shadow.
    func panel(padding: CGFloat = 16, radius: CGFloat = Theme.radius) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(Rectangle().strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

/// Thin full-width rule.
struct Rule: View {
    var color: Color = Theme.hairline
    var height: CGFloat = 1
    var body: some View { color.frame(height: height).frame(maxWidth: .infinity) }
}

/// Section label: index, title, rule running to the edge, optional trailing note.
struct SectionLabel: View {
    var index: String?
    let title: String
    var trailing: String?
    var trailingColor: Color = Theme.dim

    /// Section title: a condensed headline with its number, a rule below; the
    /// trailing note (status, count, "all →") sits on the right.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                if let index {
                    Text(index).font(.mono(11, .semibold)).foregroundStyle(Theme.accent)
                }
                Text(title.loc.uppercased()).font(.display(23, .bold)).foregroundStyle(Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing.loc).font(.mono(10.5, .semibold)).foregroundStyle(trailingColor)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Rectangle().fill(Theme.rule).frame(height: 1.5)
        }
    }
}
