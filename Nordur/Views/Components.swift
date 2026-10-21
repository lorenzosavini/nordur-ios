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
                ForEach([0.0, 10, 18, 25, 40].map { Fmt.wind($0) }, id: \.self) { t in
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
            .ciHiddenFromAccessibility()
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

/// The photograph fills whatever frame it is given and never widens it
/// (a wide image with scaledToFill would push a grid cell wider than its column).
struct HeroPhoto: View {
    let hero: Hero
    var body: some View {
        Color.clear
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .overlay { Image(hero.asset).resizable().scaledToFill() }
            .clipped()
            .accessibilityHidden(true)
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
            HeroPhoto(hero: hero)
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
        tile.accessibilityElement(children: .combine).accessibilityIdentifier("tile.\(title)")
    }

    private var tile: some View {
        ZStack(alignment: .bottomLeading) {
            HeroPhoto(hero: hero)
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

// MARK: - Remote images

/// Downloaded pictures kept in memory for the session (webcam frames).
@MainActor
final class RemoteImageCache {
    static let shared = RemoteImageCache()
    private let cache = NSCache<NSURL, UIImage>()
    init() { cache.countLimit = 120 }
    func image(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }
    func store(_ image: UIImage, _ url: URL) { cache.setObject(image, forKey: url as NSURL) }
}

/// Image from the network that survives re-renders: SwiftUI's AsyncImage
/// cancels its download every time a busy screen redraws (Today redraws often),
/// so webcam previews never appeared there.
struct RemoteImage: View {
    let url: URL
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else if failed {
                Image(systemName: "video.slash").foregroundStyle(Theme.faint)
            } else {
                ProgressView().tint(Theme.dim)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        if let cached = RemoteImageCache.shared.image(url) { image = cached; failed = false; return }
        for attempt in 0..<2 {
            do {
                let (data, response) = try await HTTP.session.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200, let picture = UIImage(data: data) else { throw URLError(.badServerResponse) }
                RemoteImageCache.shared.store(picture, url)
                image = picture
                failed = false
                return
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                if attempt == 0 { try? await Task.sleep(nanoseconds: 1_500_000_000) }
            }
        }
        if image == nil { failed = true }
    }
}

// MARK: - Place backdrop

/// Photograph of the active place behind Today's header: lightly softened so
/// the place stays recognisable, with a wash of the background colour that is
/// light at the top and grows to opaque at the bottom (where the text sits),
/// and a small credit.
struct PlaceBackdrop: View {
    @Environment(AppModel.self) private var model
    var height: CGFloat = 330
    @State private var photo: PlacePhoto?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let photo {
                RemoteImage(url: photo.imageURL)
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .blur(radius: 1.5, opaque: true)
                    .overlay {
                        LinearGradient(stops: [
                            .init(color: Theme.bg.opacity(0.18), location: 0),
                            .init(color: Theme.bg.opacity(0.38), location: 0.45),
                            .init(color: Theme.bg.opacity(0.78), location: 0.78),
                            .init(color: Theme.bg, location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                    }
                    .transition(.opacity)
                Text(photo.credit)
                    .font(.mono(7.5)).foregroundStyle(Theme.faint)
                    .lineLimit(1)
                    .padding(.trailing, 18).padding(.bottom, 6)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityHidden(true)
        .task(id: model.activePlace.name + model.placeKey) {
            let found = await PlacePhotoService.shared.photo(for: model.activePlace)
            withAnimation(.easeInOut(duration: 0.4)) { photo = found }
        }
    }
}

// MARK: - Coverage

/// Shown where a section's data exist for Iceland only and the active place is
/// elsewhere: says so instead of showing Icelandic data that do not apply.
struct CoverageNote: View {
    let feature: String
    var showsIcelandData = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "globe.europe.africa.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.caution)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text("FUORI COPERTURA").font(.mono(10, .semibold)).tracking(0.8).foregroundStyle(Theme.caution)
                Text(showsIcelandData
                     ? String(localized: "\(feature): per ora solo in Islanda. Qui sotto vedi i dati dell'Islanda, non della tua zona.")
                     : String(localized: "\(feature): per ora solo in Islanda, per la tua zona non ci sono dati. Meteo, mare, qualità dell'aria e aurora restano attivi."))
                    .font(.app(.subheadline)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .overlay(alignment: .leading) { Theme.caution.frame(width: 3) }
        .overlay(Rectangle().strokeBorder(Theme.hairline))
    }
}

// MARK: - Loading placeholders, empty states, haptics

/// Grey blocks in the shape of the content while it loads (instead of a spinner
/// on an empty page), with a slow shimmer; static when Reduce Motion is on.
struct SkeletonBlock: View {
    var lines = 3
    var height: CGFloat = 12
    var showsFigure = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsFigure {
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { _ in bar(height: 38) }
                }
            }
            ForEach(0..<lines, id: \.self) { i in
                bar(height: height).frame(maxWidth: i == lines - 1 ? 180 : .infinity, alignment: .leading)
            }
        }
        .opacity(reduceMotion ? 0.7 : (phase ? 0.45 : 0.9))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: phase)
        .onAppear { phase = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Caricamento"))
    }

    private func bar(height: CGFloat) -> some View {
        Rectangle().fill(Theme.hairline).frame(maxWidth: .infinity).frame(height: height)
    }
}

/// Placeholder rows for lists while they load.
struct SkeletonRows: View {
    var count = 5

    var body: some View {
        ForEach(0..<count, id: \.self) { _ in
            SkeletonBlock(lines: 2, height: 10, showsFigure: false).padding(.vertical, 4)
        }
    }
}

/// A list or section with nothing to show: says why, and what to do.
struct EmptyState: View {
    let symbol: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(title.loc).font(.app(.headline)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            if let message {
                Text(message.loc).font(.app(.caption)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .accessibilityElement(children: .combine)
    }
}

/// Short vibrations for actions (taps on switches, success or failure).
@MainActor
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func result(_ success: Bool) {
        UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error)
    }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

// MARK: - Offline strip

/// One strip at the top when the phone has no connection: what is shown comes
/// from the copies saved on the phone, and from when.
struct OfflineBanner: View {
    @Environment(AppModel.self) private var model
    private var connectivity: Connectivity { .shared }

    var body: some View {
        if !connectivity.isOnline {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash").font(.system(size: 11, weight: .bold))
                Text(label).font(.mono(10, .semibold)).tracking(0.5).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.warning, in: Capsule())
            .padding(.top, 2)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }

    private var label: String {
        let dates = [model.forecast?.date, model.warnings?.date, model.roads?.date].compactMap { $0 }
        guard let oldest = dates.min() else { return String(localized: "OFFLINE · NESSUN DATO SALVATO") }
        return String(localized: "OFFLINE · DATI DELLE \(Fmt.time(oldest))")
    }
}

// MARK: - Directions

/// Driving directions in Apple Maps or Google Maps (the Google link opens the
/// app when it is installed, the website otherwise).
enum Directions {
    static func apple(from: Coordinate? = nil, to: Coordinate) -> URL {
        let start = from.map { "saddr=\($0.lat),\($0.lon)&" } ?? ""
        return URL(string: "http://maps.apple.com/?\(start)daddr=\(to.lat),\(to.lon)&dirflg=d")!
    }

    static func google(from: Coordinate? = nil, to: Coordinate) -> URL {
        let start = from.map { "&origin=\($0.lat),\($0.lon)" } ?? ""
        return URL(string: "https://www.google.com/maps/dir/?api=1\(start)&destination=\(to.lat),\(to.lon)&travelmode=driving")!
    }
}

/// One row per app, for lists.
struct DirectionsRows: View {
    let to: Coordinate
    var from: Coordinate?

    var body: some View {
        Link(destination: Directions.apple(from: from, to: to)) {
            Label("Indicazioni con Apple Mappe", systemImage: "arrow.triangle.turn.up.right.diamond")
        }
        Link(destination: Directions.google(from: from, to: to)) {
            Label("Indicazioni con Google Maps", systemImage: "arrow.triangle.turn.up.right.circle")
        }
    }
}

/// A single button that asks which app to use.
struct DirectionsMenu<LabelView: View>: View {
    let to: Coordinate
    var from: Coordinate?
    @ViewBuilder let label: () -> LabelView

    var body: some View {
        Menu {
            Link(destination: Directions.apple(from: from, to: to)) { Label("Apple Mappe", systemImage: "map") }
            Link(destination: Directions.google(from: from, to: to)) { Label("Google Maps", systemImage: "globe") }
        } label: { label() }
    }
}

// MARK: - Place pictures

extension AttractionKind {
    /// Illustration in the asset catalog (Kinds/kind-<name>).
    var imageName: String { "kind-\(rawValue)" }
}

extension Shop.Kind {
    var imageName: String { "kind-\(rawValue)" }
}

/// The illustration of a kind of place, as a rounded tile.
struct KindIcon: View {
    let name: String
    var size: CGFloat = 44

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A photo of the place (the lead image of its Wikipedia article) when there is
/// one, otherwise the illustration of its kind.
struct PlaceThumb: View {
    let place: Place
    var kind: AttractionKind?
    var size: CGFloat = 56
    /// Look the photo up (for stops and the best-known sights only, to keep the lookups few).
    var photo = true
    @State private var picture: PlacePhoto?

    var body: some View {
        ZStack {
            KindIcon(name: (kind ?? .landscape).imageName, size: size)
            if let picture {
                RemoteImage(url: picture.imageURL)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if picture != nil, let kind {
                // The kind stays readable on the photo.
                KindIcon(name: kind.imageName, size: size * 0.36)
                    .overlay(RoundedRectangle(cornerRadius: size * 0.08, style: .continuous).strokeBorder(.white, lineWidth: 1.5))
                    .offset(x: 3, y: 3)
            }
        }
        .task(id: place.coordinate.key + place.name) {
            guard photo else { return }
            let found = await PlacePhotoService.shared.photo(for: place)
            withAnimation(.easeOut(duration: 0.2)) { picture = found }
        }
    }
}

/// A wide photo of a place with its name on it, for the head of a day or stop.
struct PlaceBanner<Overlay: View>: View {
    let place: Place
    var height: CGFloat = 130
    @ViewBuilder var overlay: () -> Overlay
    @State private var picture: PlacePhoto?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(LinearGradient(colors: [Theme.raised, Theme.surface], startPoint: .top, endPoint: .bottom))
            if let picture {
                RemoteImage(url: picture.imageURL)
                    .frame(height: height).frame(maxWidth: .infinity).clipped()
                    .transition(.opacity)
            }
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            overlay().padding(12)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: place.coordinate.key + place.name) {
            let found = await PlacePhotoService.shared.photo(for: place)
            withAnimation(.easeOut(duration: 0.25)) { picture = found }
        }
    }
}

/// The head of a place's page: a large photo (with its credit) and the opening
/// lines of its Wikipedia article; the illustration of its kind when there is none.
struct PlaceHero: View {
    let place: Place
    var kind: AttractionKind?
    var kindImage: String?
    var title: String
    var eyebrow: String
    var describe = true
    @State private var picture: PlacePhoto?
    @State private var summary: String?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                if let picture {
                    RemoteImage(url: picture.imageURL)
                        .frame(height: 230).frame(maxWidth: .infinity).clipped()
                        .transition(.opacity)
                } else {
                    ZStack {
                        Rectangle().fill(LinearGradient(colors: [Theme.raised, Theme.surface], startPoint: .top, endPoint: .bottom))
                        KindIcon(name: kindImage ?? (kind ?? .landscape).imageName, size: 110)
                            .opacity(loaded ? 1 : 0.5)
                    }
                    .frame(height: 230)
                }
                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow.uppercased()).font(.mono(11.5, .semibold)).foregroundStyle(.white.opacity(0.9))
                    Text(title).font(.display(32, .bold)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.7)
                }
                .shadow(color: .black.opacity(0.5), radius: 4)
                .padding(14)
            }
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if let picture {
                Text(picture.credit).font(.mono(9)).foregroundStyle(Theme.faint).lineLimit(1)
            }
            if let summary {
                if let picture, picture.title.localizedCaseInsensitiveCompare(place.name) != .orderedSame {
                    // The nearest article when the place has none of its own: say which.
                    Text(String(localized: "Da Wikipedia: \(picture.title)")).font(.mono(10.5, .semibold)).foregroundStyle(Theme.dim)
                }
                Text(summary).font(.app(.subheadline)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let page = picture?.page {
                    Link(destination: page) {
                        Label("Leggi su Wikipedia", systemImage: "book").font(.app(.caption, .semibold))
                    }
                }
            }
        }
        .task(id: place.coordinate.key + place.name) {
            let found = await PlacePhotoService.shared.photo(for: place)
            withAnimation(.easeOut(duration: 0.25)) { picture = found; loaded = true }
            if describe, found != nil {
                let text = await PlacePhotoService.shared.summary(for: place)
                withAnimation(.easeOut(duration: 0.2)) { summary = text }
            }
        }
    }
}

extension View {
    /// CI only (the demo video): maps with many pins make the accessibility tree
    /// so large that reading it from idb hangs the app, so they leave it there.
    @ViewBuilder func ciHiddenFromAccessibility() -> some View {
        if UserDefaults.standard.bool(forKey: "ciDemoTrip") { accessibilityHidden(true) } else { self }
    }
}
