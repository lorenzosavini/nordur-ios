import SwiftUI
import StoreKit

/// The purchase screen: what Pro opens, the App Store products with their
/// prices, restore and redeem a code. Prices, trials and offers come from App
/// Store Connect; which features are Pro from the admin panel.
struct PaywallView: View {
    var feature: Feature?
    var inline = false
    @Environment(\.dismiss) private var dismiss
    @State private var store = Entitlements.shared
    @State private var redeeming = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NORÐUR PRO").font(.mono(11, .semibold)).tracking(1).foregroundStyle(Theme.accent)
                    Text(store.paywallText(\.title) ?? String(localized: "Sblocca tutto Norður"))
                        .font(.display(34, .bold)).foregroundStyle(Theme.text)
                    if let feature {
                        Label(String(localized: "\(feature.label) fa parte di Pro"), systemImage: "lock.fill")
                            .font(.app(.subheadline, .semibold)).foregroundStyle(Theme.accent)
                    }
                    Text(store.paywallText(\.text) ?? String(localized: "Un solo acquisto per tutte le funzioni qui sotto. Avvisi meteo e strade, chiusure, terremoti e numeri di emergenza restano sempre gratuiti."))
                        .font(.app(.subheadline)).foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(Color.clear)

            if !store.proFeatures.isEmpty {
                Section {
                    ForEach(store.proFeatures) { f in
                        Label(f.label, systemImage: f.symbol).foregroundStyle(Theme.text)
                    }
                } header: { Text("Con Pro").pinnedHeader() }
            }

            Section {
                if store.isPro {
                    Label("Pro è attivo su questo iPhone", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.aurora)
                } else if store.products.isEmpty {
                    Text(store.config.products.isEmpty ? String(localized: "Gli acquisti non sono ancora disponibili.") : String(localized: "Caricamento dei prezzi dall'App Store…"))
                        .foregroundStyle(Theme.dim)
                } else {
                    ForEach(store.products, id: \.id) { product in
                        Button {
                            Task { await store.buy(product) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(product.displayName).font(.app(.headline)).foregroundStyle(Theme.text)
                                    Text(Self.period(product)).font(.app(.caption)).foregroundStyle(Theme.dim)
                                }
                                Spacer()
                                Text(product.displayPrice).font(.metric(22, .semibold)).foregroundStyle(Theme.accent)
                            }
                        }
                        .disabled(store.purchasing)
                    }
                }
                if let error = store.lastError {
                    Text(error).font(.app(.caption)).foregroundStyle(Theme.danger)
                }
            } header: { Text("Acquista").pinnedHeader() } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Il pagamento è addebitato sull'Apple ID. Gli abbonamenti si rinnovano da soli se non disattivati almeno 24 ore prima della scadenza, da Impostazioni › Apple ID › Abbonamenti.")
                    HStack(spacing: 14) {
                        Link("Termini d'uso", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        Link("Privacy", destination: URL(string: "https://nordur-api.vercel.app/privacy.html")!)
                    }
                }
            }

            Section {
                Button { Task { await store.restore() } } label: { Label("Ripristina acquisti", systemImage: "arrow.clockwise") }
                    .disabled(store.purchasing)
                Button { redeeming = true } label: { Label("Riscatta un codice", systemImage: "giftcard") }
            }
        }
        .themedList()
        .offerCodeRedemption(isPresented: $redeeming) { _ in Task { await store.refreshPurchases() } }
        .overlay { if store.purchasing { ProgressView().controlSize(.large) } }
        .task { await store.refresh() }
        .toolbar {
            if !inline { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
        }
        .navigationTitle(inline ? (feature?.label ?? "Pro") : "")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "Acquisto unico", "Ogni anno"…
    static func period(_ product: Product) -> String {
        guard let unit = product.subscription?.subscriptionPeriod else {
            return product.type == .nonConsumable ? String(localized: "Acquisto unico, per sempre") : ""
        }
        switch unit.unit {
        case .year: return unit.value == 1 ? String(localized: "Ogni anno") : String(localized: "Ogni \(unit.value) anni")
        case .month: return unit.value == 1 ? String(localized: "Ogni mese") : String(localized: "Ogni \(unit.value) mesi")
        case .week: return String(localized: "Ogni settimana")
        case .day: return String(localized: "Ogni giorno")
        @unknown default: return ""
        }
    }
}

/// A screen that is Pro or off: the screen itself when allowed, otherwise the
/// purchase screen in its place (or a short note when switched off).
struct ProGate<Content: View>: View {
    let feature: Feature
    @ViewBuilder var content: () -> Content
    @State private var store = Entitlements.shared

    var body: some View {
        if store.allows(feature) {
            content()
        } else if store.rule(feature) == .off {
            ContentUnavailableView(feature.label, systemImage: "pause.circle", description: Text("Non disponibile al momento."))
        } else {
            PaywallView(feature: feature, inline: true)
        }
    }
}

/// A small lock next to a row whose feature needs Pro (nothing once bought).
struct ProLock: View {
    let feature: Feature
    @State private var store = Entitlements.shared
    var body: some View {
        if store.locked(feature) {
            Text("PRO").font(.mono(9, .bold)).foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 3))
                .accessibilityLabel(Text("Richiede Pro"))
        }
    }
}

/// Settings › Norður Pro.
struct ProSettingsSection: View {
    @State private var store = Entitlements.shared
    var body: some View {
        if store.sellsPro || store.isPro {
            Section {
                if store.isPro {
                    Label(store.grantedUntil.map { String(localized: "Pro attivo fino al \(Fmt.day($0))") } ?? String(localized: "Pro attivo"), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Theme.aurora)
                }
                NavigationLink { PaywallView(inline: true) } label: {
                    Label(store.isPro ? String(localized: "Il tuo acquisto") : String(localized: "Passa a Pro"), systemImage: "star.circle")
                }
            } header: { Text("Norður Pro").pinnedHeader() }
        }
    }
}

/// The notice from the admin panel, at the top of Today; closed once, it stays closed.
struct NoticeBanner: View {
    @State private var store = Entitlements.shared
    var body: some View {
        if let n = store.announcement {
            let color = n.level == "danger" ? Theme.danger : n.level == "warning" ? Theme.caution : Theme.accent
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: n.level == "info" ? "info.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(n.title).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text)
                    if !n.text.isEmpty { Text(n.text).font(.app(.caption)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true) }
                    if let url = n.url { Link("Apri", destination: url).font(.app(.caption, .semibold)) }
                }
                Spacer(minLength: 0)
                Button { withAnimation { store.closeNotice(n.id) } } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.dim)
                }
                .accessibilityLabel(Text("Chiudi"))
            }
            .padding(12)
            .background(Theme.surface)
            .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        }
    }
}
