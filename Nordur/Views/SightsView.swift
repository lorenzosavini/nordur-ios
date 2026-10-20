import SwiftUI
import MapKit

/// Everything worth seeing around a place, on a map and as a list: the app's
/// own list of the main sights (TOP) and the places of OpenStreetMap.
struct SightsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Around this place (a trip stop); otherwise the place shown in the app.
    var center: Place?
    var inSheet = false
    var radiusKm: Double = 60

    @State private var kind: AttractionKind?
    @State private var topOnly = false
    @State private var query = ""
    @State private var selected: Attraction?

    var body: some View {
        if inSheet {
            NavigationStack {
                content.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            }
        } else {
            content
        }
    }

    private var content: some View {
        let place = center ?? model.activePlace
        let near = model.spots
            .map { NearSight(sight: $0, km: Geo.distanceKm(place.coordinate, $0.coordinate)) }
            .filter { item in
                item.km <= radiusKm && (kind == nil || item.sight.kind == kind) && (!topOnly || item.sight.isTop || item.sight.notable)
                    && (query.isEmpty || item.sight.name.localizedCaseInsensitiveContains(query) || item.sight.region.localizedCaseInsensitiveContains(query))
            }
            .sorted { a, b in
                // The main sights first, then by distance.
                let ra = a.sight.isTop ? 0 : a.sight.notable ? 1 : 2, rb = b.sight.isTop ? 0 : b.sight.notable ? 1 : 2
                return ra != rb ? ra < rb : a.km < b.km
            }
        return List {
            Section {
                ExpandableMap(height: 280, title: String(localized: "Da vedere vicino a \(place.name)")) {
                    Map(initialPosition: .region(MKCoordinateRegion(center: place.coordinate.clCoordinate,
                                                                    span: MKCoordinateSpan(latitudeDelta: radiusKm / 70, longitudeDelta: radiusKm / 30)))) {
                        Marker(place.name, systemImage: "bed.double.fill", coordinate: place.coordinate.clCoordinate).tint(.indigo)
                        ForEach(Array(near.prefix(250))) { item in
                            Annotation(item.sight.isTop ? item.sight.name : "", coordinate: item.sight.coordinate.clCoordinate) {
                                Button { selected = item.sight } label: { SightPin(sight: item.sight) }
                                    .buttonStyle(.plain)
                            }
                        }
                        UserAnnotation()
                    }
                }
                .listRowInsets(EdgeInsets())
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip(String(localized: "Tutto"), symbol: "square.grid.2x2", selected: kind == nil) { kind = nil }
                        ForEach(AttractionKind.allCases.filter { $0 != .shop }) { k in
                            chip(k.label, symbol: k.symbol, selected: kind == k) { kind = kind == k ? nil : k }
                        }
                    }
                }
                Toggle("Solo i più famosi", isOn: $topOnly).tint(Theme.accent)
            }
            Section {
                if near.isEmpty {
                    EmptyState(symbol: "binoculars", title: String(localized: "Niente da mostrare"),
                               message: String(localized: "Prova a togliere i filtri."))
                } else {
                    ForEach(Array(near.prefix(150))) { item in
                        Button { selected = item.sight } label: { SightRow(sight: item.sight, km: item.km) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("sight.row")
                    }
                }
            } header: {
                Text(String(localized: "\(near.count) luoghi entro \(Int(radiusKm)) km")).pinnedHeader()
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TOP: i luoghi principali scelti dall'app, con tempi di visita e avvertenze. Gli altri vengono da OpenStreetMap (cascate, belvedere, sorgenti calde, grotte, musei, piscine…).")
                    if model.sights == nil, let error = model.errors[.sights] {
                        Text(String(localized: "OpenStreetMap non ancora scaricato: \(error)")).foregroundStyle(Theme.caution)
                    } else if let sights = model.sights {
                        FreshnessLabel(date: sights.date, isStale: sights.isStale, source: String(localized: "OpenStreetMap"))
                    }
                }
            }
        }
        .themedList()
        .navigationTitle("Da vedere")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: String(localized: "Cascata, grotta, nome…"))
        .task { await model.loadSights() }
        .sheet(item: $selected) { sight in
            SightDetail(sight: sight, from: place).presentationDetents([.medium, .large])
        }
    }

    private func chip(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            action()
        } label: {
            Label(title, systemImage: symbol)
                .font(.mono(10.5, .semibold))
                .padding(.horizontal, 10).frame(height: 30)
                .background(selected ? Theme.accent : Theme.surface)
                .foregroundStyle(selected ? Theme.onAccent : Theme.text)
        }
        .buttonStyle(.plain)
    }
}

struct NearSight: Identifiable {
    let sight: Attraction
    let km: Double
    var id: String { sight.id }
}

