import SwiftUI
import Charts

struct AuroraView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                PlaceHeader()
                NavigationLink {
                    AuroraLiveView()
                } label: {
                    HStack {
                        Text("Mappa aurora in tempo reale").font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                tonightCard
                kpCard
                spaceCard
                linksCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Aurora boreale")
        .refreshable { await model.refreshAll() }
    }

    private var zone: TimeZone { model.forecast?.value.timeZone ?? .current }

    @ViewBuilder private var tonightCard: some View {
        Card(title: "Le prossime 24 ore", systemImage: "moon.stars.fill", tint: .mint) {
            if let outlook = model.auroraOutlook {
                Text(outlook.verdict.text).font(.title3.weight(.semibold))
                if outlook.hasDarkness {
                    Chart(outlook.darkHours) { hour in
                        BarMark(x: .value("Ora", hour.date, unit: .hour), y: .value("Punteggio", hour.score))
                            .foregroundStyle(Color.accentColor)
                    }
                    .chartYScale(domain: 0...100)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                            AxisValueLabel(format: .dateTime.hour())
                        }
                    }
                    .frame(height: 140)

                    ForEach(outlook.darkHours) { hour in
                        HStack {
                            Text(Fmt.time(hour.date, in: zone)).font(.subheadline.monospacedDigit()).frame(width: 52, alignment: .leading)
                            Label(Fmt.percent(hour.cloudCover), systemImage: "cloud.fill").font(.caption)
                                .frame(width: 70, alignment: .leading)
                            Text("Kp \(Fmt.number(hour.kp, decimals: 1))").font(.caption)
                            Spacer()
                            Text("\(hour.score)").font(.subheadline.weight(.bold)).foregroundStyle(hour.score >= 35 ? Color.green : Color.secondary)
                        }
                    }
                } else {
                    Text("Tra metà maggio e inizio agosto in Islanda il cielo non si fa mai abbastanza buio.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
            }
        }
    }

    @ViewBuilder private var kpCard: some View {
        Card(title: "Indice Kp – 3 giorni", systemImage: "chart.bar.fill", tint: .purple) {
            if let points = model.kp?.value, !points.isEmpty {
                let recent = points.filter { $0.date >= Date().addingTimeInterval(-24 * 3600) }
                Chart(recent) { point in
                    BarMark(x: .value("Ora", point.date, unit: .hour), y: .value("Kp", point.kp), width: .fixed(8))
                        .foregroundStyle(point.kp >= 5 ? Color.red : point.kp >= 4 ? Color.orange : Color.green)
                        .opacity(point.isForecast ? 0.6 : 1)
                }
                .chartYScale(domain: 0...9)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.weekday().day())
                    }
                }
                .frame(height: 150)
                if let fetched = model.kp { FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: "NOAA SWPC") }
            } else {
                ErrorNote(message: model.errors[.kp])
            }
        }
    }

    @ViewBuilder private var spaceCard: some View {
        Card(title: "Adesso nello spazio", systemImage: "sun.max.trianglebadge.exclamationmark", tint: .orange) {
            HStack {
                let local = model.ovation?.value.horizonProbability(at: model.activePlace.coordinate)
                Metric(title: "Ovale aurorale", value: Fmt.percent(local))
                Metric(title: "Bz", value: Fmt.number(model.solarWind?.value.bz, decimals: 1, unit: "nT"),
                       tint: (model.solarWind?.value.bz ?? 0) < -5 ? .green : .primary)
                Metric(title: "Vento solare", value: Fmt.number(model.solarWind?.value.speed, unit: "km/s"))
            }
            if model.solarWind?.value.favourable == true {
                Label("Bz negativo e vento solare veloce: condizioni favorevoli", systemImage: "arrow.down.circle")
                    .font(.caption.weight(.semibold)).foregroundStyle(.green)
            }
        }
    }

    private var linksCard: some View {
        Card(title: "Fonti specialistiche", systemImage: "link", tint: .blue) {
            LinkRow(title: "Previsione aurora e nuvole – Vedur.is", subtitle: "Mappa ufficiale della copertura nuvolosa", url: "https://en.vedur.is/weather/forecasts/aurora/")
            LinkRow(title: "NOAA – Previsione 30 minuti", subtitle: "Ovale aurorale animato", url: "https://www.swpc.noaa.gov/products/aurora-30-minute-forecast")
            LinkRow(title: "NOAA – Previsione 3 giorni", subtitle: nil, url: "https://www.swpc.noaa.gov/products/3-day-forecast")
        }
    }
}
