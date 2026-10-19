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
                // Back in the app: what changed meanwhile is fetched at once.
                Task {
                    async let global: Void = model.refreshGlobal()
                    async let place: Void = model.refreshPlaceIfOld()
                    _ = await (global, place)
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
    /// Background strip behind the status bar: scrolled content no longer runs
    /// under the clock (these screens hide the navigation bar).
    func statusBarScrim() -> some View {
        overlay(alignment: .top) {
            Theme.bg.opacity(0.96).frame(height: 0).ignoresSafeArea(edges: .top)
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
    @AppStorage(WindUnit.key) private var windUnit = WindUnit.ms.rawValue
    @State private var showAuroraLive = UserDefaults.standard.string(forKey: "initialTab") == "aurora"
    @State private var showAccount = UserDefaults.standard.string(forKey: "initialTab") == "account"
    @State private var showAuroraIntel = UserDefaults.standard.string(forKey: "initialTab") == "kp"
    // CI only: `-ciScreen quakes` opens a secondary screen over the tabs for the screenshots.
    @State private var ciScreen = UserDefaults.standard.string(forKey: "ciScreen").flatMap(CIScreen.init(rawValue:))
    /// A GPX file opened with Norður (Files, Mail, the share menu of Garmin Connect, Strava…).
    @State private var openedTrack: DriveSession?
    @State private var importError: String?

    enum CIScreen: String, Identifiable {
        case alerts, alertSettings, info, quakes, roads, transport, webcams, warnings, offline, stop, settings
        var id: String { rawValue }
    }

    var body: some View {
        @Bindable var alerts = alerts
        @Bindable var model = model
        // The tab bar takes its own place under the pages (not an inset over them):
        // nothing on any screen can end up underneath it.
        VStack(spacing: 0) {
            TabView(selection: $tab) {
                TodayView().tag(Tab.today).toolbar(.hidden, for: .tabBar).statusBarScrim()
                WeatherView().tag(Tab.weather).toolbar(.hidden, for: .tabBar).statusBarScrim()
                MapScreen().tag(Tab.map).toolbar(.hidden, for: .tabBar)
                DriveView().tag(Tab.drive).toolbar(.hidden, for: .tabBar).statusBarScrim()
                TripView().tag(Tab.trip).toolbar(.hidden, for: .tabBar).statusBarScrim()
            }
            .id(windUnit)  // every screen redraws with the new wind unit
            NordurTabBar(selection: $tab, badge: alerts.unreadCount, recording: recorder.isRecording)
        }
        .overlay(alignment: .top) { OfflineBanner() }
        .animation(.snappy, value: Connectivity.shared.isOnline)
        .onChange(of: Connectivity.shared.reconnections) {
            // Back online: everything is reloaded at once, without waiting for the next poll.
            Task {
                async let global: Void = model.refreshGlobal(force: true)
                async let place: Void = model.refreshPlace()
                _ = await (global, place)
                await alerts.check()
            }
        }
        .sensoryFeedback(.selection, trigger: tab)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onOpenURL { url in
            guard url.isFileURL, ["gpx", "kml"].contains(url.pathExtension.lowercased()) else { return }
            // Waypoints or placemarks: a trip planned elsewhere; a recorded track: a drive.
            if TripImportFile.isTrip(url) {
                do {
                    model.pendingTripImport = try TripImportFile.read(url)
                    tab = .trip
                } catch {
                    importError = error.localizedDescription
                }
                return
            }
            do {
                openedTrack = try DriveStore.shared.importGPX(url)
                tab = .drive
                Haptics.result(true)
            } catch {
                importError = error.localizedDescription
                Haptics.result(false)
            }
        }
        .sheet(item: $openedTrack) { track in NavigationStack { DriveDetailView(drive: track) } }
        .alert("Importazione non riuscita", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(importError ?? "") }
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
                case .stop: StopEditor(stop: nil)
                case .settings: SettingsView()
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
            await model.warmStart()
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
            // Foreground polling while the app is open: country-wide feeds (warnings,
            // quakes, roads, aurora) every 2 minutes, the place forecast every 15.
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2 * 60 * 1_000_000_000)
                guard UIApplication.shared.applicationState == .active else { continue }
                tick += 1
                await model.refreshGlobal()
                await model.refreshPlaceIfOld()
                await alerts.check()
                if tick % 3 == 0 { await Account.shared.sync() }
            }
        }
    }
}
