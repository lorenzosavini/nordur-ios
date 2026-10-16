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
            if let fetched = model.webcams {
                FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: "Vegagerðin")
            }
            ErrorNote(message: model.errors[.webcams])
            ForEach(sites) { site in
                NavigationLink {
                    WebcamSiteView(site: site)
                } label: {
                    HStack {
                        WebcamThumb(site: site, width: 96)
                        VStack(alignment: .leading) {
                            Text(site.name).font(.subheadline.weight(.semibold))
                            Text(site.road).font(.caption).foregroundStyle(.secondary)
                            Text("\(Int(Geo.distanceKm(site.coordinate, here))) km · \(site.images.count) immagini").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Webcam stradali")
        .searchable(text: $query, prompt: "Cerca webcam o strada")
        .refreshable { await model.refreshStatic(force: true) }
        .task { if model.webcams == nil { await model.refreshStatic() } }
    }
}

struct WebcamThumb: View {
    let site: WebcamSite
    var width: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let image = site.images.first {
                AsyncImage(url: Webcams.fresh(image.url)) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    case .failure: Image(systemName: "video.slash").foregroundStyle(.secondary)
                    default: ProgressView()
                    }
                }
                .frame(width: width, height: width * 0.6)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if width >= 140 {
                Text(site.name).font(.caption2).lineLimit(1).frame(width: width, alignment: .leading)
            }
        }
    }
}

struct WebcamSiteView: View {
    let site: WebcamSite
    @State private var reload = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(site.road).font(.subheadline).foregroundStyle(.secondary)
                ForEach(site.images) { image in
                    VStack(alignment: .leading, spacing: 4) {
                        AsyncImage(url: Webcams.fresh(image.url).appending(queryItems: [URLQueryItem(name: "r", value: String(Int(reload.timeIntervalSince1970)))])) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFit()
                            case .failure: Label("Immagine non disponibile", systemImage: "video.slash").foregroundStyle(.secondary)
                            default: ProgressView().frame(maxWidth: .infinity, minHeight: 180)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        Text(image.caption).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Immagini Vegagerðin, aggiornate ogni pochi minuti.").font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
        }
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
