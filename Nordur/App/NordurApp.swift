import SwiftUI
import UserNotifications

@main
struct NordurApp: App {
    @State private var model = AppModel()
    @State private var trip = TripStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Appearance.key) private var appearance = Appearance.system.rawValue

    init() {
        Appearance.configureUIKit()
        // Touch the singletons early: when iOS relaunches the app in the background
        // for a location event, their delegates must be installed immediately.
        _ = AlertCenter.shared
        _ = DriveRecorder.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
                .tint(Theme.accent)
                .font(.sans(16))
                .environment(model)
                .environment(trip)
                .environment(AlertCenter.shared)
                .environment(DriveRecorder.shared)
                .environment(DriveStore.shared)
                .environment(Account.shared)
                .onReceive(NotificationCenter.default.publisher(for: .accountRestored)) { _ in
                    trip.reload()
                    DriveStore.shared.reload()
                    AlertCenter.shared.reloadAfterRestore()
                    model.reloadSelection()
                }
                .onAppear { AlertCenter.shared.model = model }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                AlertCenter.scheduleBackgroundRefresh()
                Task { await Account.shared.sync() }
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

private extension View {
    func tabBarSpace(_ height: CGFloat) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: height) }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AlertCenter.self) private var alerts
    @Environment(DriveRecorder.self) private var recorder
    // `-initialTab drive` as launch argument opens a given tab (used by the CI screenshots).
    @State private var tab = Tab(rawValue: UserDefaults.standard.string(forKey: "initialTab") ?? "") ?? .today

    enum Tab: String, Hashable { case today, weather, map, drive, trip }
    @AppStorage(WindUnit.key) private var windUnit = WindUnit.ms.rawValue
    @State private var showAuroraLive = UserDefaults.standard.string(forKey: "initialTab") == "aurora"
    @State private var showAccount = UserDefaults.standard.string(forKey: "initialTab") == "account"
    @State private var showAuroraIntel = UserDefaults.standard.string(forKey: "initialTab") == "kp"
    // CI only: `-ciScreen quakes` opens a secondary screen over the tabs for the screenshots.
    @State private var ciScreen = UserDefaults.standard.string(forKey: "ciScreen").flatMap(CIScreen.init(rawValue:))

    enum CIScreen: String, Identifiable {
        case alerts, alertSettings, info, quakes, roads, transport, webcams, warnings, offline
        var id: String { rawValue }
    }

    var body: some View {
        @Bindable var alerts = alerts
        @Bindable var model = model
        TabView(selection: $tab) {
            // Each page reserves the custom tab bar's height at the bottom: TabView
            // pages do not receive the root's safe-area inset, so the last lines of
            // every screen (and the map's panel) ended up under the bar.
            TodayView().tag(Tab.today).toolbar(.hidden, for: .tabBar).tabBarSpace(model.tabBarHeight)
            WeatherView().tag(Tab.weather).toolbar(.hidden, for: .tabBar).tabBarSpace(model.tabBarHeight)
            MapScreen().tag(Tab.map).toolbar(.hidden, for: .tabBar).tabBarSpace(model.tabBarHeight)
            DriveView().tag(Tab.drive).toolbar(.hidden, for: .tabBar).tabBarSpace(model.tabBarHeight)
            TripView().tag(Tab.trip).toolbar(.hidden, for: .tabBar).tabBarSpace(model.tabBarHeight)
        }
        .id(windUnit)  // every screen redraws with the new wind unit
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NordurTabBar(selection: $tab, badge: alerts.unreadCount, recording: recorder.isRecording)
                .background(GeometryReader { g in
                    Color.clear.onAppear { model.tabBarHeight = g.size.height }
                        .onChange(of: g.size.height) { model.tabBarHeight = g.size.height }
                })
        }
        .onChange(of: model.requestedTab) {
            if let raw = model.requestedTab, let target = Tab(rawValue: raw) { tab = target }
            model.requestedTab = nil
        }
        .sheet(isPresented: $alerts.openInbox, onDismiss: { alerts.markAllRead() }) {
            NavigationStack { AlertsView() }
        }
        .sheet(isPresented: $showAccount) { AccountView() }
        .sheet(isPresented: $model.showSettings) { SettingsView() }
        .sheet(isPresented: $showAuroraIntel) { NavigationStack { AuroraView() } }
        .sheet(isPresented: $showAuroraLive) {
            NavigationStack { AuroraLiveView() }
        }
        .sheet(item: $ciScreen) { screen in
            NavigationStack {
                switch screen {
                case .alerts: AlertsView()
                case .alertSettings: AlertSettingsView()
                case .info: InfoView()
                case .quakes: QuakesView()
                case .roads: RoadsView()
                case .transport: TransportView()
                case .webcams: WebcamsView()
                case .warnings: WarningsView()
                case .offline: OfflineView()
                }
            }
        }
        .task {
            // CI only: `-ciAutoDrive YES` starts a recording to exercise the live road watch.
            if UserDefaults.standard.bool(forKey: "ciAutoDrive"), !recorder.isRecording {
                recorder.start(name: "Test CI")
            }
        }
        .task {
            model.location.request()
            await alerts.refreshPermissionState()
            await Account.shared.restoreAfterReinstall()
            // CI launches pass -initialTab: no permission sheet over the screenshots there.
            if UserDefaults.standard.string(forKey: "initialTab") == nil, UserDefaults.standard.string(forKey: "ciScreen") == nil,
               await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined {
                await alerts.requestNotificationPermission()
            }
            await model.refreshGlobal(force: true)
            // CI only: include yellow warnings so the inbox screenshot exercises the whole pipeline on live data.
            if UserDefaults.standard.bool(forKey: "ciAlertsYellow"), !alerts.settings.includeYellow {
                var settings = alerts.settings
                settings.includeYellow = true
                alerts.update(settings)
            }
            await alerts.check()
        }
        .task(id: model.placeKey) {
            await model.placeChanged()
            await alerts.check()
        }
        .task {
            // Foreground polling: every 5 minutes while the app is open.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                await alerts.check()
                await Account.shared.sync()
            }
        }
    }
}
