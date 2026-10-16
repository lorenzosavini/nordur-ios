import SwiftUI
import MapKit

struct MapScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(TripStore.self) private var trip

    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 64.9, longitude: -18.6),
        span: MKCoordinateSpan(latitudeDelta: 5.5, longitudeDelta: 14)))
    @AppStorage("map.warnings") private var showWarnings = true
    @AppStorage("map.roads") private var showRoads = true
    @AppStorage("map.quakes") private var showQuakes = false
    @AppStorage("map.trip") private var showTrip = true
    @State private var selectedStation: RoadStation?
    @State private var selectedWarning: WeatherWarning?

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                UserAnnotation()

                if showWarnings {
                    ForEach(model.warnings?.value ?? []) { warning in
                        ForEach(Array(warning.polygons.enumerated()), id: \.offset) { item in
                            MapPolygon(coordinates: item.element.map(\.clCoordinate))
                                .foregroundStyle(warning.color.color.opacity(warning.isActive() ? 0.28 : 0.12))
                                .stroke(warning.color.color, lineWidth: 1)
                        }
                    }
                }

                if showQuakes {
                    ForEach((model.quakes?.value ?? []).filter { $0.magnitude >= 1 }) { quake in
                        Annotation("", coordinate: quake.coordinate.clCoordinate) {
                            Circle()
                                .fill(quake.risk.color.opacity(0.75))
                                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 0.5))
                                .frame(width: CGFloat(6 + quake.magnitude * 5), height: CGFloat(6 + quake.magnitude * 5))
                        }
                    }
                }

                if showRoads, let network = model.roads?.value {
                    ForEach(network.stations.filter { !$0.isOutdated && $0.coordinate != nil }) { station in
                        Annotation(station.name, coordinate: station.coordinate!.clCoordinate) {
                            Button {
                                selectedStation = station
                            } label: {
                                ZStack {
                                    Circle().fill(network.worstRisk(of: station).color).frame(width: 22, height: 22)
                                    Text("\(Int((station.Vindhvida ?? station.Vindhradi ?? 0).rounded()))")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.black)
                                }
                            }
                        }
                        .annotationTitles(.hidden)
                    }
                }

                if showTrip {
                    ForEach(Array(trip.stops.enumerated()), id: \.element.id) { item in
                        Marker("\(item.offset + 1). \(item.element.place.name)", systemImage: item.element.transport.symbol,
                               coordinate: item.element.place.coordinate.clCoordinate)
                            .tint(.indigo)
                    }
                    if trip.stops.count >= 2 {
                        MapPolyline(coordinates: trip.stops.map(\.place.coordinate.clCoordinate))
                            .stroke(.indigo, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .safeAreaInset(edge: .bottom) { legend }
            .navigationTitle("Mappa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Allerte meteo", systemImage: "exclamationmark.triangle", isOn: $showWarnings)
                        Toggle("Stazioni stradali", systemImage: "road.lanes", isOn: $showRoads)
                        Toggle("Terremoti 48 h", systemImage: "waveform.path.ecg", isOn: $showQuakes)
                        Toggle("Il mio viaggio", systemImage: "point.topleft.down.to.point.bottomright.curvepath", isOn: $showTrip)
                    } label: {
                        Image(systemName: "square.3.layers.3d")
                    }
                }
            }
            .sheet(item: $selectedStation) { station in
                NavigationStack {
                    List {
                        if let network = model.roads?.value {
                            StationRow(station: station, network: network,
                                       distance: station.coordinate.map { Geo.distanceKm(model.activePlace.coordinate, $0) })
                        }
                        let here = station.coordinate.map { c in (model.warnings?.value ?? []).filter { $0.covers(c) } } ?? []
                        if !here.isEmpty {
                            Section("Allerte in questa zona") {
                                ForEach(here) { WarningRow(warning: $0) }
                            }
                        }
                    }
                    .navigationTitle(station.name)
                    .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium])
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(Risk.allCases, id: \.self) { risk in
                HStack(spacing: 3) {
                    Circle().fill(risk.color).frame(width: 8, height: 8)
                    Text(risk.label).font(.caption2)
                }
            }
            Spacer(minLength: 0)
            Text("n° = raffica m/s").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal)
        .padding(.bottom, 6)
    }
}
