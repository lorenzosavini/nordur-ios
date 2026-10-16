import SwiftUI
import MapKit

struct QuakesView: View {
    @Environment(AppModel.self) private var model
    @State private var minimumMagnitude = 1.0

    private var filtered: [Quake] {
        (model.quakes?.value ?? []).filter { $0.magnitude >= minimumMagnitude }
    }

    var body: some View {
        List {
            Section {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 64.9, longitude: -18.6),
                    span: MKCoordinateSpan(latitudeDelta: 5.5, longitudeDelta: 14)))) {
                    ForEach(filtered) { quake in
                        Annotation("", coordinate: quake.coordinate.clCoordinate) {
                            Circle()
                                .fill(quake.risk.color.opacity(0.7))
                                .frame(width: CGFloat(6 + quake.magnitude * 5), height: CGFloat(6 + quake.magnitude * 5))
                        }
                    }
                }
                .frame(height: 260)
                .listRowInsets(EdgeInsets())

                Picker("Magnitudo minima", selection: $minimumMagnitude) {
                    Text("Tutte").tag(0.0)
                    Text("M1+").tag(1.0)
                    Text("M2+").tag(2.0)
                    Text("M3+").tag(3.0)
                }
                .pickerStyle(.segmented)
                if let fetched = model.quakes {
                    FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: "Veðurstofa Íslands")
                }
                ErrorNote(message: model.errors[.quakes])
            }

            Section("\(filtered.count) scosse – ultime 48 ore") {
                ForEach(filtered) { quake in
                    HStack {
                        Text("M\(Fmt.number(quake.magnitude, decimals: 1))")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(quake.risk == .ok ? Color.primary : quake.risk.color)
                            .frame(width: 58, alignment: .leading)
                        VStack(alignment: .leading) {
                            Text(quake.region).font(.subheadline)
                            Text("\(Fmt.dayTime(quake.date, in: .iceland)) · prof. \(Fmt.number(quake.depth, decimals: 1, unit: "km"))\(quake.reviewed ? "" : " · automatico")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(Geo.distanceKm(quake.coordinate, model.activePlace.coordinate))) km")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Vulcani ed eruzioni") {
                Text("Zone di pericolo e chiusure: IMO e Protezione Civile.")
                    .font(.caption).foregroundStyle(.secondary)
                LinkRow(title: "Vedur.is – Terremoti", subtitle: "Mappa ufficiale in tempo reale", url: "https://en.vedur.is/earthquakes-and-volcanism/earthquakes/", systemImage: "waveform.path.ecg")
                LinkRow(title: "Vedur.is – Vulcani e mappa dei pericoli", subtitle: "Livelli di allerta aviazione e pericolo", url: "https://en.vedur.is/earthquakes-and-volcanism/", systemImage: "mountain.2.fill")
                LinkRow(title: "Previsione gas vulcanici", subtitle: "Dispersione SO₂ durante le eruzioni", url: "https://en.vedur.is/pollution-and-radiation/volcanic-gas/", systemImage: "aqi.high")
                LinkRow(title: "Protezione Civile (Almannavarnir)", subtitle: "Evacuazioni e zone chiuse", url: "https://www.almannavarnir.is/english/", systemImage: "shield.lefthalf.filled")
            }
        }
        .navigationTitle("Terremoti e vulcani")
        .refreshable { await model.refreshGlobal(force: true) }
    }
}
