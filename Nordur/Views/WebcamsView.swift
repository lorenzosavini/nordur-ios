import SwiftUI

struct WebcamsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        let here = model.activePlace.coordinate
        let sites = (model.webcams?.value ?? [])
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.road.localizedCaseInsensitiveContains(query) }
            .sorted { Geo.distanceKm($0.coordinate, here) < Geo.distanceKm($1.coordinate, here) }
        List {
            Section {
                HeroHeader(hero: .drive, eyebrow: String(localized: "Vegagerðin"), title: String(localized: "Webcam stradali"), subtitle: String(localized: "Le strade come sono adesso"))
                    .heroRow()
            }
            .listSectionSeparator(.hidden)
            if !model.inIceland {
                Section { CoverageNote(feature: String(localized: "Le webcam stradali"), showsIcelandData: true) }
                    .listRowSeparator(.hidden)
            }
            if let fetched = model.webcams {
                FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: String(localized: "Vegagerðin"))
            }
            ErrorNote(message: model.errors[.webcams])
            if model.webcams == nil && model.errors[.webcams] == nil {
                SkeletonRows()
            } else if sites.isEmpty {
                EmptyState(symbol: "video.slash", title: String(localized: "Nessuna webcam trovata"),
                           message: query.isEmpty ? nil : String(localized: "Prova con il nome di una strada o di un passo."))
            }
            ForEach(sites) { site in
                NavigationLink {
                    WebcamSiteView(site: site)
                } label: {
                    HStack {
                        WebcamThumb(site: site, width: 96)
                        VStack(alignment: .leading) {
                            Text(site.name).font(.app(.subheadline, .semibold))
                            Text(site.road).font(.app(.caption)).foregroundStyle(.secondary)
                            Text("\(Int(Geo.distanceKm(site.coordinate, here))) km · \(site.images.count) immagini").font(.app(.caption2)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .themedList()
        .navigationTitle("Webcam stradali")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: String(localized: "Cerca webcam o strada"))
        .refreshable { await model.refreshStatic(force: true) }
        .task { if model.webcams == nil { await model.refreshStatic() } }
    }
}

struct WebcamThumb: View {
    let site: WebcamSite
    var width: CGFloat = 150

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Theme.raised
            if let image = site.images.first {
                RemoteImage(url: Webcams.fresh(image.url))
                    .frame(width: width, height: width * 0.62)
                .clipped()
            }
            if width >= 140 {
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 1) {
                    Text(site.name).font(.app(.caption, .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(site.road).font(.sans(10)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                .padding(8)
            }
        }
        .frame(width: width, height: width * 0.62)
        .clipShape(Rectangle())
        .overlay(Rectangle().strokeBorder(Theme.hairline))
    }
}

struct WebcamSiteView: View {
    let site: WebcamSite
    @State private var reload = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(site.road).font(.app(.subheadline)).foregroundStyle(.secondary)
                ForEach(site.images) { image in
                    VStack(alignment: .leading, spacing: 4) {
                        RemoteImage(url: Webcams.fresh(image.url).appending(queryItems: [URLQueryItem(name: "r", value: String(Int(reload.timeIntervalSince1970)))]),
                                    contentMode: .fit)
                            .frame(maxWidth: .infinity, minHeight: 180)
                            .clipShape(Rectangle())
                        Text(image.caption).font(.app(.caption)).foregroundStyle(.secondary)
                    }
                }
                Text("Immagini Vegagerðin, aggiornate ogni pochi minuti.").font(.app(.caption2)).foregroundStyle(.secondary)
            }
            .padding()
        }
        .themedList()
        .navigationTitle(site.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { reload = Date() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { reload = Date() } label: { Image(systemName: "arrow.clockwise") }
            }
        }
    }
}
