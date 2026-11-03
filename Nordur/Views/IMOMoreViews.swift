import SwiftUI

// The rest of what Veðurstofa Íslands publishes for travellers: the forecasters'
// written forecasts and the state of the volcanoes (docs/IMO.md).

// MARK: - Written forecasts

enum IMOTextNames {
    static func name(_ text: IMOText) -> String {
        switch text.id {
        case 2: return String(localized: "Islanda, prossime 36 ore")
        case 3: return String(localized: "Reykjavík e dintorni")
        case 5: return String(localized: "Islanda, prossimi giorni")
        case 6: return String(localized: "Tendenza")
        case 9: return String(localized: "Situazione generale")
        case 30: return String(localized: "Altopiani centrali (Miðhálendið)")
        case 31: return String(localized: "Sud (Suðurland)")
        case 32: return String(localized: "Faxaflói e Borgarfjörður")
        case 33: return String(localized: "Breiðafjörður e Snæfellsnes")
        case 34: return String(localized: "Fiordi occidentali (Vestfirðir)")
        case 35: return String(localized: "Strandir e Nord-ovest")
        case 36: return String(localized: "Nord-est (Norðurland eystra)")
        case 37: return String(localized: "Est (Austurland að Glettingi)")
        case 38: return String(localized: "Fiordi orientali (Austfirðir)")
        case 39: return String(localized: "Sud-est (Suðausturland)")
        default: return text.title
        }
    }
}

extension AppModel {
    /// IMO's English duplicates (7, 27, 42) are not shown: the localized list already used them.
    var shownIMOTexts: [IMOText] {
        (imoTexts?.value ?? []).filter { !IMOTexts.english.values.contains($0.id) }
    }

    /// The written forecast of the place's region (the capital area's around Reykjavík).
    var regionalIMOText: IMOText? {
        guard let region = IMOTexts.region(near: activePlace.coordinate, stations: IMOForecast.stations) else { return nil }
        let texts = shownIMOTexts
        if region == IMOTexts.capitalArea, let capital = texts.first(where: { $0.id == IMOTexts.capitalArea }) { return capital }
        return texts.first { $0.id == region }
    }
}

/// In the Weather tab: what the forecaster writes for the place's region, and a link to all texts.
struct IMOTextCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let text = model.regionalIMOText ?? model.shownIMOTexts.first(where: { $0.id == 2 }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "text.quote").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.aurora)
                    Text(String(localized: "IL METEOROLOGO · \(IMOTextNames.name(text).uppercased())"))
                        .font(.mono(9.5, .semibold)).foregroundStyle(Theme.dim).lineLimit(1)
                }
                Text(text.content).font(.app(.subheadline)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                IMOTextFooter(text: text)
                NavigationLink {
                    IMOTextsView()
                } label: {
                    HStack(spacing: 4) {
                        Text("Tutte le previsioni scritte: regioni, prossimi giorni, mare")
                        Image(systemName: "chevron.right")
                    }
                    .font(.app(.caption, .semibold)).foregroundStyle(Theme.aurora)
                }
            }
            .padding(.vertical, 10)
            .overlay(alignment: .top) { Rule() }
        }
    }
}

struct IMOTextFooter: View {
    let text: IMOText

    var body: some View {
        let issued = text.created.map { Fmt.dayTime($0, in: .iceland) } ?? "—"
        let until = text.validTo.map { Fmt.dayTime($0, in: .iceland) }
        Text(until.map { String(localized: "vedur.is · scritta alle \(issued), valida fino a \($0)") }
             ?? String(localized: "vedur.is · scritta alle \(issued)"))
            .font(.app(.caption2)).foregroundStyle(Theme.faint)
    }
}

/// Every written forecast IMO publishes: country, next days, capital area, the ten
/// regions, the general synopsis and the sea areas.
struct IMOTextsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let texts = model.shownIMOTexts
        let regional = model.regionalIMOText?.id
        List {
            section(String(localized: "Islanda"), texts.filter { [2, 5, 6].contains($0.id) })
            section(String(localized: "Regioni"), texts.filter { $0.id == 3 || IMOTexts.regions.contains($0.id) }
                .sorted { ($0.id == regional ? -1 : $0.id) < ($1.id == regional ? -1 : $1.id) }, highlight: regional)
            section(String(localized: "Situazione generale"), texts.filter { $0.id == 9 })
            section(String(localized: "Mare (zone di pesca e navigazione)"), texts.filter { IMOTexts.seaAreas.contains($0.id) }, compact: true)
            Section {
                if texts.isEmpty { ErrorNote(message: model.errors[.imoTexts] ?? String(localized: "Previsioni scritte non ancora caricate.")) }
                Text("Testi scritti dai meteorologi di vedur.is. Le regioni e il mare sono pubblicati solo in islandese: qui sono tradotti automaticamente; i nomi dei luoghi restano originali.")
                    .font(.app(.caption)).foregroundStyle(.secondary)
                if let f = model.imoTexts { FreshnessLabel(date: f.date, isStale: f.isStale, source: String(localized: "vedur.is")) }
                LinkRow(title: String(localized: "Previsioni testuali su vedur.is"), subtitle: nil, url: "https://en.vedur.is/weather/forecasts/text/")
            }
        }
        .navigationTitle(String(localized: "Previsioni dei meteorologi"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refreshGlobal(force: true) }
    }

    @ViewBuilder
    private func section(_ title: String, _ texts: [IMOText], highlight: Int? = nil, compact: Bool = false) -> some View {
        if !texts.isEmpty {
            Section {
                ForEach(texts) { text in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(compact ? text.title : IMOTextNames.name(text)).font(.app(.subheadline, .semibold))
                            if text.id == highlight {
                                Text("QUI").font(.mono(8.5, .semibold)).foregroundStyle(Theme.bg)
                                    .padding(.horizontal, 5).padding(.vertical, 1).background(Theme.aurora, in: Capsule())
                            }
                        }
                        Text(text.content).font(.app(compact ? .caption : .subheadline)).foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        IMOTextFooter(text: text)
                    }
                    .padding(.vertical, 2)
                }
            } header: { Text(title).pinnedHeader() }
        }
    }
}

