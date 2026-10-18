import SwiftUI

/// "Aurora now, here" on Today: how the aurora can be seen at the active place
/// in this hour, the combined Kp, and the fast signals kept apart (Bz, Hp30,
/// ground magnetometer, community reports). An aurora curtain moves behind it
/// when the aurora can be seen now, and stays still and faint when there is
/// activity that darkness or clouds hide.
struct AuroraNowPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let slot = model.auroraNow
        let state = model.aurora?.value
        let confirmation = model.auroraConfirmation
        let cls = slot?.observability ?? .veryPoor
        // CI demo video only: `-ciAuroraDemo YES` shows the panel as with the aurora visible.
        let demo = UserDefaults.standard.bool(forKey: "ciAuroraDemo")
        let visible = demo || cls >= .moderate || confirmation.status >= .likely
        let active = (slot?.activityFactor ?? 0) >= 0.3 || (state?.magnetometer?.level ?? 0) >= 2
        let kp = state?.currentBlock?.value

        NavigationLink { AuroraView() } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("AURORA ADESSO · QUI").font(.mono(10, .semibold)).tracking(0.8).foregroundStyle(Theme.aurora)
                    Spacer()
                    if visible {
                        Text("VISIBILE ORA").font(.mono(10, .semibold)).foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 7).padding(.vertical, 3).background(Theme.aurora)
                    }
                }
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let slot {
                            Text(cls.label.uppercased()).font(.display(28, .bold))
                                .foregroundStyle(cls >= .good ? Theme.aurora : cls == .moderate ? Theme.caution : Theme.text)
                                .lineLimit(2).minimumScaleFactor(0.7)
                            Text(slot.reasons.first ?? slot.darkness.label).font(.app(.caption)).foregroundStyle(Theme.dim)
                                .lineLimit(2)
                        } else {
                            SkeletonBlock(lines: 2, height: 10, showsFigure: false)
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("KP").font(.mono(9.5)).foregroundStyle(Theme.faint)
                        Text(Fmt.number(kp, decimals: 1)).font(.metric(44, .bold))
                            .foregroundStyle((kp ?? 0) >= 5 ? Theme.aurora : Theme.text)
                    }
                }
                // Fast signals, each on its own.
                HStack(spacing: 0) {
                    signal("BZ", state?.solarWind.map { Fmt.number($0.latest.bz, decimals: 1, unit: "nT") } ?? "–",
                           highlight: (state?.solarWind?.latest.bz ?? 0) <= -5)
                    signal("HP30", Fmt.number(state?.hp30?.last?.hp30, decimals: 1), highlight: (state?.hp30?.last?.hp30 ?? 0) >= 5)
                    signal(String(localized: "CAMPO"), state?.magnetometer.map { "\(Int($0.rangeNt)) nT" } ?? "–",
                           highlight: (state?.magnetometer?.level ?? 0) >= 2)
                }
                .overlay(alignment: .top) { Rule() }
                if confirmation.status != .noReports {
                    Text(confirmation.headline).font(.app(.caption, .medium)).foregroundStyle(confirmation.status >= .likely ? Theme.aurora : Theme.dim)
                }
                Text("PREVISIONE ORA PER ORA, VENTO SOLARE, MAPPA →").font(.mono(9.5, .semibold)).foregroundStyle(Theme.accent)
            }
            .padding(14)
            .background {
                if visible || active {
                    AuroraCurtain(moving: visible && !reduceMotion, strength: visible ? 1 : 0.35)
                        .opacity(visible ? 0.55 : 0.25)
                        .allowsHitTesting(false)
                }
            }
            .clipped()
            .overlay(Rectangle().strokeBorder(visible ? Theme.aurora : Theme.hairline, lineWidth: visible ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.aurora")
    }

    private func signal(_ label: String, _ value: String, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.mono(9)).foregroundStyle(Theme.faint)
            Text(value).font(.metric(19, .semibold)).foregroundStyle(highlight ? Theme.aurora : Theme.text)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

/// Vertical rays of green light with a violet fringe, swaying slowly.
struct AuroraCurtain: View {
    var moving: Bool
    var strength: Double = 1

    var body: some View {
        if moving {
            TimelineView(.animation(minimumInterval: 1 / 24)) { context in
                canvas(t: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            canvas(t: 0)
        }
    }

    private func canvas(t: Double) -> some View {
        Canvas { ctx, size in
            let rays = 46
            let step = size.width / CGFloat(rays)
            for i in 0..<rays {
                let x = CGFloat(i) * step + step / 2
                let wave = 0.5 * sin(t * 0.9 + Double(i) * 0.38) + 0.5 * sin(t * 0.4 - Double(i) * 0.17)
                let top = size.height * (0.04 + 0.08 * CGFloat(wave))
                let length = size.height * CGFloat(0.55 + 0.3 * strength) * CGFloat(0.75 + 0.25 * sin(t * 1.3 + Double(i)))
                let rect = CGRect(x: x - step * 0.45, y: top, width: step * 0.9, height: length)
                let gradient = Gradient(stops: [
                    .init(color: Color(red: 0.63, green: 0.42, blue: 1).opacity(0.0), location: 0),
                    .init(color: Color(red: 0.63, green: 0.42, blue: 1).opacity(0.7 * strength), location: 0.12),
                    .init(color: Color(red: 0.2, green: 0.91, blue: 0.62).opacity(0.95), location: 0.35),
                    .init(color: Color(red: 0.11, green: 0.5, blue: 0.33).opacity(0.0), location: 1),
                ])
                ctx.fill(Path(rect), with: .linearGradient(gradient, startPoint: CGPoint(x: x, y: rect.minY), endPoint: CGPoint(x: x, y: rect.maxY)))
            }
        }
        .blur(radius: 6)
    }
}
