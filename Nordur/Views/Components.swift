import SwiftUI

// MARK: - Containers

/// A section: mono label with a rule, then the content. No box, no shadow.
struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    /// Kept for call-site compatibility; sections are deliberately neutral.
    var tint: Color = .primary
    var index: String?
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(index: index, title: title, trailing: trailing)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Badges and labels

/// Square status tag. Solid when it calls for action, outlined otherwise.
struct RiskBadge: View {
    let risk: Risk
    var text: String?

    var body: some View {
        let solid = risk >= .warning
        Text(text?.loc ?? risk.label)
            .font(.mono(10.5, .semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(solid ? Theme.onAccent : (risk == .ok ? Theme.dim : risk.color))
            .background(solid ? risk.color : .clear)
            .overlay(Rectangle().strokeBorder(solid ? .clear : (risk == .ok ? Theme.hairline : risk.color), lineWidth: 1))
    }
}

struct WarningBadge: View {
    let color: WarningColor

    var body: some View {
        Text(color.label)
            .font(.mono(9.5, .semibold))
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.color)
            .foregroundStyle(Color.black)
    }
}

/// When data was fetched, from where, and whether it comes from the offline cache.
struct FreshnessLabel: View {
    let date: Date?
    let isStale: Bool
    var source: String?

    var body: some View {
        if let date {
            HStack(spacing: 6) {
                if isStale { Text("OFFLINE").foregroundStyle(Theme.warning) }
                Text(isStale ? String(localized: "dati di \(Fmt.relative(date))") : String(localized: "agg. \(Fmt.relative(date))"))
                if let source { Text("· \(source.uppercased())") }
            }
            .font(.mono(10))
            .foregroundStyle(Theme.faint)
        }
    }
}

struct ErrorNote: View {
    let message: String?

    var body: some View {
        if let message {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("ERR").font(.mono(10, .semibold)).foregroundStyle(Theme.warning)
                Text(message.loc).font(.app(.caption)).foregroundStyle(Theme.dim)
            }
        }
    }
}

/// Mono label on top, condensed figure below.
struct Metric: View {
    let title: String
    let value: String
    var systemImage: String?
    var tint: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.loc).eyebrow(Theme.faint).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.metric(22, .semibold)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Reading with a separate unit, for data grids.
struct Reading: View {
    let label: String
    let value: String
    var unit: String = ""
    var note: String?
    var tint: Color = Theme.text
    var size: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.loc).eyebrow(Theme.faint).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.metric(size, .semibold)).foregroundStyle(tint)
                if !unit.isEmpty { Text(unit.loc).font(.mono(10.5)).foregroundStyle(Theme.dim) }
            }
            .lineLimit(1).minimumScaleFactor(0.6)
            if let note { Text(note.loc).font(.mono(10)).foregroundStyle(Theme.dim).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Grid of readings separated by hairlines.
struct ReadingGrid: View {
    let items: [Reading]
    var columns = 2

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { row in
                if row.offset > 0 { Rule() }
                HStack(spacing: 0) {
                    ForEach(Array(row.element.enumerated()), id: \.offset) { cell in
                        if cell.offset > 0 { Theme.hairline.frame(width: 1) }
                        cell.element.padding(.vertical, 10).padding(.leading, cell.offset > 0 ? 12 : 0)
                    }
                    if row.element.count < columns { Spacer() }
                }
            }
        }
    }
}

/// Arrow pointing where the wind blows *to* (meteorological direction + 180°).
struct WindArrow: View {
    let degrees: Double?

    var body: some View {
        Image(systemName: "arrow.up")
            .fontWeight(.semibold)
            .rotationEffect(.degrees((degrees ?? 0) + 180))
            .opacity(degrees == nil ? 0 : 1)
    }
}

/// Place selector: mono context line, condensed uppercase name.
struct PlaceHeader: View {
    @Environment(AppModel.self) private var model
    @State private var showPicker = false
    var onHero = false
    var size: CGFloat = 34

    init(onHero: Bool = false, size: CGFloat = 34) {
        self.onHero = onHero
        self.size = size
    }

