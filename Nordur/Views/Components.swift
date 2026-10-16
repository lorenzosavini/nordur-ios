import SwiftUI

// MARK: - Containers

/// Dark surface panel with an uppercase section label.
struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    /// Kept for call-site compatibility; panels are deliberately neutral.
    var tint: Color = .primary
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
                Text(title)
            }
            .eyebrow()
            content
        }
        .panel()
    }
}

// MARK: - Badges and labels

struct RiskBadge: View {
    let risk: Risk
    var text: String?

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(risk.color).frame(width: 7, height: 7)
            Text(text ?? risk.label)
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(risk.color.opacity(0.14), in: Capsule())
        .foregroundStyle(risk.color)
    }
}

struct WarningBadge: View {
    let color: WarningColor

    var body: some View {
        Text(color.label)
            .font(.system(size: 10, weight: .bold).width(.expanded))
            .textCase(.uppercase)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.color, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .foregroundStyle(Theme.bg)
    }
}

/// When data was fetched and whether it comes from the offline cache.
struct FreshnessLabel: View {
    let date: Date?
    let isStale: Bool
    var source: String?

    var body: some View {
        if let date {
            HStack(spacing: 4) {
                if isStale { Image(systemName: "wifi.slash") }
                Text(isStale ? "Offline, dati di \(Fmt.relative(date))" : "Aggiornato \(Fmt.relative(date))")
                if let source { Text("· \(source)") }
            }
            .font(.system(size: 11))
            .foregroundStyle(isStale ? Theme.warning : Theme.faint)
        }
    }
}

struct ErrorNote: View {
    let message: String?

    var body: some View {
        if let message {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle")
                Text(message)
            }
            .font(.caption)
            .foregroundStyle(Theme.dim)
        }
    }
}

/// Label on top, value below in rounded digits.
struct Metric: View {
    let title: String
    let value: String
    var systemImage: String?
    var tint: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).eyebrow(Theme.faint).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.metric(19, .semibold)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
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
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: model.useCurrentLocation ? "location.fill" : "mappin")
                            .font(.system(size: 10, weight: .bold))
                        Text(model.useCurrentLocation ? "Posizione attuale" : (model.activePlace.subtitle ?? "Località"))
                    }
                    .eyebrow(Theme.accent)
                    Text(model.activePlace.name)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.dim)
                    .padding(9)
                    .background(Theme.raised, in: Circle())
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
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 30, height: 30)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).foregroundStyle(Theme.text)
                        if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Theme.dim) }
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.faint)
                }
            }
        }
    }
}

// MARK: - Data visualisations

/// Compass dial: ticks, cardinal letters, arrow towards where the wind blows, speed in the centre.
struct WindDial: View {
    let direction: Double?
    let speed: Double?
    let gust: Double?
    var size: CGFloat = 96

    var body: some View {
        let risk = Risk.wind(mean: speed, gust: gust)
        ZStack {
            Circle().fill(Theme.raised)
            ForEach(0..<36, id: \.self) { i in
                Rectangle()
                    .fill(i % 9 == 0 ? Theme.dim : Theme.faint.opacity(0.6))
                    .frame(width: i % 9 == 0 ? 2 : 1, height: i % 9 == 0 ? 7 : 4)
                    .offset(y: -size / 2 + 6)
                    .rotationEffect(.degrees(Double(i) * 10))
            }
            ForEach(Array(["N", "E", "S", "O"].enumerated()), id: \.offset) { item in
                let angle = Double(item.offset) * 90 * .pi / 180
                Text(item.element)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(item.element == "N" ? Theme.text : Theme.faint)
                    .offset(x: sin(angle) * (size / 2 - 18), y: -cos(angle) * (size / 2 - 18))
            }
            if let direction {
                Capsule()
                    .fill(risk.color)
                    .frame(width: 3, height: size * 0.3)
                    .offset(y: -size * 0.2)
                    .rotationEffect(.degrees(direction + 180))
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(risk.color)
                    .offset(y: -size * 0.36)
                    .rotationEffect(.degrees(direction + 180))
            }
            Circle().fill(Theme.surface).frame(width: size * 0.42, height: size * 0.42)
            VStack(spacing: -2) {
                Text(speed.map { "\(Int($0.rounded()))" } ?? "–").font(.metric(size * 0.2, .bold)).foregroundStyle(Theme.text)
                Text("m/s").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.faint)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Horizontal 0–40 m/s scale with the danger thresholds and markers for mean (hollow) and gust (filled).
struct GustScale: View {
    let mean: Double?
    let gust: Double?
    private let maxValue = 40.0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    segment(0, 10, Theme.ok, w)
                    segment(10, 18, Theme.caution, w)
                    segment(18, 25, Theme.warning, w)
                    segment(25, 40, Theme.danger, w)
                }
                if let mean { marker(mean, w, filled: false) }
                if let gust { marker(gust, w, filled: true) }
            }
            .frame(height: 14)
        }
        .frame(height: 14)
    }

    private func segment(_ from: Double, _ to: Double, _ color: Color, _ w: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.4))
            .frame(width: max(0, CGFloat((to - from) / maxValue) * w - 2), height: 4)
    }

    private func marker(_ value: Double, _ w: CGFloat, filled: Bool) -> some View {
        let x = CGFloat(min(value, maxValue) / maxValue) * w
        return Circle()
            .fill(filled ? Theme.text : Theme.surface)
            .overlay(Circle().strokeBorder(Theme.text, lineWidth: 2))
            .frame(width: 12, height: 12)
            .offset(x: x - 6)
    }
}

