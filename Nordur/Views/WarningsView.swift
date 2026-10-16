import SwiftUI
import MapKit

struct WarningsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            let warnings = model.warnings?.value ?? []
            Section {
                if let fetched = model.warnings {
                    FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: "Veðurstofa Íslands")
                }
                ErrorNote(message: model.errors[.warnings])
                if warnings.isEmpty && model.warnings != nil {
                    Label("Nessuna allerta meteo attiva", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
            }
            ForEach(warnings) { warning in
                NavigationLink {
                    WarningDetail(warning: warning)
                } label: {
                    WarningRow(warning: warning, coversYou: warning.covers(model.activePlace.coordinate))
                }
            }
            Section("Cosa significano i colori") {
                Text("Giallo: possibili disagi.
Arancione: impatti significativi, valuta di rimandare.
Rosso: evento estremo, non metterti in viaggio.")
                    .font(.caption)
                LinkRow(title: "Allerte su vedur.is", subtitle: nil, url: "https://en.vedur.is/weather/forecasts/areas/")
            }
        }
        .navigationTitle("Allerte meteo")
        .refreshable { await model.refreshGlobal(force: true) }
    }
}

struct WarningRow: View {
    let warning: WeatherWarning
    var coversYou: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: warning.symbol)
                .foregroundStyle(warning.color.color)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    WarningBadge(color: warning.color)
                    if coversYou {
                        Text("LA TUA ZONA").font(.caption2.weight(.bold)).foregroundStyle(.red)
                    }
                }
                Text(warning.headline).font(.subheadline.weight(.semibold))
                Text(warning.region).font(.caption).foregroundStyle(.secondary)
                Text("\(Fmt.dayTime(warning.onset, in: .iceland)) → \(Fmt.dayTime(warning.expires, in: .iceland))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct WarningDetail: View {
    let warning: WeatherWarning

    var body: some View {
        List {
            Section {
                WarningRow(warning: warning)
            }
            if !warning.polygons.isEmpty {
                Section {
                    Map(initialPosition: .automatic) {
                        ForEach(Array(warning.polygons.enumerated()), id: \.offset) { item in
                            MapPolygon(coordinates: item.element.map(\.clCoordinate))
                                .foregroundStyle(warning.color.color.opacity(0.3))
                                .stroke(warning.color.color, lineWidth: 2)
                        }
                    }
                    .frame(height: 240)
                    .listRowInsets(EdgeInsets())
                }
            }
            Section("Descrizione (IMO)") {
                Text(warning.details)
                if let icelandic = warning.headlineIcelandic {
                    Text(icelandic).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Dettagli") {
                LabeledContent("Evento", value: warning.event)
                LabeledContent("Gravità", value: warning.severity ?? "–")
                LabeledContent("Certezza", value: warning.certainty ?? "–")
                LabeledContent("Inizio", value: Fmt.dayTime(warning.onset, in: .iceland))
                LabeledContent("Fine", value: Fmt.dayTime(warning.expires, in: .iceland))
            }
        }
        .navigationTitle(warning.color.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}
