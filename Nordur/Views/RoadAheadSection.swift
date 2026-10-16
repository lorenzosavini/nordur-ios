import SwiftUI

/// "La strada davanti a te": live road stations, segments, warnings and
/// webcams ahead while driving, along the planned route if a destination is set.
struct RoadAheadSection: View {
    @Environment(AppModel.self) private var model
    @Environment(DriveRecorder.self) private var recorder
    @State private var watch = RoadWatch.shared
    @State private var picking = false

    private var position: Coordinate? {
        recorder.session?.points.last?.coordinate ?? model.location.coordinate ?? LocationManager.lastKnown
    }

    var body: some View {
        Section {
            HStack {
                Image(systemName: "flag.checkered")
                VStack(alignment: .leading, spacing: 1) {
                    Text(watch.destination.map { "Verso \($0.name)" } ?? "Nessuna destinazione").font(.subheadline.weight(.semibold))
                    if let remaining = watch.remainingKm {
                        let minutes = watch.routeTotalKm > 0 ? Int(watch.routeTravelTime / 60 * remaining / watch.routeTotalKm) : 0
                        Text("Mancano \(Fmt.number(remaining, unit: "km")) · circa \(Fmt.duration(Double(minutes) * 60))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Senza destinazione: stazioni nella direzione di marcia, entro 60 km.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if watch.isPlanning { ProgressView() }
                Menu {
                    Button("Scegli destinazione", systemImage: "mappin.and.ellipse") { picking = true }
                    if watch.destination != nil {
                        Button("Rimuovi destinazione", systemImage: "xmark", role: .destructive) {
                            Task { await watch.setDestination(nil, from: position) }
                        }
                    }
                    Button("Aggiorna ora", systemImage: "arrow.clockwise") {
                        Task {
                            let course = recorder.session?.points.last?.course
                            await watch.refresh(position: position, course: course, speedKmh: recorder.speedKmh, force: true)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
            }
            if let error = watch.planError { ErrorNote(message: error) }

            ForEach(watch.warningsAhead) { warning in
                HStack { WarningBadge(color: warning.color); Text(warning.headline).font(.caption) }
            }

            if watch.ahead.isEmpty {
                Text(recorder.isRecording ? "Nessuna stazione stradale davanti a te nel raggio controllato." :
                        "Disponibile durante la registrazione di un percorso.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(watch.ahead) { item in
                AheadRow(item: item)
            }

            if let last = watch.lastUpdate {
                Text("Calcolato \(Fmt.relative(last)) · dati strade \(watch.lastRoadsFetch.map { Fmt.relative($0) } ?? "–")")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if !watch.changes.isEmpty {
                DisclosureGroup("Cambiamenti rilevati (\(watch.changes.count))") {
                    ForEach(watch.changes, id: \.self) { Text($0).font(.caption2) }
                }
                .font(.caption)
            }
        } header: {
            Text("La strada davanti a te").eyebrow()
        }
        .sheet(isPresented: $picking) {
            PlacePicker(allowCurrentLocation: false) { choice in
                if case .place(let place) = choice {
                    Task { await watch.setDestination(place, from: position) }
                }
            }
        }
        .task(id: recorder.isRecording) {
            if recorder.isRecording { await watch.refresh(position: position, course: nil, speedKmh: 0, force: true) }
        }
    }
}

struct AheadRow: View {
    let item: AheadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.kmAhead < 1 ? "qui" : "\(Int(item.kmAhead)) km")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .frame(width: 52, alignment: .leading)
                Circle().fill(item.risk.color).frame(width: 9, height: 9)
                Text(item.station.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(item.kmAhead < 1 ? "" : "≈ \(item.etaMinutes) min").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Label("\(Fmt.ms(item.station.Vindhradi)) / \(Fmt.ms(item.station.Vindhvida))", systemImage: "wind")
                    .foregroundStyle(item.station.windRisk == .ok ? Color.secondary : item.station.windRisk.color)
                Label("asfalto \(Fmt.temp(item.station.Veghiti))", systemImage: "road.lanes")
                    .foregroundStyle(item.station.surfaceRisk == .ok ? Color.secondary : item.station.surfaceRisk.color)
                Label(Fmt.temp(item.station.Hiti), systemImage: "thermometer.medium").foregroundStyle(.secondary)
            }
            .font(.caption2)
            .labelStyle(CompactLabelStyle())
            .padding(.leading, 52)
            ForEach(item.segments.filter { ($0.risk ?? .ok) > .ok }) { segment in
                Text("\(segment.conditionItalian) – \(segment.name)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle((segment.risk ?? .ok).color)
                    .padding(.leading, 52)
            }
            if let webcam = item.webcam {
                NavigationLink {
                    WebcamSiteView(site: webcam)
                } label: {
                    Label("Webcam \(webcam.name)", systemImage: "video.fill").font(.caption2)
                }
                .padding(.leading, 52)
            }
        }
    }
}
