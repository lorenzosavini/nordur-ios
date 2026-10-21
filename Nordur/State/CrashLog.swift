import Foundation
import UIKit
import MetricKit
import Darwin

/// Why the app closed by itself, kept on the phone and shown in Settings ›
/// Registro errori, ready to send.
///
/// Three sources:
/// - crashes caught as they happen (signals such as a Swift error, and
///   Objective-C exceptions), written with the stack to a file and read at the
///   next launch;
/// - closings with no crash while the app was on screen (iOS ends the app for
///   too much memory or a screen frozen too long): found at the next launch,
///   with the screen open and the memory used just before;
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
    private static let memoryKey = "crash.memoryMB", beatKey = "crash.beat"

    static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?")) · iOS \(UIDevice.current.systemVersion)"
    }

    @ObservationIgnored private var heartbeat: Timer?

    /// First thing at launch: reads what the last run left, then arms the handlers.
    func install() {
        load()
        collectPending()
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.runningKey), defaults.string(forKey: Self.phaseKey) == "active" {
            // Closed while on screen, and no crash caught: iOS ended it.
            let memory = defaults.double(forKey: Self.memoryKey)
            let beat = defaults.object(forKey: Self.beatKey) as? Date ?? Date()
            add(Entry(date: beat, kind: String(localized: "Chiusura inattesa"),
                      summary: String(localized: "L'app si è chiusa mentre era aperta, senza un errore del codice."),
                      details: String(localized: "Di solito è iOS che la chiude: memoria esaurita (usati circa \(Int(memory)) MB poco prima) oppure schermo bloccato troppo a lungo. Se succede sempre nella stessa schermata, è un indizio.")
                        + "\n\n" + String(localized: "Ultimo segnale di vita: \(Fmt.dayTime(beat))"),
                      screen: defaults.string(forKey: Self.screenKey), version: Self.version))
        }
        defaults.set(true, forKey: Self.runningKey)
        defaults.set("active", forKey: Self.phaseKey)
        armHandlers()
        MXMetricManager.shared.add(self)
        heartbeat = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            Task { @MainActor in CrashLog.beat() }
        }
        Self.beat()
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
        beat()
    }

    private static func beat() {
        UserDefaults.standard.set(memoryMB(), forKey: memoryKey)
        UserDefaults.standard.set(Date(), forKey: beatKey)
    }

    static func memoryMB() -> Double {
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
}
