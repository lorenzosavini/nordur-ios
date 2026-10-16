import SwiftUI
import WebKit

/// Windy's embeddable animated map (wind particles, radar, waves…) inside the app.
struct WindyView: View {
    let layer: WeatherLayer
    let center: Coordinate
    @Environment(\.dismiss) private var dismiss
    @State private var overlay = "wind"

    static let overlays: [(id: String, label: String)] = [
        ("wind", "Vento"), ("gust", "Raffiche"), ("rain", "Pioggia"), ("snowAccu", "Neve accumulata"),
        ("clouds", "Nuvole"), ("temp", "Temperatura"), ("waves", "Onde"), ("swell1", "Onda lunga"),
        ("visibility", "Visibilità"), ("cape", "Temporali (CAPE)"), ("pressure", "Pressione"),
    ]

    private var url: URL? {
        var components = URLComponents(string: "https://embed.windy.com/embed.html")
        components?.queryItems = [
            .init(name: "type", value: "map"), .init(name: "location", value: "coordinates"),
            .init(name: "metricRain", value: "mm"), .init(name: "metricTemp", value: "°C"), .init(name: "metricWind", value: "m/s"),
            .init(name: "zoom", value: "6"), .init(name: "overlay", value: overlay), .init(name: "product", value: "ecmwf"),
            .init(name: "level", value: "surface"), .init(name: "lat", value: String(format: "%.3f", center.lat)),
            .init(name: "lon", value: String(format: "%.3f", center.lon)), .init(name: "message", value: "true"),
            .init(name: "calendar", value: "now"), .init(name: "pressure", value: "true"),
        ]
        return components?.url
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Self.overlays, id: \.id) { item in
                            Button(item.label) { overlay = item.id }
                                .font(.app(.caption, .semibold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(overlay == item.id ? Color.accentColor : Color.clear, in: Rectangle())
                                .foregroundStyle(overlay == item.id ? Color.white : Color.primary)
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
                if let url { WebView(url: url).ignoresSafeArea(edges: .bottom) }
            }
            .themedList()
            .navigationTitle("Windy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            .onAppear {
                switch layer {
                case .gust: overlay = "gust"
                case .precipitation, .radar: overlay = "rain"
                case .snow: overlay = "snowAccu"
                case .cloud, .aurora: overlay = "clouds"
                case .temperature: overlay = "temp"
                default: overlay = "wind"
                }
            }
        }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: config)
        view.scrollView.isScrollEnabled = false
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        if view.url?.absoluteString != url.absoluteString {
            view.load(URLRequest(url: url))
        }
    }
}
