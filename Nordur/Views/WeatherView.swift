import SwiftUI
import Charts

struct WeatherView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    PlaceHeader()
                    if let fetched = model.forecast {
                        let forecast = fetched.value
                        let next48 = forecast.upcomingHours(48)
                        temperatureChart(next48, zone: forecast.timeZone)
                        windChart(next48, zone: forecast.timeZone)
                        hourlyList(Array(next48.prefix(24)), zone: forecast.timeZone)
                        dailyList(forecast.days, zone: forecast.timeZone)
                        FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: "Open-Meteo")
                    } else if let error = model.errors[.forecast] {
                        ErrorNote(message: error)
                    } else {
                        ProgressView().padding(40)
                    }
                    seaCard
                    airCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Meteo")
            .refreshable { await model.refreshPlace() }
        }
    }

    // MARK: Charts

    private func temperatureChart(_ hours: [HourPoint], zone: TimeZone) -> some View {
        Card(title: "Temperatura e precipitazioni – 48 ore", systemImage: "thermometer.medium") {
            Chart {
                ForEach(hours) { hour in
                    if let precip = hour.precipitation, precip > 0 {
                        BarMark(x: .value("Ora", hour.date, unit: .hour), y: .value("mm", precip))
                            .foregroundStyle(.blue.opacity(0.35))
                    }
                    if let temp = hour.temperature {
                        LineMark(x: .value("Ora", hour.date, unit: .hour), y: .value("°C", temp))
                            .foregroundStyle(.orange)
                            .interpolationMethod(.catmullRom)
                    }
                }
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.cyan.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().day(), centered: false)
                }
            }
            .frame(height: 170)
            Text("Linea arancione: °C · barre blu: pioggia/neve in mm · tratteggio: 0 °C")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func windChart(_ hours: [HourPoint], zone: TimeZone) -> some View {
        Card(title: "Vento e raffiche – 48 ore", systemImage: "wind") {
            Chart {
                ForEach(hours) { hour in
                    if let gust = hour.gust {
                        AreaMark(x: .value("Ora", hour.date, unit: .hour), y: .value("Raffiche", gust))
                            .foregroundStyle(.red.opacity(0.18))
                    }
                    if let wind = hour.wind {
                        LineMark(x: .value("Ora", hour.date, unit: .hour), y: .value("Vento", wind))
                            .foregroundStyle(.teal)
                    }
                }
                RuleMark(y: .value("Pericolo", 25))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("raffiche 25 m/s").font(.caption2).foregroundStyle(.red)
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().day(), centered: false)
                }
            }
            .frame(height: 170)
            Text("Linea: vento medio · area rossa: raffiche (m/s)")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Lists

    private func hourlyList(_ hours: [HourPoint], zone: TimeZone) -> some View {
        Card(title: "Ora per ora", systemImage: "clock") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(hours) { hour in
                        let info = WeatherCode.describe(hour.code, isDay: hour.isDay)
                        VStack(spacing: 6) {
                            Text(Fmt.time(hour.date, in: zone)).font(.caption2).foregroundStyle(.secondary)
                            Image(systemName: info.symbol).symbolRenderingMode(.multicolor).font(.title3)
                            Text(Fmt.temp(hour.temperature)).font(.subheadline.weight(.semibold))
                            HStack(spacing: 2) {
                                WindArrow(degrees: hour.windDirection).font(.caption2)
                                Text("\(Int((hour.wind ?? 0).rounded()))").font(.caption2)
                            }
                            Text("\(Int((hour.gust ?? 0).rounded()))")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(hour.windRisk.color)
                            if let p = hour.precipitationProbability, p >= 20 {
                                Text("\(Int(p))%").font(.caption2).foregroundStyle(.blue)
                            } else {
                                Text(" ").font(.caption2)
                            }
                            if hour.lightningRisk > .ok {
                                Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(.yellow)
                            }
                        }
                        .frame(minWidth: 40)
                    }
                }
            }
            Text("Sotto l'icona: vento medio e raffica (m/s, colorata per rischio) · % pioggia · ⚡ rischio fulmini")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func dailyList(_ days: [DayPoint], zone: TimeZone) -> some View {
        Card(title: "Prossimi 16 giorni", systemImage: "calendar") {
            ForEach(days) { day in
                let info = WeatherCode.describe(day.code)
                HStack {
                    Text(Fmt.day(day.date, in: zone)).font(.subheadline).frame(width: 92, alignment: .leading)
                    Image(systemName: info.symbol).symbolRenderingMode(.multicolor).frame(width: 26)
                    Text("\(Fmt.temp(day.minTemp)) / \(Fmt.temp(day.maxTemp))").font(.subheadline.monospacedDigit())
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("raff. \(Fmt.ms(day.maxGust))").font(.caption.weight(.semibold)).foregroundStyle(day.windRisk.color)
                        if let snow = day.snowfall, snow > 0 {
                            Text("neve \(Fmt.number(snow, decimals: 1, unit: "cm"))").font(.caption2).foregroundStyle(.cyan)
                        } else if let rain = day.precipitation, rain > 0.5 {
                            Text("\(Fmt.number(rain, decimals: 1, unit: "mm"))").font(.caption2).foregroundStyle(.blue)
                        }
                    }
                }
                Divider()
            }
            Text("Oltre 7 giorni le previsioni sono indicative.").font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Sea & air

    @ViewBuilder private var seaCard: some View {
        if let fetched = model.marine, fetched.value.hasData, let c = fetched.value.current {
            let marine = fetched.value
            Card(title: "Mare", systemImage: "water.waves", tint: .teal) {
                HStack {
                    Metric(title: "Onde", value: Fmt.number(c.wave_height, decimals: 1, unit: "m"))
                    Metric(title: "Periodo", value: Fmt.number(c.wave_period, decimals: 0, unit: "s"))
                    Metric(title: "Da", value: Fmt.compass(c.wave_direction))
                }
                HStack {
                    Metric(title: "Onda lunga (swell)", value: Fmt.number(c.swell_wave_height, decimals: 1, unit: "m"))
                    Metric(title: "Max 48 h", value: Fmt.number(marine.maxWaveHeight(next: 48), decimals: 1, unit: "m"))
                    Metric(title: "Acqua", value: Fmt.temp(c.sea_surface_temperature))
                }
                HStack {
                    Text("Spiagge").font(.caption)
                    RiskBadge(risk: marine.beachRisk)
                    Spacer()
                    Text("Traghetti/barche").font(.caption)
                    RiskBadge(risk: marine.seaRisk)
                }
                Text("Su spiagge come Reynisfjara le onde anomale (sneaker waves) arrivano senza preavviso: mai voltare le spalle al mare, resta lontano dalla battigia e rispetta il semaforo all'ingresso.")
                    .font(.caption2).foregroundStyle(.secondary)
                FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: "Open-Meteo Marine")
            }
        }
    }

    @ViewBuilder private var airCard: some View {
        if let fetched = model.air, let c = fetched.value.current {
            Card(title: "Aria e gas vulcanici", systemImage: "aqi.medium", tint: .purple) {
                HStack {
                    Metric(title: "Indice EU", value: Fmt.number(c.european_aqi), tint: fetched.value.aqiRisk.color)
                    Metric(title: "SO₂", value: Fmt.number(c.sulphur_dioxide, unit: "µg/m³"), tint: fetched.value.so2Risk.color)
                    Metric(title: "PM10", value: Fmt.number(c.pm10, unit: "µg/m³"))
                }
                Text("Durante le eruzioni sulla penisola di Reykjanes il gas (SO₂) può spostarsi verso le zone abitate: segui le previsioni del gas su vedur.is.")
                    .font(.caption2).foregroundStyle(.secondary)
                FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: "CAMS via Open-Meteo")
            }
        }
    }
}
