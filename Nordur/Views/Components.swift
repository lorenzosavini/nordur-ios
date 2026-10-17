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

// MARK: - Maps

/// An embedded map with a button that opens the same map full screen
/// (pan, zoom, rotate), with an optional legend below it.
struct ExpandableMap<MapBody: View, Legend: View>: View {
    var height: CGFloat
    var title: String
    var map: () -> MapBody
    var legend: () -> Legend
    @State private var fullScreen = false

    init(height: CGFloat, title: String, @ViewBuilder map: @escaping () -> MapBody, @ViewBuilder legend: @escaping () -> Legend) {
        self.height = height
        self.title = title
        self.map = map
        self.legend = legend
    }

    var body: some View {
        map()
            .frame(height: height)
            .clipShape(Rectangle())
            .overlay(alignment: .topTrailing) {
                Button { fullScreen = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 36, height: 36)
                        .background(Theme.bg.opacity(0.92))
                        .overlay(Rectangle().strokeBorder(Theme.hairline))
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel(String(localized: "Mappa a schermo intero"))
            }
            .fullScreenCover(isPresented: $fullScreen) {
                NavigationStack {
                    VStack(spacing: 0) {
                        map().ignoresSafeArea(edges: .bottom)
                        legend()
                    }
                    .background(Theme.bg)
                    .navigationTitle(title.loc)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(String(localized: "Chiudi")) { fullScreen = false }
                        }
                    }
                }
            }
    }
}

extension ExpandableMap where Legend == EmptyView {
    init(height: CGFloat, title: String, @ViewBuilder map: @escaping () -> MapBody) {
        self.init(height: height, title: title, map: map, legend: { EmptyView() })
    }
}

/// Lays out its children left to right and wraps to a new line when the row is
/// full: filter chips stay all visible without horizontal scrolling.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].items.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width && !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.items.isEmpty }
    }
}

/// Norður logo mark: a tall Ð (Barlow Condensed Bold) with the crossbar in the
/// signal orange, the same drawing as the app icon (tools/brand/make_icon.py).
struct LogoMark: View {
    var size: CGFloat = 22

    var body: some View {
        Text("D")
            .font(.custom("BarlowCondensed-Bold", fixedSize: size * 1.25))
            .foregroundStyle(Theme.text)
            .overlay(alignment: .leading) {
                Theme.accent
                    .frame(width: size * 0.42, height: max(2, size * 0.11))
                    .offset(x: -size * 0.12, y: size * 0.04)
            }
            .frame(height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Hero images

/// Photographs bundled with the app (Wikimedia Commons, free licences; credits
/// in THIRD_PARTY_NOTICES.md and in Info › Crediti).
enum Hero: String, CaseIterable {
    case aurora, roads, weather, map, trip, volcano, drive

    var asset: String { "hero-\(rawValue)" }

    /// Title, author, licence and source page (Wikimedia Commons).
    var credit: (title: String, author: String, license: String, page: String) {
        switch self {
        case .aurora: return ("Church of light.jpg", "AstroAnthony", "CC BY 4.0", "https://commons.wikimedia.org/wiki/File:Church_of_light.jpg")
        case .roads: return ("Driving in Iceland can be challenging (40217475782).jpg", "Winniepix", "CC BY 2.0", "https://commons.wikimedia.org/wiki/File:Driving_in_Iceland_can_be_challenging_(40217475782).jpg")
        case .weather: return ("Crepuscular rays break through clouds in Iceland.jpg", "Thomas Heins", "CC BY 4.0", "https://commons.wikimedia.org/wiki/File:Crepuscular_rays_break_through_clouds_in_Iceland.jpg")
        case .map: return ("Iceland (15082529060).jpg", "NASA Goddard Space Flight Center", "Public domain", "https://commons.wikimedia.org/wiki/File:Iceland_(15082529060).jpg")
        case .trip: return ("Kirkjufell, Iceland (Unsplash LoKG7kKx7Zc).jpg", "Steven Diaz stevendiazphoto", "CC0", "https://commons.wikimedia.org/wiki/File:Kirkjufell,_Iceland_(Unsplash_LoKG7kKx7Zc).jpg")
        case .volcano: return ("Iceland's Fagradalsfjall volcano.png", "Mokslo Sriuba", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Iceland%27s_Fagradalsfjall_volcano.png")
        case .drive: return ("Saturday Winter Afternoon on the Road from the Factory, Iceland - panoramio.jpg", "Petr Kraumann", "CC BY 3.0", "https://commons.wikimedia.org/wiki/File:Saturday_Winter_Afternoon_on_the_Road_from_the_Factory,_Iceland_-_panoramio.jpg")
        }
    }
}

/// Full-width photograph with the section title over a dark gradient.
struct HeroHeader: View {
    let hero: Hero
    var eyebrow: String?
    let title: String
    var subtitle: String?
    var height: CGFloat = 210

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(hero.asset)
                .resizable()
                .scaledToFill()
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .clipped()
                .accessibilityHidden(true)
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.25), .black.opacity(0.78)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                if let eyebrow {
                    Text(eyebrow.uppercased()).font(.mono(10, .semibold)).tracking(0.9).foregroundStyle(.white.opacity(0.85))
                }
                Text(title).font(.display(38, .bold)).foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle).font(.sans(13.5, .medium)).foregroundStyle(.white.opacity(0.88))
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .frame(height: height)
        .clipped()
    }
}

/// Tile with a photograph, a title and one live line, for the Today screen.
struct HeroTile: View {
    let hero: Hero
    let title: String
    var status: String?
    var statusColor: Color = .white

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(hero.asset).resizable().scaledToFill()
                .frame(height: 118).frame(maxWidth: .infinity).clipped()
                .accessibilityHidden(true)
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased()).font(.mono(11, .semibold)).tracking(0.7).foregroundStyle(.white)
                if let status {
                    Text(status).font(.sans(12.5, .medium)).foregroundStyle(statusColor).lineLimit(2)
                }
            }
            .padding(10)
        }
        .frame(height: 118)
        .clipped()
        .contentShape(Rectangle())
    }
}

extension View {
    /// A hero header as the first row of a List: edge to edge, no separator.
    func heroRow() -> some View {
        listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.clear)
    }
}
