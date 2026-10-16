import SwiftUI
import WidgetKit
import ActivityKit

struct DriveLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DriveActivityAttributes.self) { context in
            LockScreenDriveView(state: context.state, start: context.attributes.start)
                .padding()
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        Text(Fmt.number(context.state.km, decimals: 1, unit: "km")).font(.title3.weight(.bold)).monospacedDigit()
                        Text(Fmt.clock(context.state.elapsedSeconds)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing) {
                        Text("\(Int(context.state.speedKmh)) km/h").font(.title3.weight(.semibold)).monospacedDigit()
                        Text("media \(Int(context.state.averageKmh))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let alert = context.state.alertTitle {
                        Label(alert, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle((Risk(rawValue: context.state.alertSeverity) ?? .caution).color)
                            .lineLimit(2)
                    } else if let odometer = context.state.odometer {
                        Text("Contachilometri \(Fmt.number(odometer, decimals: 1, unit: "km"))").font(.caption)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.paused ? "pause.circle.fill" : "car.fill")
                    .foregroundStyle(context.state.alertTitle == nil ? Color.green : (Risk(rawValue: context.state.alertSeverity) ?? .caution).color)
            } compactTrailing: {
                Text(Fmt.number(context.state.km, decimals: context.state.km < 100 ? 1 : 0))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "car.fill")
            }
        }
    }
}

struct LockScreenDriveView: View {
    let state: DriveActivityAttributes.ContentState
    let start: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(state.paused ? "In pausa" : "Norður · in viaggio", systemImage: state.paused ? "pause.circle.fill" : "car.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(start, style: .timer).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.8))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.number(state.km, decimals: 1)).font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
                Text("km").foregroundStyle(.white.opacity(0.7))
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(Int(state.speedKmh)) km/h").font(.title3.weight(.semibold)).monospacedDigit()
                    Text("media \(Int(state.averageKmh)) km/h").font(.caption2).foregroundStyle(.white.opacity(0.7))
                }
            }
            .foregroundStyle(.white)
            if let alert = state.alertTitle {
                Label(alert, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle((Risk(rawValue: state.alertSeverity) ?? .caution).color)
                    .lineLimit(2)
            } else if let odometer = state.odometer {
                Text("Contachilometri \(Fmt.number(odometer, decimals: 1, unit: "km"))").font(.caption).foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}
