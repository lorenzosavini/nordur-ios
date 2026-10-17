import SwiftUI
import UIKit

/// App appearance: follows the system or forces light/dark.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "appearance"
    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return String(localized: "Automatico")
        case .light: return String(localized: "Chiaro")
        case .dark: return String(localized: "Scuro")
        }
    }

    var short: String {
        switch self {
        case .system: return String(localized: "AUTO")
        case .light: return String(localized: "GIORNO")
        case .dark: return String(localized: "NOTTE")
        }
    }

    var next: Appearance {
        switch self {
        case .system: return .light
        case .light: return .dark
        case .dark: return .system
        }
    }

    /// Navigation bars and controls in the app fonts.
    static func configureUIKit() {
        let title = UIFont(name: "IBMPlexMono-SemiBold", size: 13) ?? .monospacedSystemFont(ofSize: 13, weight: .semibold)
        let large = UIFont(name: "BarlowCondensed-Bold", size: 40) ?? .systemFont(ofSize: 34, weight: .bold)
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: title, .kern: 1.0]
        let bar = UINavigationBarAppearance()
        bar.configureWithTransparentBackground()
        bar.titleTextAttributes = titleAttributes
        bar.largeTitleTextAttributes = [.font: large]
        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithOpaqueBackground()
        scrolled.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? .black : .white }
        scrolled.shadowColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.16) : UIColor(white: 0, alpha: 0.13) }
        scrolled.titleTextAttributes = titleAttributes
        scrolled.largeTitleTextAttributes = [.font: large]
        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().compactAppearance = scrolled
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        let barButton = UIBarButtonItemAppearance()
        barButton.normal.titleTextAttributes = [.font: UIFont(name: "IBMPlexSansRoman-Medium", size: 16) ?? .systemFont(ofSize: 16)]
        scrolled.buttonAppearance = barButton
        bar.buttonAppearance = barButton
        let mono = UIFont(name: "IBMPlexMono-Medium", size: 12) ?? .monospacedSystemFont(ofSize: 12, weight: .medium)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: mono], for: .normal)
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(hex: 0xF04A00)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: mono, .foregroundColor: UIColor.white], for: .selected)
        UITableViewHeaderFooterView.appearance().tintColor = .clear
    }
}

/// Flat bottom bar: rule on top, mono labels, orange marker above the active tab.
struct NordurTabBar: View {
    @Binding var selection: RootView.Tab
    var badge: Int
    var recording: Bool
    @Namespace private var namespace

    private let items: [(tab: RootView.Tab, symbol: String, title: String)] = [
        (.today, "sun.horizon.fill", String(localized: "Oggi")),
        (.weather, "cloud.sun.rain.fill", String(localized: "Meteo")),
        (.map, "map.fill", String(localized: "Mappa")),
        (.drive, "car.fill", String(localized: "Guida")),
        (.trip, "suitcase.rolling.fill", String(localized: "Viaggio")),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Rule(color: Theme.hairline)
            HStack(spacing: 0) {
                ForEach(items, id: \.tab) { item in
                    let selected = selection == item.tab
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { selection = item.tab }
                    } label: {
                        VStack(spacing: 0) {
                            ZStack {
                                Rectangle().fill(Color.clear).frame(height: 2)
                                if selected {
                                    Rectangle().fill(Theme.accent).frame(height: 2)
                                        .matchedGeometryEffect(id: "tab", in: namespace)
                                }
                            }
                            VStack(spacing: 4) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 19, weight: selected ? .semibold : .regular))
                                    .symbolRenderingMode(.monochrome)
                                    .foregroundStyle(selected ? Theme.accent : Theme.dim)
                                    .frame(height: 22)
                                    .overlay(alignment: .topTrailing) {
                                        if (item.tab == .today && badge > 0) || (item.tab == .drive && recording) {
                                            Circle().fill(Theme.danger).frame(width: 8, height: 8)
                                                .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 1.5))
                                                .offset(x: 6, y: -3)
                                        }
                                    }
                                Text(item.title.loc.uppercased())
                                    .font(.mono(10, selected ? .semibold : .medium))
                                    .tracking(0.5)
                                    .foregroundStyle(selected ? Theme.text : Theme.dim)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .padding(.top, 7)
                            .padding(.bottom, 5)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .background(Theme.bg.ignoresSafeArea(edges: .bottom))
    }
}

/// Header at the top of the main screens: index + mono kicker, condensed title.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var index: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    if let index { Text(index).font(.mono(10.5, .semibold)).foregroundStyle(Theme.accent) }
                    if let subtitle { Text(subtitle.loc).eyebrow(Theme.dim) }
                }
                Spacer()
                trailing
            }
            Text(title.loc.uppercased()).font(.display(46, .bold)).foregroundStyle(Theme.text)
                .padding(.bottom, -6)
            Rule(color: Theme.rule, height: 2)
        }
        .padding(.top, 6)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, index: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.index = index
        self.trailing = EmptyView()
    }
}

/// Square outlined control used in headers.
struct HeaderButton: View {
    let systemImage: String
    var tint: Color = Theme.text
    var dot: Bool = false
    var label: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let label {
                        Text(label.loc).font(.mono(10.5, .semibold)).tracking(0.6).padding(.horizontal, 9)
                    } else {
                        Image(systemName: systemImage).font(.system(size: 13, weight: .semibold)).frame(width: 34)
                    }
                }
                .foregroundStyle(tint)
                .frame(height: 34)
                .overlay(Rectangle().strokeBorder(Theme.hairline, lineWidth: 1))
                if dot { Rectangle().fill(Theme.accent).frame(width: 7, height: 7).offset(x: 2, y: -2) }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Cycles automatic → day → night.
struct AppearanceButton: View {
    @AppStorage(Appearance.key) private var appearance = Appearance.system.rawValue

    var body: some View {
        let current = Appearance(rawValue: appearance) ?? .system
        HeaderButton(systemImage: "circle.lefthalf.filled", label: current.short) {
            withAnimation(.easeInOut(duration: 0.25)) { appearance = current.next.rawValue }
        }
        .accessibilityLabel("Aspetto: \(current.label)")
    }
}
