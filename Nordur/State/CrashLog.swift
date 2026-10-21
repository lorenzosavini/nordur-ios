import Foundation
import UIKit
import MetricKit
import Darwin
import os

/// Why the app closed by itself, kept on the phone and shown in Settings ›
/// Registro errori, ready to send.
///
/// Three sources:
/// - crashes caught as they happen (signals such as a Swift error, and
///   Objective-C exceptions), written with the stack to a file and read at the
///   next launch;
/// - closings with no crash while the app was on screen (iOS ends the app for
///   too much memory or a screen frozen too long): found at the next launch,
///   with the screen open, the memory used and left just before, the memory
///   warnings and the freezes seen by the watchdog thread. Not counted: the
///   app replaced by a new build, the phone restarted, the app launched by iOS
///   in the background (it never came on screen);
/// - iOS's own diagnostic reports (MetricKit): crashes, hangs, with details the
///   app cannot see by itself. They arrive at a later launch.
@MainActor
@Observable
final class CrashLog: NSObject {
    static let shared = CrashLog()

    struct Entry: Codable, Identifiable, Hashable {
        var id = UUID()
        var date: Date
        var kind: String
        var summary: String
        var details: String
        var screen: String?
        var version: String
    }

    private(set) var entries: [Entry] = []

    private static let directory: URL = {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("crashes", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    private static var storeURL: URL { directory.appendingPathComponent("log.json") }
    fileprivate static var pendingURL: URL { directory.appendingPathComponent("pending.txt") }

    private static let runningKey = "crash.running", phaseKey = "crash.phase", screenKey = "crash.screen"
    private static let memoryKey = "crash.memoryMB", beatKey = "crash.beat", versionKey = "crash.version"
    private static let availableKey = "crash.availableMB", warningKey = "crash.memoryWarning"
    nonisolated fileprivate static let hangSinceKey = "crash.hangSince", hangSecondsKey = "crash.hangSeconds"

    static var version: String {
        let info = Bundle.main.infoDictionary
        let commit = (info?["NordurCommit"] as? String).map { " · \($0)" } ?? ""
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (build \(info?["CFBundleVersion"] as? String ?? "?")\(commit)) · iOS \(UIDevice.current.systemVersion)"
    }

    @ObservationIgnored private var heartbeat: Timer?

    /// First thing at launch: reads what the last run left, then arms the handlers.
    func install() {
        load()
        collectPending()
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.runningKey), defaults.string(forKey: Self.phaseKey) == "active",
           let entry = Self.unexpectedClosing(defaults) {
            add(entry)
        }
        defaults.set(true, forKey: Self.runningKey)
        // "active" only once the screen is on: iOS also launches the app in the
        // background (location, refresh), and ending it there is normal.
        defaults.set("launch", forKey: Self.phaseKey)
        defaults.set(Self.version, forKey: Self.versionKey)
        defaults.removeObject(forKey: Self.hangSinceKey)
        defaults.removeObject(forKey: Self.hangSecondsKey)
        armHandlers()
        MXMetricManager.shared.add(self)
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in CrashLog.memoryWarning() }
        }
        heartbeat = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { @MainActor in CrashLog.beat() }
        }
        Self.beat()
        HangWatch.start()
    }

    /// What the last run left when it ended on screen with no crash caught, told
    /// as plainly as the clues allow; nil when the closing was not the app's
    /// (a new build installed over it, the phone restarted).
    private static func unexpectedClosing(_ defaults: UserDefaults) -> Entry? {
        let beat = defaults.object(forKey: beatKey) as? Date ?? Date()
        let closedVersion = defaults.string(forKey: versionKey)
        // Installing a new build ends the one open: not a closing to report.
        guard closedVersion == version else { return nil }
        // Restarted or switched off since: iOS ended everything.
        if let boot = bootTime(), boot > beat.addingTimeInterval(-5) { return nil }
        let memory = Int(defaults.double(forKey: memoryKey))
        let available = defaults.object(forKey: availableKey) as? Double
        let warning = defaults.object(forKey: warningKey) as? Date
        let hang = defaults.object(forKey: hangSinceKey) as? Date
        let hangSeconds = defaults.double(forKey: hangSecondsKey)
        let memoryLine = String(localized: "Memoria usata: \(memory) MB") + (available.map { String(localized: " · ancora disponibile: \(Int($0)) MB") } ?? "")
        let summary: String, cause: String
        if hang != nil {
            summary = String(localized: "Schermo bloccato: iOS l'ha chiusa.")
            cause = String(localized: "L'app non rispondeva da \(Int(hangSeconds.rounded())) s quando si è chiusa: iOS chiude un'app ferma troppo a lungo (watchdog). Il punto del codice arriva con il «Blocco (rapporto iOS)», di solito il giorno dopo.")
        } else if let warning, beat.timeIntervalSince(warning) < 120 {
            summary = String(localized: "Memoria esaurita: iOS l'ha chiusa.")
            cause = String(localized: "iOS aveva avvisato di memoria quasi finita alle \(Fmt.time(warning)), poco prima della chiusura.")
        } else if let available, available < 150 {
            summary = String(localized: "Memoria esaurita: iOS l'ha chiusa.")
            cause = String(localized: "Restavano solo \(Int(available)) MB prima del limite che iOS concede all'app.")
        } else {
            summary = String(localized: "Chiusa mentre era aperta, senza crash, blocchi o avvisi di memoria.")
            cause = String(localized: "L'app non ha visto la causa: niente errori nel codice, schermo che rispondeva, memoria nella norma. Di solito è iOS che chiude l'app (per esempio per liberare memoria per un'altra app o la fotocamera), oppure l'app è stata chiusa dal multitasking mentre era aperta. Se è un crash, il «rapporto iOS» arriva a un avvio successivo.")
        }
        return Entry(date: beat, kind: String(localized: "Chiusura inattesa"), summary: summary,
                     details: [cause, memoryLine, String(localized: "Ultimo segnale di vita: \(Fmt.dayTime(beat))")].joined(separator: "\n\n"),
                     screen: defaults.string(forKey: screenKey), version: closedVersion ?? version)
    }

    private static func bootTime() -> Date? {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec))
    }

    private static func memoryWarning() {
        UserDefaults.standard.set(Date(), forKey: warningKey)
        beat()
        ErrorLog.record("Memoria", String(localized: "iOS ha avvisato: memoria quasi finita"),
                        detail: String(localized: "In uso \(Int(memoryMB())) MB, ancora disponibili \(Int(availableMB())) MB") + " · "
                            + String(localized: "Schermata: \(UserDefaults.standard.string(forKey: screenKey) ?? "?")"))
    }

    /// The screen on view, written with each crash.
    static func note(screen: String) {
        UserDefaults.standard.set(screen, forKey: screenKey)
        crashScreen = strdup(screen)
    }

    /// Background and foreground: a closing in the background is normal (iOS frees memory).
    static func phase(_ phase: String) {
        UserDefaults.standard.set(phase, forKey: phaseKey)
        if phase == "active" { UserDefaults.standard.set(true, forKey: runningKey) }
        HangWatch.onScreen(phase == "active")
        beat()
    }

    private static func beat() {
        UserDefaults.standard.set(memoryMB(), forKey: memoryKey)
        UserDefaults.standard.set(availableMB(), forKey: availableKey)
        UserDefaults.standard.set(Date(), forKey: beatKey)
    }

    /// How much more memory iOS lets the app use before ending it.
    nonisolated static func availableMB() -> Double { Double(os_proc_available_memory()) / 1_048_576 }

    nonisolated static func memoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    func delete(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    /// The whole log as text, to send.
    var text: String {
        entries.map { e in
            ["\(Fmt.dayTime(e.date)) · \(e.kind)", e.summary, e.screen.map { String(localized: "Schermata: \($0)") }, e.version, e.details]
                .compactMap { $0 }.joined(separator: "\n")
        }.joined(separator: "\n\n————\n\n")
    }

    // MARK: Storage

    private func add(_ entry: Entry) {
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(50))
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storeURL), let stored = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = stored
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: Self.storeURL, options: .atomic) }
    }

    /// A crash written by the handlers during the last run.
    private func collectPending() {
        guard let raw = try? String(contentsOf: Self.pendingURL, encoding: .utf8), !raw.isEmpty else { return }
        let date = (try? FileManager.default.attributesOfItem(atPath: Self.pendingURL.path)[.modificationDate]) as? Date
        try? FileManager.default.removeItem(at: Self.pendingURL)
        let lines = raw.components(separatedBy: "\n")
        let first = lines.first ?? ""
        let screen = lines.first { $0.hasPrefix("SCREEN ") }.map { String($0.dropFirst(7)) }
        let summary: String
        if first.hasPrefix("EXCEPTION") {
            summary = String(localized: "Eccezione: \(first.dropFirst(10))")
        } else {
            summary = Self.signalSummary(first)
        }
        add(Entry(date: date ?? (UserDefaults.standard.object(forKey: Self.beatKey) as? Date ?? Date()),
                  kind: String(localized: "Crash"), summary: summary,
                  details: lines.dropFirst().filter { !$0.hasPrefix("SCREEN ") }.joined(separator: "\n"),
                  screen: screen ?? UserDefaults.standard.string(forKey: Self.screenKey), version: Self.version))
        // A crash was caught: the "closed while on screen" check must not count it twice.
        UserDefaults.standard.set(false, forKey: Self.runningKey)
    }

    private static func signalSummary(_ line: String) -> String {
        let number = Int32(line.split(separator: " ").last ?? "") ?? 0
        switch number {
        case SIGTRAP: return String(localized: "Errore nel codice Swift (SIGTRAP): un valore mancante o un indice fuori dai limiti.")
        case SIGABRT: return String(localized: "Arresto forzato (SIGABRT): il sistema o una libreria ha fermato l'app.")
        case SIGSEGV, SIGBUS: return String(localized: "Accesso a memoria non valida (\(number == SIGSEGV ? "SIGSEGV" : "SIGBUS")).")
        case SIGILL: return String(localized: "Istruzione non valida (SIGILL).")
        case SIGFPE: return String(localized: "Errore aritmetico (SIGFPE).")
        default: return String(localized: "Crash (segnale \(number)).")
        }
    }

    // MARK: Handlers

    private func armHandlers() {
        crashFile = strdup(Self.pendingURL.path)
        NSSetUncaughtExceptionHandler { exception in
            let text = "EXCEPTION \(exception.name.rawValue): \(exception.reason ?? "")\n"
                + (crashScreen.map { "SCREEN \(String(cString: $0))\n" } ?? "")
                + exception.callStackSymbols.joined(separator: "\n")
            try? text.write(toFile: String(cString: crashFile!), atomically: false, encoding: .utf8)
        }
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE] {
            signal(sig, crashSignalHandler)
        }
    }
}