    var body: some View {
        Button {
            showPicker = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if model.useCurrentLocation {
                        Rectangle().fill(Theme.accent).frame(width: 6, height: 6)
                    }
                    Text(model.useCurrentLocation ? String(localized: "GPS · posizione attuale") : (model.activePlace.subtitle ?? String(localized: "Località scelta")))
                        .eyebrow(Theme.dim)
                    Text(Fmt.coordinate(model.activePlace.coordinate)).font(.mono(10)).foregroundStyle(Theme.faint)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.activePlace.name.uppercased())
                        .font(.display(size, .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("CAMBIA").font(.mono(9.5, .semibold)).foregroundStyle(Theme.accent)
                    Spacer(minLength: 0)
                }
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
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title.loc).font(.app(.subheadline, .medium)).foregroundStyle(Theme.text)
                        if let subtitle { Text(subtitle.loc).font(.app(.caption)).foregroundStyle(Theme.dim) }
                    }
                    Spacer()
                    Text("↗").font(.mono(13, .medium)).foregroundStyle(Theme.accent)
                }
            }
        }
    }
}

// MARK: - Data visualisations

/// Compass rose: ticks, letters, arrow towards where the wind blows, speed in the centre.
struct WindDial: View {
    let direction: Double?
    let speed: Double?
    let gust: Double?
    var size: CGFloat = 96

    var body: some View {
        let risk = Risk.wind(mean: speed, gust: gust)
        let needle = risk >= .caution ? risk.color : Theme.text
        ZStack {
            Circle().strokeBorder(Theme.hairline, lineWidth: 1)
            ForEach(0..<72, id: \.self) { i in
                Rectangle()
                    .fill(i % 18 == 0 ? Theme.text : Theme.faint)
                    .frame(width: 1, height: i % 18 == 0 ? 8 : (i % 2 == 0 ? 4 : 2))
                    .offset(y: -size / 2 + 5)
                    .rotationEffect(.degrees(Double(i) * 5))
            }
            ForEach(Array(["N", "E", "S", "O"].enumerated()), id: \.offset) { item in
                let angle = Double(item.offset) * 90 * .pi / 180
                Text(item.element.loc)
                    .font(.mono(9, .semibold))
                    .foregroundStyle(item.element == "N" ? Theme.accent : Theme.dim)
                    .offset(x: sin(angle) * (size / 2 - 18), y: -cos(angle) * (size / 2 - 18))
            }
            if let direction {
                Rectangle()
                    .fill(needle)
                    .frame(width: 2, height: size * 0.62)
                    .rotationEffect(.degrees(direction + 180))
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: size * 0.1))
                    .foregroundStyle(needle)
                    .offset(y: -size * 0.31)
                    .rotationEffect(.degrees(direction + 180))
            }
            Rectangle().fill(Theme.bg).frame(width: size * 0.4, height: size * 0.3)
            VStack(spacing: -3) {
                Text(speed.map { "\(Int($0.rounded()))" } ?? "–").font(.metric(size * 0.22, .bold)).foregroundStyle(Theme.text)
                Text("M/S").font(.mono(7.5, .medium)).foregroundStyle(Theme.dim)
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
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 1) {
                        segment(0, 10, Theme.ok.opacity(0.35), w)
                        segment(10, 18, Theme.caution, w)
                        segment(18, 25, Theme.warning, w)
                        segment(25, 40, Theme.danger, w)
                    }
                    if let mean { marker(mean, w, filled: false) }
                    if let gust { marker(gust, w, filled: true) }
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            HStack {
                ForEach(["0", "10", "18", "25", "40"], id: \.self) { t in
                    Text(t).font(.mono(9)).foregroundStyle(Theme.faint)
                    if t != "40" { Spacer() }
                }
            }
        }
    }

    private func segment(_ from: Double, _ to: Double, _ color: Color, _ w: CGFloat) -> some View {
        Rectangle().fill(color)
            .frame(width: max(0, CGFloat((to - from) / maxValue) * w - 1), height: 3)
    }

    private func marker(_ value: Double, _ w: CGFloat, filled: Bool) -> some View {
        let x = CGFloat(min(value, maxValue) / maxValue) * w
        return Rectangle()
            .fill(filled ? Theme.text : Theme.bg)
            .overlay(Rectangle().strokeBorder(Theme.text, lineWidth: 1.5))
            .frame(width: filled ? 4 : 8, height: 16)
            .offset(x: x - (filled ? 2 : 4))
    }
}

