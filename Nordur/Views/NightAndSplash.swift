import SwiftUI

// MARK: - Night vision

/// Red on black, for watching the aurora: white and blue light undo the eyes'
/// adaptation to the dark (20–30 minutes to come back), deep red does not.
enum NightVision {
    static let key = "nightVision"
    /// Turns itself on in the Aurora tab when the sun is down at the place shown.
    static let autoKey = "nightVision.auto"

    static func auto(at c: Coordinate) -> Bool {
        UserDefaults.standard.bool(forKey: autoKey) && Astro.sunAltitude(Date(), at: c) < -6
    }
}

extension View {
    /// The whole screen in shades of red (maps and photos too).
    @ViewBuilder func nightVision(_ on: Bool) -> some View {
        if on {
            self.grayscale(1)
                .colorMultiply(Color(red: 1, green: 0.12, blue: 0.08))
                .brightness(-0.04)
                .preferredColorScheme(.dark)
        } else {
            self
        }
    }
}

/// The moon button that switches it (Aurora tab, Map).
struct NightVisionButton: View {
    @AppStorage(NightVision.key) private var night = false

    var body: some View {
        Button {
            Haptics.tap()
            withAnimation(.easeInOut(duration: 0.3)) { night.toggle() }
        } label: {
            Label(night ? String(localized: "NOTTE ON") : String(localized: "NOTTE"), systemImage: night ? "moon.fill" : "moon")
                .font(.mono(11, .semibold))
                .foregroundStyle(night ? Color.black : Theme.text)
                .padding(.horizontal, 10).frame(height: 34)
                .background(night ? Color.red : Theme.bg.opacity(0.94))
                .overlay(Rectangle().strokeBorder(night ? Color.red : Theme.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Visione notturna rossa"))
        .accessibilityIdentifier("nightVision")
    }
}

// MARK: - Launch

/// The opening: night sky, a moving aurora, the mountains and the Ð of Norður.
struct LaunchAnimation: View {
    let done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var bar = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(red: 0.02, green: 0.03, blue: 0.07), Color(red: 0.05, green: 0.08, blue: 0.16)],
                               startPoint: .top, endPoint: .bottom)
                Stars().opacity(shown ? 1 : 0)
                AuroraCurtain(moving: !reduceMotion, strength: 1)
                    .frame(height: geo.size.height * 0.55)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .opacity(shown ? 0.95 : 0)
                    .offset(y: shown ? 0 : -40)
                Mountains()
                    .fill(Color(red: 0.01, green: 0.02, blue: 0.04))
                    .frame(height: geo.size.height * 0.3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                VStack(spacing: 18) {
                    ZStack(alignment: .leading) {
                        Text("D")
                            .font(.custom(AppFontName.condensed(.bold), size: 150))
                            .foregroundStyle(Color(white: 0.97))
                        Rectangle().fill(Theme.accent)
                            .frame(width: bar ? 64 : 0, height: 16)
                            .offset(x: -22, y: 6)
                    }
                    .scaleEffect(shown ? 1 : 0.86)
                    Text("NORÐUR")
                        .font(.custom(AppFontName.condensed(.bold), size: 34))
                        .tracking(10)
                        .foregroundStyle(Color(white: 0.95))
                    Text("Islanda: aurora, meteo, strade")
                        .font(.app(.subheadline)).foregroundStyle(Color(white: 0.7))
                }
                .opacity(shown ? 1 : 0)
                .offset(y: -geo.size.height * 0.02)
            }
        }
        .ignoresSafeArea()
        .task {
            withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.7)) { shown = true }
            try? await Task.sleep(nanoseconds: 350_000_000)
            withAnimation(.spring(duration: 0.45, bounce: 0.3)) { bar = true }
            try? await Task.sleep(nanoseconds: reduceMotion ? 700_000_000 : 1_450_000_000)
            done()
        }
        .accessibilityHidden(true)
    }

    private struct Stars: View {
        var body: some View {
            Canvas { ctx, size in
                var rng = SeededRandom(seed: 7)
                for _ in 0..<120 {
                    let p = CGPoint(x: rng.next() * size.width, y: rng.next() * size.height * 0.7)
                    let r = 0.6 + rng.next() * 1.4
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: r, height: r)), with: .color(.white.opacity(0.35 + rng.next() * 0.6)))
                }
            }
        }
    }

    private struct Mountains: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            let peaks: [(CGFloat, CGFloat)] = [(0, 0.45), (0.12, 0.3), (0.22, 0.38), (0.33, 0.12), (0.45, 0.32), (0.56, 0.22), (0.68, 0.4), (0.8, 0.18), (0.9, 0.34), (1, 0.28)]
            p.move(to: CGPoint(x: 0, y: rect.maxY))
            for (x, y) in peaks { p.addLine(to: CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)) }
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.closeSubpath()
            return p
        }
    }
}

/// A tiny deterministic random generator (the same stars every launch).
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(Double(state >> 11) / Double(1 << 53))
    }
}

/// The aurora behind the app: when the aurora is possible where you are, soft
/// curtains move at the top of every screen, brighter the better the chances,
/// gone when there is none. Light enough not to cover what is written (it adds
/// light on the dark theme, it does not paint over it), still with Reduce
/// Motion and Low Power Mode, off from Settings › Schermo.
struct AmbientAurora: View {
    static let key = "ambientAurora"
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @AppStorage(AmbientAurora.key) private var enabled = true

    /// 0 with no chance, 1 with excellent conditions (observability index here, now).
    static func intensity(_ slot: AuroraSlot?) -> Double {
        guard let index = slot?.index else { return 0 }
        return min(1, max(0, (index - 0.08) / 0.47))
    }

    var body: some View {
        let strength = enabled ? Self.intensity(model.auroraNow) : 0
        GeometryReader { geo in
            if strength > 0 {
                AuroraCurtain(moving: !reduceMotion && phase == .active && !ProcessInfo.processInfo.isLowPowerModeEnabled,
                              strength: 0.4 + 0.6 * strength)
                    .frame(height: geo.size.height * (0.28 + 0.17 * strength))
                    .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
                    .opacity(scheme == .dark ? 0.16 + 0.34 * strength : 0.08 + 0.14 * strength)
                    .blendMode(scheme == .dark ? .screen : .multiply)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 2), value: strength)
    }
}