/// Sequence of small bars coloured by risk, one per hour.
struct RiskTimeline: View {
    let risks: [Risk]
    var labels: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(risks.enumerated()), id: \.offset) { item in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(item.element.color.opacity(item.element == .ok ? 0.45 : 0.95))
                        .frame(height: 8 + CGFloat(item.element.rawValue) * 5)
                }
            }
            .frame(height: 24, alignment: .bottom)
            if !labels.isEmpty {
                HStack {
                    ForEach(Array(labels.enumerated()), id: \.offset) { item in
                        Text(item.element).font(.system(size: 10)).foregroundStyle(Theme.faint)
                        if item.offset < labels.count - 1 { Spacer() }
                    }
                }
            }
        }
    }
}

/// 270° arc gauge.
struct ArcGauge: View {
    let value: Double          // 0…1
    let color: Color
    var lineWidth: CGFloat = 9
    var label: String
    var caption: String

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Theme.raised, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * max(0.02, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
            VStack(spacing: 0) {
                Text(label).font(.metric(28, .bold)).foregroundStyle(Theme.text)
                Text(caption).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.faint)
            }
        }
    }
}

/// Proportional bar split into coloured parts.
struct StackedBar: View {
    let parts: [(value: Double, color: Color)]

    var body: some View {
        GeometryReader { geo in
            let total = max(parts.map(\.value).reduce(0, +), 1)
            HStack(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { item in
                    if item.element.value > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(item.element.color)
                            .frame(width: max(3, geo.size.width * CGFloat(item.element.value / total) - 2))
                    }
                }
            }
        }
        .frame(height: 8)
    }
}

/// Minimal vertical bars for compact histograms.
struct MiniBars: View {
    let values: [Double]
    var maxValue: Double?
    var color: Color = Theme.accent
    var height: CGFloat = 34

    var body: some View {
        let top = max(maxValue ?? (values.max() ?? 1), 0.0001)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { item in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color.opacity(item.element > 0 ? 0.35 + 0.65 * min(1, item.element / top) : 0.12))
                    .frame(height: max(2, height * CGFloat(min(1, item.element / top))))
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}

/// Min–max temperature bar on a common scale, coloured by temperature.
struct RangeBar: View {
    let low: Double
    let high: Double
    let scaleMin: Double
    let scaleMax: Double

    var body: some View {
        GeometryReader { geo in
            let span = max(scaleMax - scaleMin, 1)
            let x0 = CGFloat((low - scaleMin) / span) * geo.size.width
            let x1 = CGFloat((high - scaleMin) / span) * geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.raised)
                Capsule()
                    .fill(LinearGradient(colors: [Theme.temperature(low), Theme.temperature(high)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, x1 - x0))
                    .offset(x: x0)
            }
        }
        .frame(height: 6)
    }
}

/// Day bar (midnight to midnight) with the daylight span and the current time.
struct DaylightBar: View {
    let sunrise: Date?
    let sunset: Date?
    var zone: TimeZone = .current
    var now = Date()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.raised)
                if let sunrise, let sunset, sunset > sunrise {
                    let start = startOfDay(sunrise)
                    let day: Double = 24 * 3600
                    let a = CGFloat(sunrise.timeIntervalSince(start) / day) * geo.size.width
                    let b = CGFloat(sunset.timeIntervalSince(start) / day) * geo.size.width
                    let n = CGFloat(min(max(now.timeIntervalSince(start) / day, 0), 1)) * geo.size.width
                    Capsule().fill(Theme.caution.opacity(0.55)).frame(width: max(4, b - a)).offset(x: a)
                    Circle().fill(Theme.text).frame(width: 9, height: 9).offset(x: n - 4.5)
                }
            }
        }
        .frame(height: 9)
    }

    private func startOfDay(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.startOfDay(for: date)
    }
}