/// Sequence of ticks coloured by risk, one per hour.
struct RiskTimeline: View {
    let risks: [Risk]
    var labels: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(risks.enumerated()), id: \.offset) { item in
                    Rectangle()
                        .fill(item.element == .ok ? Theme.hairline : item.element.color)
                        .frame(height: item.element == .ok ? 6 : 8 + CGFloat(item.element.rawValue) * 6)
                }
            }
            .frame(height: 28, alignment: .bottom)
            if !labels.isEmpty {
                HStack {
                    ForEach(Array(labels.enumerated()), id: \.offset) { item in
                        Text(item.element.loc).font(.mono(9.5)).foregroundStyle(Theme.faint)
                        if item.offset < labels.count - 1 { Spacer() }
                    }
                }
            }
        }
    }
}

/// Segmented linear gauge with a figure.
struct ArcGauge: View {
    let value: Double          // 0…1
    let color: Color
    var lineWidth: CGFloat = 9
    var label: String
    var caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(label.loc).font(.metric(40, .bold)).foregroundStyle(Theme.text)
                Text(caption.loc.uppercased()).font(.mono(9.5)).foregroundStyle(Theme.dim)
            }
            HStack(spacing: 2) {
                ForEach(0..<20, id: \.self) { i in
                    Rectangle().fill(Double(i) / 20 < value ? color : Theme.hairline)
                }
            }
            .frame(height: 8)
        }
    }
}

/// Proportional bar split into coloured parts.
struct StackedBar: View {
    let parts: [(value: Double, color: Color)]

    var body: some View {
        GeometryReader { geo in
            let total = max(parts.map(\.value).reduce(0, +), 1)
            HStack(spacing: 1) {
                ForEach(Array(parts.enumerated()), id: \.offset) { item in
                    if item.element.value > 0 {
                        Rectangle()
                            .fill(item.element.color)
                            .frame(width: max(3, geo.size.width * CGFloat(item.element.value / total) - 1))
                    }
                }
            }
        }
        .frame(height: 6)
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
        HStack(alignment: .bottom, spacing: 1) {
            ForEach(Array(values.enumerated()), id: \.offset) { item in
                Rectangle()
                    .fill(item.element > 0 ? color : Theme.hairline)
                    .frame(height: max(1, height * CGFloat(min(1, item.element / top))))
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}

/// Min–max temperature bar on a common scale.
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
                Rectangle().fill(Theme.hairline).frame(height: 1)
                Rectangle()
                    .fill(LinearGradient(colors: [Theme.temperature(low), Theme.temperature(high)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, x1 - x0), height: 4)
                    .offset(x: x0)
            }
        }
        .frame(height: 4)
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
                Rectangle().fill(Theme.hairline).frame(height: 1)
                if let sunrise, let sunset, sunset > sunrise {
                    let start = startOfDay(sunrise)
                    let day: Double = 24 * 3600
                    let a = CGFloat(sunrise.timeIntervalSince(start) / day) * geo.size.width
                    let b = CGFloat(sunset.timeIntervalSince(start) / day) * geo.size.width
                    let n = CGFloat(min(max(now.timeIntervalSince(start) / day, 0), 1)) * geo.size.width
                    Rectangle().fill(Theme.text).frame(width: max(4, b - a), height: 4).offset(x: a)
                    Rectangle().fill(Theme.accent).frame(width: 2, height: 12).offset(x: n - 1)
                }
            }
        }
        .frame(height: 12)
    }

    private func startOfDay(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.startOfDay(for: date)
    }
}
