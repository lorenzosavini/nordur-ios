import SwiftUI

struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct RiskBadge: View {
    let risk: Risk
    var text: String?

    var body: some View {
        Label(text ?? risk.label, systemImage: risk.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(risk.color.opacity(0.2), in: Capsule())
            .foregroundStyle(risk == .caution ? Color.primary : risk.color)
    }
}

struct WarningBadge: View {
    let color: WarningColor

    var body: some View {
        Text(color.label.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.color, in: Capsule())
            .foregroundStyle(color == .yellow ? Color.black : Color.white)
    }
}

/// Shows when data was fetched and whether it comes from the offline cache.
struct FreshnessLabel: View {
    let date: Date?
    let isStale: Bool
    var source: String?

    var body: some View {
        if let date {
            HStack(spacing: 4) {
                Image(systemName: isStale ? "wifi.slash" : "clock")
                Text(isStale ? "Offline · dati di \(Fmt.relative(date))" : "Aggiornato \(Fmt.relative(date))")
                if let source { Text("· \(source)") }
            }
            .font(.caption2)
            .foregroundStyle(isStale ? Color.orange : Color.secondary)
        }
    }
}

struct ErrorNote: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.icloud")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct Metric: View {
    let title: String
    let value: String
    var systemImage: String?
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let systemImage {
                Label(title, systemImage: systemImage).font(.caption).foregroundStyle(.secondary)
            } else {
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Arrow pointing where the wind blows *to* (meteorological direction + 180°).
struct WindArrow: View {
    let degrees: Double?

    var body: some View {
        Image(systemName: "location.north.fill")
            .rotationEffect(.degrees((degrees ?? 0) + 180))
            .opacity(degrees == nil ? 0 : 1)
    }
}

struct PlaceHeader: View {
    @Environment(AppModel.self) private var model
    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack {
                Image(systemName: model.useCurrentLocation ? "location.fill" : "mappin.circle.fill")
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.activePlace.name).font(.title3.weight(.bold))
                    if let subtitle = model.activePlace.subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.down.circle").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPicker) {
            PlacePicker(allowCurrentLocation: true) { choice in
                switch choice {
                case .current: model.selectCurrentLocation()
                case .place(let place): model.select(place)
                }
            }
        }
    }
}

struct LinkRow: View {
    let title: String
    let subtitle: String?
    let url: String
    var systemImage: String = "safari"

    var body: some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                HStack {
                    Image(systemName: systemImage).frame(width: 28)
                    VStack(alignment: .leading) {
                        Text(title).foregroundStyle(.primary)
                        if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
