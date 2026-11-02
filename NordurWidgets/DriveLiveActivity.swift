import SwiftUI
import WidgetKit
import ActivityKit

/// The drive while recording: km and speed, the next stop with the km left and
/// the arrival time, the next fuel station and the most relevant wind/road alert.
/// The app sends updates sparingly (docs/BATTERIA.md); the elapsed time runs here.
struct DriveLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DriveActivityAttributes.self) { context in
            LockScreenDriveView(state: context.state, start: context.attributes.start)
                .padding()
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "nordur://drive"))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Fmt.number(state.km, decimals: 1, unit: "km")).font(.app(.title3, .bold)).monospacedDigit()
                        Text(context.attributes.start, style: .timer).font(.app(.caption)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(Int(state.speedKmh)) km/h").font(.app(.title3, .semibold)).monospacedDigit()
                        Text("media \(Int(state.averageKmh))").font(.app(.caption)).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if let stop = state.nextStopName {
                        NextStopLine(name: stop, km: state.remainingKm, eta: state.eta)
                            .font(.app(.caption, .semibold))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let alert = state.alertTitle {
                            AlertLine(title: alert, severity: state.alertSeverity).font(.app(.caption)).lineLimit(2)
                        }
                        if let fuel = state.fuelName, let km = state.fuelKm {
                            FuelLine(name: fuel, km: km).font(.app(.caption2)).foregroundStyle(.secondary).lineLimit(1)
                        } else if state.alertTitle == nil, let odometer = state.odometer {
                            Text("Contachilometri \(Fmt.number(odometer, decimals: 1, unit: "km"))").font(.app(.caption2))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: state.paused ? "pause.circle.fill" : (state.alertTitle == nil ? "car.fill" : "exclamationmark.triangle.fill"))
                    .foregroundStyle(tint(state))
            } compactTrailing: {
                // Towards a stop: the km left; otherwise the km driven.
                if let left = state.remainingKm {
                    Text("→\(Fmt.number(left, decimals: left < 10 ? 1 : 0))")
                        .monospacedDigit()
                } else {
                    Text(Fmt.number(state.km, decimals: state.km < 100 ? 1 : 0))
                        .monospacedDigit()
                }
            } minimal: {
                Image(systemName: state.alertTitle == nil ? "car.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(tint(state))
            }
            .widgetURL(URL(string: "nordur://drive"))
            .keylineTint(tint(state))
        }
    }

    private func tint(_ state: DriveActivityAttributes.ContentState) -> Color {
        state.alertTitle == nil ? .green : (Risk(rawValue: state.alertSeverity) ?? .caution).color
    }
}

struct NextStopLine: View {
    let name: String
    let km: Double?
    let eta: Date?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flag.checkered")
            Text(name).lineLimit(1)
            if let km { Text("· \(Fmt.number(km, decimals: km < 10 ? 1 : 0, unit: "km"))").monospacedDigit() }
            if let eta { Text("· \(Fmt.time(eta))").monospacedDigit() }
        }
    }
}

struct FuelLine: View {
    let name: String
    let km: Double

    var body: some View {
        Label("\(name) · \(Fmt.number(km, decimals: km < 10 ? 1 : 0, unit: "km"))", systemImage: "fuelpump.fill")
    }
}

struct AlertLine: View {
    let title: String
    let severity: Int

    var body: some View {
        Label(title, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle((Risk(rawValue: severity) ?? .caution).color)
    }
}

struct LockScreenDriveView: View {
    let state: DriveActivityAttributes.ContentState
    let start: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(state.paused ? String(localized: "In pausa") : String(localized: "Norður · in viaggio"), systemImage: state.paused ? "pause.circle.fill" : "car.fill")
                    .font(.app(.caption, .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(start, style: .timer).font(.app(.caption).monospacedDigit()).foregroundStyle(.white.opacity(0.8))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.number(state.km, decimals: 1)).font(.metric(34, .bold))
                Text("km").foregroundStyle(.white.opacity(0.7))
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(Int(state.speedKmh)) km/h").font(.app(.title3, .semibold)).monospacedDigit()
                    Text("media \(Int(state.averageKmh)) km/h").font(.app(.caption2)).foregroundStyle(.white.opacity(0.7))
                }
            }
            .foregroundStyle(.white)
            if let stop = state.nextStopName {
                NextStopLine(name: stop, km: state.remainingKm, eta: state.eta)
                    .font(.app(.caption, .semibold))
                    .foregroundStyle(.white)
            }
            if let alert = state.alertTitle {
                AlertLine(title: alert, severity: state.alertSeverity)
                    .font(.app(.caption))
                    .lineLimit(2)
            }
            if let fuel = state.fuelName, let km = state.fuelKm {
                FuelLine(name: fuel, km: km)
                    .font(.app(.caption2))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            } else if state.alertTitle == nil, state.nextStopName == nil, let odometer = state.odometer {
                Text("Contachilometri \(Fmt.number(odometer, decimals: 1, unit: "km"))").font(.app(.caption)).foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}