extension AttractionKind {
    var tint: Color {
        switch self {
        case .waterfall: return .blue
        case .beach: return .gray
        case .glacier: return .cyan
        case .geothermal: return .orange
        case .canyon, .landscape: return .green
        case .bath: return .teal
        case .town: return .purple
        case .wildlife: return .mint
        case .shop: return .yellow
        }
    }

    var uiTint: UIColor { UIColor(tint) }
}

struct SightPin: View {
    let sight: Attraction

    var body: some View {
        let size: CGFloat = sight.isTop ? 26 : 18
        Image(systemName: sight.kind.symbol)
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(sight.kind.tint))
            .overlay(Circle().strokeBorder(.white, lineWidth: sight.isTop ? 2 : 1))
            .shadow(radius: 1)
    }
}

struct SightRow: View {
    let sight: Attraction
    let km: Double?
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Photos for the best-known places; the others show the illustration of their kind.
            PlaceThumb(place: sight.place, kind: sight.kind, size: 56, photo: sight.isTop || sight.notable)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(sight.name).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    if sight.isTop {
                        Text("TOP").font(.mono(8.5, .semibold)).foregroundStyle(Theme.accent)
                            .padding(.horizontal, 4).overlay(Rectangle().strokeBorder(Theme.accent.opacity(0.6)))
                    }
                    Spacer()
                    if let km {
                        Text("\(Fmt.number(km, decimals: km < 10 ? 1 : 0)) km").font(.mono(10.5, .semibold)).foregroundStyle(Theme.dim)
                    }
                }
                Text("\(sight.isTop ? sight.kind.label : sight.region) · ~\(Fmt.duration(Double(sight.minutes) * 60))")
                    .font(.app(.caption)).foregroundStyle(Theme.dim).lineLimit(1)
                if let caution = sight.caution {
                    Text(caution).font(.app(.caption2)).foregroundStyle(Theme.caution).lineLimit(2)
                } else if let detail = sight.detail {
                    Text(detail).font(.app(.caption2)).foregroundStyle(Theme.faint).lineLimit(2)
                }
            }
            if let trailing { trailing }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// A place to visit: what it is, how far, the weather there now, directions,
/// and adding it to a stop of the trip.
struct SightDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(TripStore.self) private var trip
    @Environment(\.dismiss) private var dismiss
    let sight: Attraction
    let from: Place
    @State private var added: String?

    var body: some View {
        let c = sight.coordinate
        let nearestStop = trip.stops.min { Geo.distanceKm($0.place.coordinate, c) < Geo.distanceKm($1.place.coordinate, c) }
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text((sight.isTop ? sight.kind.label : sight.region).uppercased()).font(.mono(10, .semibold)).foregroundStyle(Theme.accent)
                        Text(sight.name).font(.display(28, .bold)).foregroundStyle(Theme.text)
                        Text(String(localized: "\(Int(Geo.distanceKm(from.coordinate, c).rounded())) km in linea d'aria da \(from.name) · visita ~\(Fmt.duration(Double(sight.minutes) * 60))"))
                            .font(.mono(10)).foregroundStyle(Theme.dim)
                        if let detail = sight.detail {
                            Text(detail).font(.app(.caption)).foregroundStyle(Theme.dim).padding(.top, 4)
                        }
                        if let caution = sight.caution {
                            Label(caution, systemImage: "exclamationmark.triangle").font(.app(.caption)).foregroundStyle(Theme.caution).padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    if trip.stops.isEmpty {
                        Text("Aggiungi una tappa al viaggio per mettere questo luogo nel programma.").font(.app(.caption)).foregroundStyle(Theme.dim)
                    } else {
                        Menu {
                            ForEach(trip.stops) { stop in
                                Button("\(stop.place.name) · \(Fmt.day(stop.date, in: .iceland)) · \(Int(Geo.distanceKm(stop.place.coordinate, c).rounded())) km") {
                                    add(to: stop)
                                }
                            }
                        } label: {
                            Label(String(localized: "Aggiungi al viaggio"), systemImage: "plus.circle.fill").font(.app(.headline))
                        }
                        if let nearestStop {
                            Button { add(to: nearestStop) } label: {
                                Label(String(localized: "Aggiungi alla tappa più vicina: \(nearestStop.place.name)"), systemImage: "bed.double")
                            }
                        }
                        if let added {
                            Label(String(localized: "Aggiunto a \(added): trovi giorno e ora nella tappa"), systemImage: "checkmark.circle.fill")
                                .font(.app(.caption, .semibold)).foregroundStyle(Theme.aurora)
                        }
                    }
                } header: { Text("Viaggio").pinnedHeader() }
                Section {
                    DirectionsRows(to: c)
                }
            }
            .themedList()
            .navigationTitle("Da vedere")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
        }
    }

    private func add(to stop: TripStop) {
        trip.upsert(.next(at: sight.place, kind: sight.kind, minutes: sight.minutes, in: stop), in: stop.id)
        Haptics.result(true)
        added = stop.place.name
    }
}