// Written from a signal handler: only plain C state, set up before.
nonisolated(unsafe) private var crashFile: UnsafeMutablePointer<CChar>?
nonisolated(unsafe) private var crashScreen: UnsafeMutablePointer<CChar>?

private func crashSignalHandler(_ sig: Int32) {
    if let path = crashFile {
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        if fd >= 0 {
            var header = Array("SIGNAL \(sig)\n".utf8)
            _ = write(fd, &header, header.count)
            if let screen = crashScreen {
                var prefix = Array("SCREEN ".utf8)
                _ = write(fd, &prefix, prefix.count)
                _ = write(fd, screen, strlen(screen))
                var newline: UInt8 = 10
                _ = write(fd, &newline, 1)
            }
            var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 64)
            let count = backtrace(&frames, 64)
            backtrace_symbols_fd(&frames, count, fd)
            close(fd)
        }
    }
    signal(sig, SIG_DFL)
    raise(sig)
}

extension CrashLog: MXMetricManagerSubscriber {
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        var found: [Entry] = []
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                let reason = [crash.exceptionType.map { "exception \($0)" }, crash.signal.map { "signal \($0)" },
                              crash.terminationReason, crash.virtualMemoryRegionInfo].compactMap { $0 }.joined(separator: " · ")
                found.append(Entry(date: payload.timeStampEnd, kind: String(localized: "Crash (rapporto iOS)"),
                                   summary: reason.isEmpty ? String(localized: "Crash registrato da iOS") : reason,
                                   details: String(decoding: crash.callStackTree.jsonRepresentation(), as: UTF8.self).prefix(20_000).description,
                                   screen: nil, version: crash.metaData.applicationBuildVersion + " · " + crash.metaData.osVersion))
            }
            for hang in payload.hangDiagnostics ?? [] {
                found.append(Entry(date: payload.timeStampEnd, kind: String(localized: "Blocco (rapporto iOS)"),
                                   summary: String(localized: "Schermo bloccato per \(hang.hangDuration.formatted())"),
                                   details: String(decoding: hang.callStackTree.jsonRepresentation(), as: UTF8.self).prefix(20_000).description,
                                   screen: nil, version: hang.metaData.applicationBuildVersion + " · " + hang.metaData.osVersion))
            }
        }
        guard !found.isEmpty else { return }
        Task { @MainActor in for entry in found { CrashLog.shared.add(entry) } }
    }

    /// iOS's daily count of how the app ended, with the reasons it gives: the
    /// cause of a closing the app could not see by itself.
    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        var found: [Entry] = []
        for payload in payloads {
            guard let exits = payload.applicationExitMetrics else { continue }
            let fg = exits.foregroundExitData, bg = exits.backgroundExitData
            let onScreen: [(String, Int)] = [
                (String(localized: "memoria esaurita"), fg.cumulativeMemoryResourceLimitExitCount),
                (String(localized: "schermo bloccato (watchdog)"), fg.cumulativeAppWatchdogExitCount),
                (String(localized: "accesso a memoria non valida"), fg.cumulativeBadAccessExitCount),
                (String(localized: "istruzione non valida"), fg.cumulativeIllegalInstructionExitCount),
                (String(localized: "altra chiusura anomala"), fg.cumulativeAbnormalExitCount),
            ].filter { $0.1 > 0 }
            guard !onScreen.isEmpty else { continue }
            let behind: [(String, Int)] = [
                (String(localized: "memoria liberata da iOS"), bg.cumulativeMemoryPressureExitCount),
                (String(localized: "limite di memoria"), bg.cumulativeMemoryResourceLimitExitCount),
                (String(localized: "troppo uso del processore"), bg.cumulativeCPUResourceLimitExitCount),
                (String(localized: "tempo in background scaduto"), bg.cumulativeBackgroundTaskAssertionTimeoutExitCount),
                (String(localized: "file bloccato"), bg.cumulativeSuspendedWithLockedFileExitCount),
                (String(localized: "watchdog"), bg.cumulativeAppWatchdogExitCount),
                (String(localized: "chiusura anomala"), bg.cumulativeAbnormalExitCount + bg.cumulativeBadAccessExitCount + bg.cumulativeIllegalInstructionExitCount),
            ].filter { $0.1 > 0 }
            let list = { (items: [(String, Int)]) in items.map { "\($0.0) ×\($0.1)" }.joined(separator: ", ") }
            let range = "\(Fmt.dayTime(payload.timeStampBegin)) → \(Fmt.dayTime(payload.timeStampEnd))"
            found.append(Entry(date: payload.timeStampEnd, kind: String(localized: "Chiusure del giorno (rapporto iOS)"),
                               summary: String(localized: "Con l'app aperta: \(list(onScreen))"),
                               details: [range,
                                         String(localized: "Chiusure normali con l'app aperta: \(fg.cumulativeNormalAppExitCount)"),
                                         behind.isEmpty ? nil : String(localized: "In background (di solito normali): \(list(behind))")]
                                .compactMap { $0 }.joined(separator: "\n"),
                               screen: nil, version: payload.metaData?.applicationBuildVersion ?? ""))
        }
        guard !found.isEmpty else { return }
        Task { @MainActor in for entry in found { CrashLog.shared.add(entry) } }
    }
}

