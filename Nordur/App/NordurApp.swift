import SwiftUI
import UserNotifications

@main
struct NordurApp: App {
    @UIApplicationDelegateAdaptor(OrientationDelegate.self) private var orientationDelegate
    @State private var model = AppModel()
    @State private var trip = TripStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Appearance.key) private var appearance = Appearance.system.rawValue

    init() {
        CrashLog.shared.install()
        Appearance.configureUIKit()
        // Touch the singletons early: when iOS relaunches the app in the background
        // for a location event, their delegates must be installed immediately.
        _ = AlertCenter.shared
        _ = DriveRecorder.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modifier(OrientationRefresh())
                .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
                .tint(Theme.accent)
                .font(.sans(17))
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
                .onAppear {
                    AlertCenter.shared.model = model
                    if UIApplication.shared.applicationState == .active { CrashLog.phase("active") }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                CrashLog.phase("background")
                AlertCenter.scheduleBackgroundRefresh()
                AuroraWatch.shared.update()
                Task { await Account.shared.syncIfDue(leavingApp: true) }
            case .active:
                CrashLog.phase("active")
                // Back in the app: what changed meanwhile is fetched at once.
                Task {
                    async let global: Void = model.refreshGlobal()
                    async let place: Void = model.refreshPlaceIfOld()
                    _ = await (global, place)
                    await AlertCenter.shared.check()
                    await Entitlements.shared.refresh()
                }
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(AlertCenter.refreshTaskID)) {
            await AuroraWatch.shared.update()   // after dusk the watch starts from here
            await Entitlements.shared.loadConfig()   // a notice from the admin panel arrives as a notification
            await AlertCenter.shared.check()
            // iOS wakes the app now and then: a due backup runs too (e.g. the daily one).
            await Account.shared.syncIfDue()
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
    @Environment(TripStore.self) private var trip
    @Environment(AlertCenter.self) private var alerts
    @Environment(DriveRecorder.self) private var recorder
    // `-initialTab drive` as launch argument opens a given tab (used by the CI screenshots).
    @State private var tab = Tab(rawValue: UserDefaults.standard.string(forKey: "initialTab") ?? "") ?? .today

    /// Drives (recording, imports) live inside Trip; the aurora has its own tab.
    enum Tab: String, Hashable { case today, weather, aurora, map, trip }
    @AppStorage(WindUnit.key) private var windUnit = WindUnit.ms.rawValue
    @State private var showAuroraLive = UserDefaults.standard.string(forKey: "initialTab") == "aurora" && !UserDefaults.standard.bool(forKey: "ciAuroraMain")
    @State private var showAccount = UserDefaults.standard.string(forKey: "initialTab") == "account"
    @State private var showAuroraIntel = UserDefaults.standard.string(forKey: "initialTab") == "kp"
    // CI only: `-ciScreen quakes` opens a secondary screen over the tabs for the screenshots.
    @State private var ciScreen = UserDefaults.standard.string(forKey: "ciScreen").flatMap(CIScreen.init(rawValue:))
    /// A GPX file opened with Norður (Files, Mail, the share menu of Garmin Connect, Strava…).
    @State private var openedTrack: DriveSession?
    @AppStorage(NightVision.key) private var nightVision = false
    @AppStorage(NightVision.autoKey) private var nightAuto = false
    /// The opening animation (not in the CI runs, which open a given screen).
    @State private var launching = UserDefaults.standard.string(forKey: "initialTab") == nil
        && UserDefaults.standard.string(forKey: "ciScreen") == nil && !UserDefaults.standard.bool(forKey: "ciDemoTrip")
        || UserDefaults.standard.bool(forKey: "ciShowLaunch")
    @State private var importError: String?

    enum CIScreen: String, Identifiable {
        case alerts, alertSettings, info, quakes, roads, transport, webcams, warnings, offline, stop, settings, sights, sources
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
                AuroraTab().tag(Tab.aurora).toolbar(.hidden, for: .tabBar).statusBarScrim()
                MapScreen().tag(Tab.map).toolbar(.hidden, for: .tabBar)
                TripView().tag(Tab.trip).toolbar(.hidden, for: .tabBar).statusBarScrim()
            }
            .id(windUnit)  // every screen redraws with the new wind unit
            if !(tab == .map && model.immersiveMap) {
                NordurTabBar(selection: $tab, badge: alerts.unreadCount, recording: recorder.isRecording)
                    .transition(.move(edge: .bottom))
            }
        }
        .overlay { AmbientAurora() }
        .overlay(alignment: .top) { OfflineBanner() }
        .nightVision(nightVision || (nightAuto && tab == .aurora && NightVision.auto(at: model.activePlace.coordinate)))
        .overlay {
            if launching {
                LaunchAnimation { withAnimation(.easeOut(duration: 0.45)) { launching = false } }
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
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
        .onChange(of: tab) {
            if tab != .map { model.immersiveMap = false }
            CrashLog.note(screen: tab.rawValue)
        }
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
                tab = .trip
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
        .sheet(item: Binding(get: { Entitlements.shared.paywall }, set: { Entitlements.shared.paywall = $0 })) { feature in
            NavigationStack { PaywallView(feature: feature) }
        }
        .sheet(isPresented: $model.showSettings) { SettingsView() }
        .sheet(isPresented: $showAuroraIntel) { NavigationStack { AuroraView() } }
        .sheet(isPresented: $showAuroraLive) {
            NavigationStack { AuroraLiveView() }
        }
        .onCICommand { command in
          // Sheets opened from these (a place, the 3D card) close first on the same
          // command; a sheet closed while another is still up over it stays on screen.
          DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            // Each sheet closes through its own state: closing them from UIKit leaves
            // SwiftUI thinking they are still up, and nothing opens after that.
            @MainActor func closeAll() {
                ciScreen = nil
                openedTrack = nil
                model.showSettings = false
                model.immersiveMap = false
            }
            switch command {
            case "dismiss":
                closeAll()
            case "settings":
                closeAll()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { model.showSettings = true }
            case "night":
                nightVision.toggle()
            case "drive.demo":
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { openedTrack = DriveStore.shared.drives.first }
            case let c where c.hasPrefix("screen."):
                closeAll()
                let target = CIScreen(rawValue: String(c.dropFirst(7)))
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { ciScreen = target }
            case let c where c.hasPrefix("tab."):
                closeAll()
                if let target = Tab(rawValue: String(c.dropFirst(4))) { tab = target }
            default:
                break
            }
          }
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
                case .sights: SightsView()
                case .sources: DataSourcesView()
                }
            }
        }
        .task {
            // CI only: `-ciAutoDrive YES` starts a recording to exercise the live road watch.
            if UserDefaults.standard.bool(forKey: "ciAutoDrive"), !recorder.isRecording {
                recorder.start(name: "Test CI")
            }
        }
        .task { await Entitlements.shared.refresh() }
        .task {
            CIRemote.start()
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
            AuroraWatch.shared.update()
            await alerts.check()
        }
        .task {
            // Foreground polling while the app is open: country-wide feeds (warnings,
            // quakes, roads, aurora) every 2 minutes, the place forecast every 15.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2 * 60 * 1_000_000_000)
                guard UIApplication.shared.applicationState == .active else { continue }
                await model.refreshGlobal()
                await model.refreshPlaceIfOld()
                await Entitlements.shared.loadConfig()
                await alerts.check()
            }
        }
        .task {
            // The backup at the frequency chosen in Settings (checked every 30 s).
            var inboxTick = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                guard UIApplication.shared.applicationState == .active else { continue }
                await Account.shared.syncIfDue()
                // A trip edited together: the others' changes arrive within half a minute.
                await trip.syncShared()
                // Invitations and copies sent to this account, every 2 minutes.
                inboxTick += 1
                if inboxTick % 4 == 0 { await trip.refreshInbox() }
            }
        }
    }
}

/// Small windows (a phone, iPhone Duo folded) stay upright; large ones (iPhone
/// Duo open, iPad) turn freely. Decided by the window's own size, never by the
/// device or the main screen (Apple's guidance for iPhone Duo); asked again
/// whenever the window changes size.
final class OrientationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        guard let size = window?.bounds.size, size != .zero else { return .portrait }
        return min(size.width, size.height) >= 600 ? .all : .portrait
    }
}

/// Tells UIKit to ask the orientations again when the screen changes (iPhone Duo folded or open).
struct OrientationRefresh: ViewModifier {
    func body(content: Content) -> some View {
        content.background(GeometryReader { geo in
            Color.clear.onChange(of: geo.size) { _, _ in
                for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                    scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            }
        })
    }
}