// MARK: - Volcanoes

extension Volcano {
    var color: Color {
        switch severity {
        case 3: return WarningColor.red.color
        case 2: return WarningColor.orange.color
        case 1: return WarningColor.yellow.color
        default: return Theme.aurora
        }
    }

    static func colourName(_ level: Int) -> String {
        switch level {
        case 3: return String(localized: "rosso")
        case 2: return String(localized: "arancione")
        case 1: return String(localized: "giallo")
        default: return String(localized: "verde")
        }
    }

    /// What the IMO alert level means (our wording, not a machine translation).
    static func levelMeaning(_ level: Int) -> String {
        switch level {
        case 3: return String(localized: "eruzione in corso o imminente")
        case 2: return String(localized: "attività vulcanica molto aumentata")
        case 1: return String(localized: "attività vulcanica sopra il normale")
        default: return String(localized: "attività normale")
        }
    }

    var aviationLevel: Int { ["GREEN": 0, "YELLOW": 1, "ORANGE": 2, "RED": 3][aviation?.uppercased() ?? ""] ?? 0 }
}

/// Quakes tab: the state of every volcano (IMO alert level and aviation colour
/// code), the ones above green first, with the line of the weekly report.
struct VolcanoSection: View {
    @Environment(AppModel.self) private var model
    @State private var showAll = false

    var body: some View {
        if let fetched = model.volcanoes {
            let status = fetched.value
            let all = status.sorted
            let active = all.filter { $0.severity > 0 }
            Section {
                if active.isEmpty {
                    Text("Tutti i \(all.count) vulcani sono a livello verde: attività normale.")
                        .font(.app(.subheadline)).foregroundStyle(Theme.text)
                }
                ForEach(active) { VolcanoRow(volcano: $0, distanceKm: Geo.distanceKm($0.coordinate, model.activePlace.coordinate)) }
                DisclosureGroup(isExpanded: $showAll) {
                    ForEach(all.filter { $0.severity == 0 }) { VolcanoRow(volcano: $0, distanceKm: Geo.distanceKm($0.coordinate, model.activePlace.coordinate), compact: true) }
                } label: {
                    Text("Vulcani a livello verde (\(all.filter { $0.severity == 0 }.count))").font(.app(.subheadline))
                }
                if let notes = status.reportNotes {
                    Text(notes).font(.app(.caption)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                }
                if let date = status.reportDate {
                    Text("Bollettino settimanale vedur.is del \(Fmt.dayTime(date, in: .iceland))").font(.app(.caption2)).foregroundStyle(Theme.faint)
                }
                FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: String(localized: "vedur.is"))
            } header: { Text("Stato dei vulcani").pinnedHeader() } footer: {
                Text("Livello di allerta vedur.is (verde → rosso) e codice colore per l'aviazione (VONA). Giallo: attività sopra il normale; arancione: attività aumentata, eruzione possibile; rosso: eruzione in corso o imminente.")
            }
        } else if let error = model.errors[.volcanoes] {
            Section { ErrorNote(message: error) } header: { Text("Stato dei vulcani").pinnedHeader() }
        }
    }
}

struct VolcanoRow: View {
    let volcano: Volcano
    let distanceKm: Double
    var compact = false

    private func alertLine(_ level: Int) -> String {
        var line = String(localized: "Allerta vedur.is: \(Volcano.colourName(level))")
        line += " – " + Volcano.levelMeaning(level)
        if let since = volcano.levelSince { line += " · " + String(localized: "dal \(Fmt.day(since))") }
        return line
    }

    private var aviationLine: String {
        var line = String(localized: "Aviazione: \(Volcano.colourName(volcano.aviationLevel))")
        if let since = volcano.aviationSince { line += " · " + String(localized: "dal \(Fmt.day(since))") }
        return line
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "triangle.fill").font(.system(size: 10)).foregroundStyle(volcano.color)
                Text(volcano.name).font(.app(.subheadline, .semibold))
                Spacer()
                Text("\(Int(distanceKm.rounded())) km").font(.app(.caption)).foregroundStyle(.secondary)
            }
            if !compact {
                if let level = volcano.level {
                    Text(alertLine(level)).font(.app(.caption)).foregroundStyle(Theme.text)
                }
                Text(aviationLine).font(.app(.caption)).foregroundStyle(Theme.dim)
                if let report = volcano.report {
                    Text(report).font(.app(.caption)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
