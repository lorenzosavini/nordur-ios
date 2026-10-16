import SwiftUI

@main
struct NordurApp: App {
    @State private var model = AppModel()
    @State private var trip = TripStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(trip)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                Notifier.scheduleRefresh()
            case .active:
                Task { await model.refreshGlobal() }
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(Notifier.refreshTaskID)) {
            await Notifier.runChecks()
            Notifier.scheduleRefresh()
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Oggi", systemImage: "sun.horizon.fill") }
            WeatherView()
                .tabItem { Label("Meteo", systemImage: "cloud.sun.rain.fill") }
            MapScreen()
                .tabItem { Label("Mappa", systemImage: "map.fill") }
            TripView()
                .tabItem { Label("Viaggio", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill") }
            InfoView()
                .tabItem { Label("Info & SOS", systemImage: "cross.case.fill") }
        }
        .task {
            model.location.request()
            await model.refreshGlobal(force: true)
        }
        .task(id: model.placeKey) {
            await model.refreshPlace()
        }
    }
}
