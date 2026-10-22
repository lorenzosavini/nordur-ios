import SwiftUI

/// The app's language, chosen here instead of following the phone's. iOS
/// reads it once at launch (AppleLanguages for this app only), so the change
/// applies when the app is opened again.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, it, en

    static let key = "app.language"
    var id: String { rawValue }

    /// Each language in its own name, so it can be found whatever the app shows now.
    var label: String {
        switch self {
        case .system: return String(localized: "Come il telefono")
        case .it: return "Italiano"
        case .en: return "English"
        }
    }

    func apply() {
        let defaults = UserDefaults.standard
        if self == .system { defaults.removeObject(forKey: "AppleLanguages") } else { defaults.set([rawValue], forKey: "AppleLanguages") }
    }

    /// The language the app is showing now.
    static var showing: String { Bundle.main.preferredLocalizations.first ?? "it" }
}

struct LanguageSection: View {
    @AppStorage(AppLanguage.key) private var language = AppLanguage.system.rawValue
    @State private var askRestart = false

    var body: some View {
        Section {
            Picker(selection: $language) {
                ForEach(AppLanguage.allCases) { Text($0.label).tag($0.rawValue) }
            } label: {
                Label("Lingua", systemImage: "globe")
            }
            .pickerStyle(.menu)
            .onChange(of: language) { _, value in
                let chosen = AppLanguage(rawValue: value) ?? .system
                chosen.apply()
                let target = chosen == .system ? (Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "it") : chosen.rawValue
                askRestart = target != AppLanguage.showing
            }
        } header: { Text("Lingua").pinnedHeader() } footer: {
            Text("La nuova lingua si vede quando riapri l'app. Le notizie e gli avvisi delle fonti islandesi restano nella lingua in cui li pubblicano, con la traduzione dove c'è.")
        }
        .alert("Riapri l'app", isPresented: $askRestart) {
            Button("Chiudi ora") { exit(0) }
            Button("Più tardi", role: .cancel) {}
        } message: {
            Text("La lingua cambia alla prossima apertura. Chiudi l'app ora e riaprila dalla schermata Home.")
        }
    }
}
