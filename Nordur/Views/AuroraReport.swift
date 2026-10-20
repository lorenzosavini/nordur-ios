import SwiftUI

/// "I see it / I don't": the aurora report, always one tap away (Aurora tab,
/// Today). Signing in is asked for only when you tap.
struct AuroraReportBar: View {
    @Environment(AppModel.self) private var model
    @Environment(Account.self) private var account
    var compact = false
    @State private var reporting: SightingSheet.Kind?
    @State private var signingIn = false

    var body: some View {
        HStack(spacing: 10) {
            button(String(localized: "VEDO L'AURORA"), "sparkles", filled: true) { open(.seen) }
                .accessibilityIdentifier("aurora.report.seen")
            button(String(localized: "NON LA VEDO"), "eye.slash", filled: false) { open(.notSeen) }
                .accessibilityIdentifier("aurora.report.notSeen")
        }
        .sheet(item: $reporting, onDismiss: { Task { await model.refreshSightings() } }) { kind in
            SightingSheet(coordinate: model.location.coordinate ?? model.activePlace.coordinate, kind: kind)
        }
        .sheet(isPresented: $signingIn) { AccountView() }
    }

    private func open(_ kind: SightingSheet.Kind) {
        Haptics.tap()
        if account.isSignedIn { reporting = kind } else { signingIn = true }
    }

    private func button(_ title: String, _ symbol: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.mono(compact ? 11.5 : 13, .bold)).tracking(0.5)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity).frame(height: compact ? 44 : 52)
                .foregroundStyle(filled ? Color.black : Theme.text)
                .background(filled ? Theme.aurora : Theme.bg.opacity(0.94))
                .overlay(Rectangle().strokeBorder(filled ? Theme.aurora : Theme.rule, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

/// The Aurora tab: the forecast, with the report always at hand at the bottom.
struct AuroraTab: View {
    var body: some View {
        NavigationStack {
            AuroraView()
                .toolbar(.hidden, for: .navigationBar)
                .overlay(alignment: .topTrailing) { NightVisionButton().padding(.top, 8).padding(.trailing, 14) }
                .safeAreaInset(edge: .bottom) {
                    AuroraReportBar()
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                }
        }
    }
}