/// A thread that checks the screen still answers: the main thread is asked to
/// stamp the time twice a second. Over 2 s without an answer is a freeze,
/// written down while it lasts (iOS ends an app frozen too long, and the next
/// launch then knows why) and logged as an error when it ends.
enum HangWatch {
    private struct State { var pong = Date(); var onScreen = false; var hangSince: Date? }
    private static let state = OSAllocatedUnfairLock(initialState: State())
    private static let threshold: TimeInterval = 2

    static func onScreen(_ value: Bool) {
        state.withLock { $0.onScreen = value; $0.pong = Date(); $0.hangSince = nil }
    }

    static func start() {
        let thread = Thread {
            var tick = Date()
            while true {
                Thread.sleep(forTimeInterval: 0.5)
                let now = Date()
                // The whole app was suspended (background, locked screen): not a freeze.
                let suspended = now.timeIntervalSince(tick) > 1.5
                tick = now
                DispatchQueue.main.async { state.withLock { $0.pong = Date() } }
                let (since, ended) = state.withLock { s -> (Date?, TimeInterval?) in
                    if suspended || !s.onScreen { s.pong = now; s.hangSince = nil; return (nil, nil) }
                    let silent = now.timeIntervalSince(s.pong)
                    if silent > threshold {
                        if s.hangSince == nil { s.hangSince = s.pong }
                        return (s.hangSince, nil)
                    }
                    if let start = s.hangSince {
                        s.hangSince = nil
                        return (nil, s.pong.timeIntervalSince(start))
                    }
                    return (nil, nil)
                }
                let defaults = UserDefaults.standard
                if let since {
                    defaults.set(since, forKey: CrashLog.hangSinceKey)
                    defaults.set(now.timeIntervalSince(since), forKey: CrashLog.hangSecondsKey)
                } else if let ended {
                    defaults.removeObject(forKey: CrashLog.hangSinceKey)
                    defaults.removeObject(forKey: CrashLog.hangSecondsKey)
                    let screen = defaults.string(forKey: "crash.screen") ?? "?"
                    ErrorLog.record("Blocco", String(localized: "Lo schermo non ha risposto per \(String(format: "%.1f", ended)) s"),
                                    detail: String(localized: "Schermata: \(screen)") + " · " + String(localized: "Memoria usata: \(Int(CrashLog.memoryMB())) MB"))
                }
            }
        }
        thread.name = "nordur.hangwatch"
        thread.qualityOfService = .utility
        thread.start()
    }
}
