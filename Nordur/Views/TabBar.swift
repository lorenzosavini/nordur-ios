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
        case .system: return "Automatico"
        case .light: return "Chiaro"
        case .dark: return "Scuro"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var next: Appearance {
        switch self {
        case .system: return .light
        case .light: return .dark
        case .dark: return .system
        }
    }

    /// Navigation bar titles in the app fonts.
    static func configureUIKit() {
        let title = UIFont(name: "Geist-SemiBold", size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)
        let large = UIFont(name: "BricolageGrotesque-Bold", size: 34) ?? .systemFont(ofSize: 34, weight: .bold)
        let bar = UINavigationBarAppearance()
        bar.configureWithTransparentBackground()
        bar.titleTextAttributes = [.font: title]
        bar.largeTitleTextAttributes = [.font: large]
        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        scrolled.titleTextAttributes = [.font: title]
        scrolled.largeTitleTextAttributes = [.font: large]
        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().compactAppearance = scrolled
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        let barButton = UIBarButtonItemAppearance()
        barButton.normal.titleTextAttributes = [.font: UIFont(name: "Geist-Medium", size: 17) ?? .systemFont(ofSize: 17)]
        scrolled.buttonAppearance = barButton
        bar.buttonAppearance = barButton
        UISegmentedControl.appearance().setTitleTextAttributes([.font: UIFont(name: "Geist-Medium", size: 13) ?? .systemFont(ofSize: 13)], for: .normal)
    }
}

/// Floating pill tab bar with an animated selection.
struct NordurTabBar: View {
    @Binding var selection: RootView.Tab
    var badge: Int
    var recording: Bool
    @Namespace private var namespace

    private let items: [(tab: RootView.Tab, title: String, symbol: String, selectedSymbol: String)] = [
        (.today, "Oggi", "sun.horizon", "sun.horizon.fill"),
        (.weather, "Meteo", "cloud.sun", "cloud.sun.fill"),
        (.map, "Mappa", "map", "map.fill"),
        (.drive, "Guida", "car", "car.fill"),
        (.trip, "Viaggio", "signpost.right", "signpost.right.fill"),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.tab) { item in
                let selected = selection == item.tab
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selection = item.tab }
                } label: {
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: selected ? item.selectedSymbol : item.symbol)
                                .font(.system(size: 17, weight: selected ? .semibold : .regular))
                                .frame(height: 22)
                            if item.tab == .today && badge > 0 {
                                Circle().fill(Theme.danger).frame(width: 7, height: 7).offset(x: 5, y: -1)
                            }
                            if item.tab == .drive && recording {
                                Circle().fill(Theme.danger).frame(width: 7, height: 7).offset(x: 5, y: -1)
                            }
                        }
                        Text(item.title).font(.geist(10.5, selected ? .semibold : .medium))
                    }
                    .foregroundStyle(selected ? Theme.text : Theme.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if selected {
                            Capsule().fill(Theme.raised).matchedGeometryEffect(id: "tab", in: namespace)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
}

/// Custom header used at the top of the main screens instead of the system large title.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                if let subtitle { Text(subtitle).eyebrow(Theme.accent) }
                Text(title).font(.display(36, .heavy)).foregroundStyle(Theme.text)
            }
            Spacer()
            trailing
        }
        .padding(.top, 8)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

/// Round icon button used in headers.
struct HeaderButton: View {
    let systemImage: String
    var tint: Color = Theme.text
    var dot: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.hairline))
                if dot { Circle().fill(Theme.danger).frame(width: 9, height: 9).offset(x: -2, y: 2) }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Cycles automatic → light → dark.
struct AppearanceButton: View {
    @AppStorage(Appearance.key) private var appearance = Appearance.system.rawValue

    var body: some View {
        let current = Appearance(rawValue: appearance) ?? .system
        HeaderButton(systemImage: current.symbol) {
            withAnimation(.easeInOut(duration: 0.25)) { appearance = current.next.rawValue }
        }
        .accessibilityLabel("Aspetto: \(current.label)")
    }
}
