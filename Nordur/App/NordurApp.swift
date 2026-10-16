import SwiftUI

@main
struct NordurApp: App {
    @State private var model = AppModel()
    @State private var trip = TripStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Touch the singletons early: when iOS relaunches the app in the background
        // for a location event, their delegates must be installed immediately.
        _ = AlertCenter.shared
        _ = DriveRecorder.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(trip)
                .environment(AlertCenter.shared)
                .environment(DriveRecorder.shared)
                .environment(DriveStore.shared)
                .onAppear { AlertCenter.shared.model = model }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                AlertCenter.scheduleBackgroundRefresh()
            case .active:
                Task {
                    await model.refreshGlobal()
                    await AlertCenter.shared.check()
                }
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(AlertCenter.refreshTaskID)) {
            await AlertCenter.shared.check()
            await AlertCenter.scheduleBackgroundRefresh()
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AlertCenter.self) private var alerts
    @Environment(DriveRecorder.self) private var recorder
    // `-initialTab drive` as launch argument opens a given tab (used by the CI screenshots).
    @State private var tab = Tab(rawValue: UserDefaults.standard.string(forKey: "initialTab") ?? "") ?? .today

    enum Tab: String, Hashable { case today, weather, map, drive, trip }
    @State private var showAuroraLive = UserDefaults.standard.string(forKey: "initialTab") == "aurora"

    var body: some View {
        @Bindable var alerts = alerts
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Oggi", systemImage: "sun.horizon.fill") }
                .tag(Tab.today)
                .badge(alerts.unreadCount)
            WeatherView()
                .tabItem { Label("Meteo", systemImage: "cloud.sun.rain.fill") }
                .tag(Tab.weather)
            MapScreen()
                .tabItem { Label("Mappa", systemImage: "map.fill") }
                .tag(Tab.map)
            DriveView()
                .tabItem { Label("Guida", systemImage: recorder.isRecording ? "record.circle" : "car.fill") }
                .tag(Tab.drive)
            TripView()
                .tabItem { Label("Viaggio", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill") }
                .tag(Tab.trip)
        }
        .sheet(isPresented: $alerts.openInbox) {
            NavigationStack { AlertsView() }
        }
        .sheet(isPresented: $showAuroraLive) {
            NavigationStack { AuroraLiveView() }
        }
        .task {
            model.location.request()
            await alerts.refreshPermissionState()
            await model.refreshGlobal(force: true)
            await alerts.check()
        }
        .task(id: model.placeKey) {
            await model.refreshPlace()
        }
        .task {
            // Foreground polling: every 5 minutes while the app is open.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                await alerts.check()
            }
        }
    }
}
