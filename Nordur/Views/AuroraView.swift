import SwiftUI
import Charts

/// Aurora forecast. Three answers kept apart: aurora activity (models and
/// measurements), observability here (darkness, clouds, Moon, geometry) and
/// how reliable both are. Four horizons: live (≤ 90 min), 24 h, 3 days, 27 days.
struct AuroraView: View {
    @Environment(AppModel.self) private var model
    @Environment(Account.self) private var account
    // `-auroraMode day|three|long` as launch argument opens a mode (CI screenshots).
    @State private var mode: Mode = ["day": .day, "three": .three, "long": .long][UserDefaults.standard.string(forKey: "auroraMode") ?? ""] ?? .live
    @State private var reporting: SightingSheet.Kind?

    enum Mode: String, CaseIterable, Identifiable {
        case live = "LIVE", day = "24 ORE", three = "3 GIORNI", long = "27 GIORNI"
        var id: String { rawValue }
    }

    private var zone: TimeZone { model.forecast?.value.timeZone ?? .iceland }
    private var state: AuroraState? { model.aurora?.value }
    private var place: Coordinate { model.activePlace.coordinate }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 16) {
                    HeroHeader(hero: .aurora, eyebrow: String(localized: "NOAA · GFZ · NASA · MET Norway"), title: String(localized: "Aurora"),
                               subtitle: String(localized: "Attività, cielo qui e conferme della community"))
                        .padding(.horizontal, -18)
                    PlaceHeader(size: 30)
                    summary
                    modePicker
                }
                switch mode {
                case .live: liveMode
                case .day: dayMode
                case .three: threeDayMode
                case .long: longMode
                }
                // Sources, data status and the method live in Settings: only a link here.
                NavigationLink { DataSourcesView() } label: {
                    HStack {
                        Label("Fonti, stato dei dati e metodo", systemImage: "doc.text.magnifyingglass")
                            .font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.faint)
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) { Rule() }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refreshAurora() }
        .task { await model.refreshAurora() }
        .onCICommand { command in
            switch command {
            case "aurora.mode.live": mode = .live
            case "aurora.mode.day": mode = .day
            case "aurora.mode.three": mode = .three
            default: break
            }
        }
        .sheet(item: $reporting, onDismiss: { Task { await model.refreshSightings() } }) { kind in
            SightingSheet(coordinate: model.location.coordinate ?? place, kind: kind)
        }
    }

    // MARK: Summary — the three answers

    @ViewBuilder private var summary: some View {
        let now = model.auroraNow
        let best = model.auroraBestTonight
        VStack(spacing: 0) {
            Rule(color: Theme.rule, height: 2)
            HStack(alignment: .top, spacing: 0) {
                answer(String(localized: "ATTIVITÀ"), activityText(now), activityDetail(now))
                Theme.hairline.frame(width: 1)
                answer(String(localized: "OSSERVABILITÀ QUI"), now?.observability.label ?? "–", now.map { $0.darkness.label } ?? "", color: classColor(now?.observability))
                    .padding(.leading, 10)
                Theme.hairline.frame(width: 1)
                answer(String(localized: "AFFIDABILITÀ"), now?.reliability.label ?? "–", now?.activitySource ?? "", color: reliabilityColor(now?.reliability))
                    .padding(.leading, 10)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 12)
            HStack {
                InfoTip(title: String(localized: "Attività, osservabilità, affidabilità"), text: String(localized: "Attività: quanta aurora c'è sopra di te secondo i modelli (OVATION nella prima ora, poi Kp e posizione dell'ovale). Osservabilità: se qui la puoi vedere, combinando l'attività con nuvole, buio, Luna, luci artificiali e orizzonte. Affidabilità: quanto sono recenti e concordi i dati. È una stima, non una probabilità."))
                Spacer()
            }
            .padding(.bottom, 10)
            Rule()
            let confirmation = model.auroraConfirmation
            if confirmation.status != .noReports {
                HStack(alignment: .firstTextBaseline) {
                    Text("COMMUNITY").font(.mono(9.5)).foregroundStyle(Theme.faint)
                    Spacer()
                    Text(confirmation.headline).font(.mono(10.5, .semibold)).foregroundStyle(confirmationColor(confirmation.status))
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 10)
                Rule()
            }
            if let now, !now.reasons.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(now.reasons.prefix(3), id: \.self) { reason in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("—").font(.mono(10)).foregroundStyle(Theme.faint)
                            Text(reason.loc).font(.app(.caption)).foregroundStyle(Theme.text)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                Rule()
            }
            if let best, best.observability > (now?.observability ?? .veryPoor) || best.date.timeIntervalSinceNow > 3600 {
                HStack(alignment: .firstTextBaseline) {
                    Text("FINESTRA MIGLIORE 24 H").font(.mono(9.5)).foregroundStyle(Theme.faint)
                    Spacer()
                    Text("\(Fmt.dayTime(best.date, in: zone)) · \(best.observability.label)")
                        .font(.mono(10.5, .semibold)).foregroundStyle(classColor(best.observability))
                }
                .padding(.vertical, 10)
                Rule()
            }
        }
    }

    private func answer(_ title: String, _ value: String, _ detail: String, color: Color = Theme.text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.loc).font(.mono(8.5)).foregroundStyle(Theme.faint)
            Text(value.uppercased()).font(.display(19, .semibold)).foregroundStyle(color).lineLimit(2).minimumScaleFactor(0.7)
            Text(detail.loc).font(.mono(9)).foregroundStyle(Theme.dim).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activityText(_ s: AuroraSlot?) -> String {
        guard let s else { return "–" }
        if s.activitySource == "OVATION" { return s.geometry == .none ? String(localized: "Assente qui") : s.geometry.label }
        return s.kp.map { "Kp \(Fmt.number($0, decimals: 1))" } ?? "–"
    }

    private func activityDetail(_ s: AuroraSlot?) -> String {
        guard let s else { return "" }
        if s.activitySource == "OVATION", let v = s.ovationValue, v > 0 { return String(localized: "OVATION \(Int(v)) · \(AuroraEngine.compass(s.lookAzimuth))") }
        return s.geometry.label
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(Mode.allCases) { m in
                Button { withAnimation(.snappy(duration: 0.2)) { mode = m } } label: {
                    Text(m.rawValue.loc).font(.mono(10.5, .semibold)).tracking(0.5)
                        .foregroundStyle(mode == m ? Theme.bg : Theme.text)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background(mode == m ? Theme.text : .clear)
                }
                .buttonStyle(.plain)
                if m != Mode.allCases.last { Theme.hairline.frame(width: 1, height: 36) }
            }
        }
        .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: 1))
    }

    // MARK: LIVE (now → 90 min)

    @ViewBuilder private var liveMode: some View {
        nextHourSection
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(index: "02", title: String(localized: "Ovale adesso"), trailing: ovationValidity)
            InfoTip(title: String(localized: "Ovale OVATION"), text: String(localized: "OVATION Prime (NOAA) calcola dalle misure del vento solare dove cade l'aurora nei prossimi 30-90 minuti, in percentuale su una griglia. Oltre quell'orizzonte l'app passa al Kp previsto e alla latitudine geomagnetica."))
            if let now = model.auroraNow, now.activitySource == "OVATION" {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(now.ovationValue.map { "\(Int($0))" } ?? "0").font(.metric(72, .bold))
                        .foregroundStyle((now.ovationValue ?? 0) >= 10 ? Theme.aurora : Theme.text)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("VALORE OVATION NEL TUO CIELO").font(.mono(9)).foregroundStyle(Theme.dim)
                        Text(now.geometry.label.uppercased()).font(.display(20, .semibold)).foregroundStyle(Theme.text)
                        if now.geometry != .none, let az = now.lookAzimuth {
                            Text("GUARDA VERSO \(AuroraEngine.compass(az)) (\(Int(az))°)\(now.lookElevation.map { String(localized: " · ~\(Int($0))° SULL'ORIZZONTE") } ?? "")")
                                .font(.mono(10, .semibold)).foregroundStyle(Theme.accent)
                        }
                    }
                }
                Text("OVATION Prime (NOAA) stima l'aurora per l'orario indicato a partire dal vento solare misurato a L1. Il valore è una grandezza del modello (NOAA la descrive come probabilità di aurora visibile), non la probabilità che tu la veda: nuvole, buio e Luna sono valutati a parte. La direzione considera aurore a ~110 km di quota e la curvatura terrestre.")
                    .font(.app(.caption)).foregroundStyle(Theme.dim)
            } else {
                Text("OVATION non disponibile o fuori validità: l'attività è stimata dal Kp.").font(.app(.caption)).foregroundStyle(Theme.dim)
            }
            NavigationLink { AuroraLiveView() } label: {
                HStack {
                    Text("MAPPA DELL'OVALE").font(.mono(11, .semibold)).tracking(0.6)
                    Spacer()
                    Text("→").font(.mono(14, .semibold))
                }
                .foregroundStyle(Theme.onAccent).padding(.horizontal, 14).frame(height: 44).background(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        solarWindSection
        kpNowSection
        alertsSection
        sightingsSection
    }

    // MARK: Next 60 minutes (solar wind already measured at L1)

    @ViewBuilder private var nextHourSection: some View {
        let steps = model.auroraNextHour
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(index: "01", title: String(localized: "Prossimi 60 minuti"),
                         trailing: state?.solarWind?.nowcast.map { String(localized: "MISURATO FINO A +\($0.coveredMinutes) MIN") } ?? "")
            if steps.isEmpty {
                Text("Previsione a breve termine non disponibile: serve il vento solare aggiornato.")
                    .font(.app(.caption)).foregroundStyle(Theme.dim)
            } else {
                if let summary = AuroraEngine.nextHourSummary(steps) {
                    Text(summary).font(.sans(15, .medium)).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        cellHead(String(localized: "ORA"), 64, .leading)
                        cellHead("BZ", 46)
                        cellHead("KM/S", 50)
                        cellHead("KP", 40)
                        cellHead(String(localized: "OSSERVABILITÀ"), nil, .leading).padding(.leading, 12)
                    }
                    .padding(.bottom, 5)
                    Rule()
                    ForEach(steps, id: \.minutes) { s in
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.minutes == 0 ? String(localized: "now.short", defaultValue: "ORA") : "+\(s.minutes)'")
                                    .font(.mono(10, .semibold)).foregroundStyle(s.minutes == 0 ? Theme.accent : Theme.text)
                                Text(Fmt.time(s.date, in: zone)).font(.mono(8.5)).foregroundStyle(Theme.faint)
                            }
                            .frame(width: 64, alignment: .leading)
                            Text(s.known ? Fmt.number(s.bz, decimals: 1) : "–").font(.metric(16, .semibold))
                                .foregroundStyle(!s.known ? Theme.faint : (s.bz ?? 0) <= -5 ? Theme.aurora : Theme.text)
                                .frame(width: 46, alignment: .trailing)
                            Text(s.known ? Fmt.number(s.speed) : "–").font(.metric(16, .semibold))
                                .foregroundStyle(s.known ? Theme.text : Theme.faint).frame(width: 50, alignment: .trailing)
                            Text(Fmt.number(s.kp, decimals: 1)).font(.metric(16, .semibold))
                                .foregroundStyle(s.known ? Theme.text : Theme.faint).frame(width: 40, alignment: .trailing)
                            Text(s.slot.observability.label).font(.mono(9.5)).foregroundStyle(classColor(s.slot.observability))
                                .lineLimit(1).minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12)
                        }
                        .padding(.vertical, 7)
                        .overlay(alignment: .bottom) { Rule() }
                    }
                }
                Text("Il vento solare che raggiungerà la Terra nei prossimi minuti è già stato misurato dal satellite in L1, a 1,5 milioni di km: ogni misura è spostata del suo tempo di viaggio. Kp atteso = Kp attuale corretto con la variazione dell'accoppiamento di Newell del vento in arrivo; finché è valido, la geometria usa OVATION. L'aurora risponde con un ritardo che va da alcuni minuti a 20–30 minuti. Oltre l'ultimo dato misurato (–) resta il Kp attuale.")
                    .font(.app(.caption)).foregroundStyle(Theme.dim)
            }
        }
    }

    private var ovationValidity: String {
        guard let o = state?.ovation, let v = o.validAt else {
            return model.ovation?.value.forecastTime.map { String(localized: "VALIDO \(Fmt.time($0, in: zone))") } ?? ""
        }
        return String(localized: "VALIDO \(Fmt.time(v, in: zone))")
    }

    @ViewBuilder private var solarWindSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(index: "03", title: String(localized: "Vento solare a L1"), trailing: swTrailing.text, trailingColor: swTrailing.color)
            InfoTip(title: String(localized: "Vento solare e Bz"), text: String(localized: "Il satellite a L1, 1,5 milioni di km verso il Sole, misura il vento solare circa 30-60 minuti prima che arrivi alla Terra. Conta soprattutto il Bz: quando è negativo (verso sud) per decine di minuti, l'aurora si accende. La velocità alta la rende più forte."))
            if let sw = state?.solarWind {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        cellHead("", 46, .leading)
                        ForEach([String(localized: "now.short", defaultValue: "ORA"), "5'", "15'", "30'", "60'"], id: \.self) { cellHead($0, nil) }
                    }
                    .padding(.bottom, 5)
                    Rule()
                    swRow("BZ nT", sw.latest.bz, [5, 15, 30, 60].map { sw.average($0)?.bz }, decimals: 1, tint: { ($0 ?? 0) <= -5 ? Theme.aurora : Theme.text })
                    swRow("BT nT", sw.latest.bt, [5, 15, 30, 60].map { sw.average($0)?.bt }, decimals: 1)
                    swRow("V km/s", sw.latest.v, [5, 15, 30, 60].map { sw.average($0)?.v }, decimals: 0, tint: { ($0 ?? 0) >= 600 ? Theme.aurora : Theme.text })
                    swRow("N /cm³", sw.latest.n, [5, 15, 30, 60].map { sw.average($0)?.n }, decimals: 1)
                    swRow(String(localized: "P nPa"), sw.latest.pdyn, [5, 15, 30, 60].map { sw.average($0)?.pdyn }, decimals: 2)
                }
                ReadingGrid(items: [
                    Reading(label: String(localized: "Bz sud continuo"), value: "\(sw.bzSouth.continuousMinutes)", unit: "min",
                            tint: sw.bzSouth.continuousMinutes >= 30 ? Theme.aurora : Theme.text, size: 24),
                    Reading(label: "Bz ≤ −5 in 60'", value: Fmt.number((sw.bzSouth.fractionBelow5 ?? 0) * 100), unit: "%", size: 24),
                    Reading(label: String(localized: "Pressione vs 1 h fa"), value: sw.pressureTrend.map { "×\(Fmt.number($0, decimals: 1))" } ?? "–",
                            tint: (sw.pressureTrend ?? 1) >= 1.5 ? Theme.caution : Theme.text, size: 24),
                    Reading(label: String(localized: "Arrivo a terra"), value: sw.propagation.map { "\(Int($0.minutes))" } ?? "–",
                            unit: sw.propagation.map { String(localized: "±\(Int($0.uncertaintyMinutes)) min") } ?? "", size: 24),
                    Reading(label: String(localized: "Kp da vento (Newell)"), value: Fmt.number(sw.newellKp, decimals: 1), size: 24),
                    Reading(label: String(localized: "Bz min / max 60'"), value: "\(Fmt.number(sw.extremes60.bzMin, decimals: 0))/\(Fmt.number(sw.extremes60.bzMax, decimals: 0))", unit: "nT", size: 24),
                ], columns: 3)
                .overlay(alignment: .top) { Rule() }
                .overlay(alignment: .bottom) { Rule() }
                if !sw.shocks.isEmpty {
                    ForEach(sw.shocks.suffix(2), id: \.t) { shock in
                        HStack(alignment: .top, spacing: 10) {
                            Rectangle().fill(Theme.accent).frame(width: 3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("POSSIBILE SHOCK INTERPLANETARIO · \(Fmt.time(shock.date, in: zone))").font(.mono(9.5, .semibold)).foregroundStyle(Theme.accent)
                                Text("Salto di velocità +\(Int(shock.dv)) km/s, densità ×\(Fmt.number(shock.densityRatio, decimals: 1)), campo ×\(Fmt.number(shock.fieldRatio, decimals: 1)). Rilevamento automatico, non confermato.")
                                    .font(.app(.caption)).foregroundStyle(Theme.text)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                bzChart(sw)
                if let p = sw.propagation {
                    Text("Il vento misurato ora da \(sw.spacecraft ?? "RTSW") a \(Fmt.number(p.distanceKm / 1000, decimals: 0)) mila km arriva alla Terra tra circa \(Int(p.minutes)) ± \(Int(p.uncertaintyMinutes)) minuti (ritardo piatto X/Vx). La risposta di magnetosfera e ionosfera richiede poi da alcuni minuti a decine di minuti: non è l'orario di comparsa dell'aurora.")
                        .font(.app(.caption)).foregroundStyle(Theme.dim)
                }
            } else {
                Text("Vento solare non disponibile.").font(.app(.caption)).foregroundStyle(Theme.dim)
            }
        }
    }

    private var swTrailing: (text: String, color: Color) {
        guard let sw = state?.solarWind, let s = state?.source("solarWind") else { return ("", Theme.dim) }
        let age = String(localized: "\(sw.spacecraft ?? "") · \(Int(sw.ageMinutes ?? 0)) MIN FA")
        return s.isOK ? (age, Theme.dim) : (String(localized: "NON AGGIORNATO · \(age)"), Theme.warning)
    }

    private func cellHead(_ text: String, _ width: CGFloat?, _ alignment: Alignment = .trailing) -> some View {
        Text(text.loc).font(.mono(8.5)).foregroundStyle(Theme.faint)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }

    private func swRow(_ label: String, _ now: Double?, _ values: [Double?], decimals: Int, tint: @escaping (Double?) -> Color = { _ in Theme.text }) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(label.loc).font(.mono(9)).foregroundStyle(Theme.dim).frame(width: 46, alignment: .leading)
                Text(Fmt.number(now, decimals: decimals)).font(.metric(17, .semibold)).foregroundStyle(tint(now)).frame(maxWidth: .infinity, alignment: .trailing)
                ForEach(Array(values.enumerated()), id: \.offset) { item in
                    Text(Fmt.number(item.element, decimals: decimals)).font(.metric(17)).foregroundStyle(tint(item.element)).frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(height: 28)
            Rule()
        }
    }

    @ViewBuilder private func bzChart(_ sw: AuroraState.SolarWind) -> some View {
        let points = sw.series.compactMap { row -> (Date, Double)? in
            guard row.count >= 2, let t = row[0], let bz = row[1] else { return nil }
            return (Date(timeIntervalSince1970: t), bz)
        }
        if points.count > 10 {
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { item in
                    LineMark(x: .value(String(localized: "Ora"), item.element.0), y: .value("Bz", item.element.1))
                        .foregroundStyle(Theme.text).lineStyle(StrokeStyle(lineWidth: 1.1))
                }
                RuleMark(y: .value("0", 0)).foregroundStyle(Theme.rule.opacity(0.4))
                RuleMark(y: .value("-5", -5)).foregroundStyle(Theme.aurora).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.hairline)
                    AxisValueLabel { if let d = value.as(Date.self) { Text(Fmt.time(d, in: zone)).font(.mono(9)).foregroundStyle(Theme.faint) } }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.hairline)
                    AxisValueLabel { if let v = value.as(Double.self) { Text("\(Int(v))").font(.mono(9)).foregroundStyle(Theme.faint) } }
                }
            }
            .frame(height: 100)
            Text("BZ GSM, ULTIME 3 ORE · LINEA VERDE −5 NT").font(.mono(8.5)).foregroundStyle(Theme.faint)
        }
    }

    @ViewBuilder private var kpNowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(index: "04", title: String(localized: "Indice Kp"), trailing: String(localized: "MISURATO ≠ PREVISTO"))
            InfoTip(title: String(localized: "Indice Kp"), text: String(localized: "Il Kp misura da 0 a 9 il disturbo del campo magnetico terrestre su blocchi di 3 ore. Quello misurato (GFZ Potsdam, NOAA) arriva dopo la fine del blocco; quello previsto viene da NOAA. In Islanda l'aurora è spesso visibile già con Kp 2-3 se il cielo è buio e sereno."))
            VStack(spacing: 0) {
                kpRow(String(localized: "Stima NOAA (1 min)"), String(localized: "provvisoria, magnetometri a terra"), state?.kp.estimated?.kp, state?.kp.estimated?.date)
                kpRow(String(localized: "Kp GFZ Potsdam"), String(localized: "produttore ufficiale · \(state?.kp.gfz.last?.status ?? "–")"), state?.kp.gfz.last?.kp, state?.kp.gfz.last?.date)
                kpRow(String(localized: "Previsione NOAA, blocco attuale"), String(localized: "3 ore"), state?.currentBlock?.noaa, state?.currentBlock?.start)
                kpRow(String(localized: "Combinato, blocco attuale"), state?.currentBlock?.driver ?? "–", state?.currentBlock?.value, nil, highlight: true)
            }
            .overlay(alignment: .top) { Rule() }
            if let hp = state?.hemisphericPower?.latest?.north {
                HStack(alignment: .firstTextBaseline) {
                    Text("POTENZA EMISFERICA (OVATION)").font(.mono(9.5)).foregroundStyle(Theme.faint)
                    Spacer()
                    Text("\(Int(hp)) GW").font(.metric(20, .semibold)).foregroundStyle(hp >= 50 ? Theme.aurora : Theme.text)
                }
            }
            realtimeSection
        }
    }

    /// Faster than Kp and kept apart from it: Hp30 (every 30 min) and the ground magnetometer (every minute).
    @ViewBuilder private var realtimeSection: some View {
        let hp30 = state?.hp30?.last
        let mag = state?.magnetometer
        if hp30 != nil || mag != nil {
            VStack(alignment: .leading, spacing: 0) {
                Text("TEMPO REALE · DIVERSO DAL KP").font(.mono(9.5, .semibold)).foregroundStyle(Theme.faint).padding(.top, 10).padding(.bottom, 4)
                if let hp30 {
                    kpRow(String(localized: "Hp30 GFZ Potsdam"), String(localized: "scala Kp su 30 minuti"), hp30.hp30, hp30.date)
                }
                if let mag {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Magnetometro \(mag.station)").font(.app(.subheadline, .medium)).foregroundStyle(Theme.text)
                                Text(String(localized: "Groenlandia, il più vicino all'Islanda in tempo reale") + (mag.observedDate.map { " · \(Fmt.dayTime($0, in: zone))" } ?? ""))
                                    .font(.mono(9)).foregroundStyle(Theme.faint)
                            }
                            Spacer()
                            Text("\(Int(mag.rangeNt)) nT").font(.metric(26, .semibold)).foregroundStyle(mag.level >= 2 ? Theme.aurora : Theme.text)
                        }
                        Text(mag.levelLabel.uppercased()).font(.mono(10, .semibold)).foregroundStyle(mag.level >= 2 ? Theme.aurora : Theme.dim)
                        if let series = mag.series, series.count > 2 {
                            Chart(series.filter { $0.date != nil }, id: \.t) { p in
                                LineMark(x: .value("t", p.date ?? Date()), y: .value("nT", p.h)).foregroundStyle(Theme.aurora)
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .chartXAxis(.hidden)
                            .chartYAxis(.hidden)
                            .frame(height: 60)
                        }
                        Text("Variazione del campo orizzontale nell'ultima ora: sotto 50 nT calmo, da 150 nT aurora probabile sopra l'Islanda, oltre 400 nT tempesta.")
                            .font(.app(.caption2)).foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func kpRow(_ title: String, _ detail: String, _ kp: Double?, _ time: Date?, highlight: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title.loc).font(.app(.subheadline, .medium)).foregroundStyle(Theme.text)
                    Text(detail + (time.map { " · \(Fmt.dayTime($0, in: zone))" } ?? "")).font(.mono(9)).foregroundStyle(Theme.faint)
                }
                Spacer()
                Text(Fmt.number(kp, decimals: 1)).font(.metric(26, .semibold)).foregroundStyle(highlight ? Theme.accent : Theme.text)
            }
            .padding(.vertical, 8)
            Rule()
        }
    }

    @ViewBuilder private var alertsSection: some View {
        let active = (state?.alerts ?? []).filter { $0.active == true }
        let recent = (state?.alerts ?? []).filter { $0.active != true }.prefix(3)
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(index: "05", title: String(localized: "Avvisi NOAA"), trailing: active.isEmpty ? String(localized: "NESSUNO ATTIVO") : String(localized: "\(active.count) ATTIVI"),
                         trailingColor: active.isEmpty ? Theme.dim : Theme.warning)
            ForEach(active + Array(recent)) { alert in
                HStack(alignment: .top, spacing: 10) {
                    Rectangle().fill(alert.active == true ? Theme.warning : Theme.hairline).frame(width: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(alert.active == true ? "ATTIVO" : String(localized: "SCADUTO")) · \(alert.issuedDate.map { Fmt.dayTime($0, in: zone) } ?? "")")
                            .font(.mono(9)).foregroundStyle(Theme.faint)
                        Text(alert.italian).font(.app(.caption, .medium)).foregroundStyle(Theme.text)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var sightingsSection: some View {
        let confirmation = model.auroraConfirmation
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(index: "06", title: String(localized: "Conferme dalla community"),
                         trailing: String(localized: "ULTIMI \(confirmation.windowMinutes) MIN"))
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(confirmationColor(confirmation.status)).frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(confirmation.headline).font(.sans(16, .semibold)).foregroundStyle(Theme.text)
                    Text(confirmation.detail).font(.app(.caption)).foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            let reports = (model.sightings?.value.recent ?? [])
                .map { (report: $0, km: Geo.distanceKm(place, $0.coordinate)) }
                .filter { $0.km <= 150 }
                .prefix(6)
            if !reports.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(reports.enumerated()), id: \.offset) { entry in
                        sightingRow(entry.element.report, km: entry.element.km)
                        Rule()
                    }
                }
            }
            HStack(spacing: 8) {
                reportButton(account.isSignedIn ? String(localized: "LA VEDO") : String(localized: "ACCEDI PER SEGNALARE"), "+") { reporting = .seen }
                if account.isSignedIn {
                    reportButton(String(localized: "NON LA VEDO"), "–") { reporting = .notSeen }
                }
            }
            .disabled(!account.isSignedIn)
            InfoTip(title: String(localized: "Conferme dalla community"), text: String(localized: "Segnalazioni anonime degli utenti Norður (ultime 3 ore, posizione arrotondata). Pesano di più quelle vicine, recenti e a occhio nudo; «non la vedo» conta solo con cielo sereno. Restano separate dal modello: se non coincidono, lo vedi scritto."), label: String(localized: "Come funziona"))
        }
    }

    private func sightingRow(_ r: SightingReport, km: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(r.date.map { Fmt.time($0, in: zone) } ?? "–").font(.mono(10.5, .medium)).foregroundStyle(Theme.dim).frame(width: 44, alignment: .leading)
            Text("\(Int(km.rounded())) km").font(.mono(10.5)).foregroundStyle(Theme.dim).frame(width: 52, alignment: .leading)
            Text(sightingText(r)).font(.app(.caption, r.isPositive ? .semibold : .regular))
                .foregroundStyle(r.isPositive ? Theme.aurora : Theme.dim)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 28)
    }

    private func sightingText(_ r: SightingReport) -> String {
        guard r.isPositive else {
            switch r.sky {
            case "sereno": return String(localized: "Niente aurora · cielo sereno")
            case "parziale": return String(localized: "Niente aurora · cielo in parte nuvoloso")
            default: return String(localized: "Niente aurora · cielo coperto")
            }
        }
        var parts = [r.nakedEye == true ? String(localized: "A occhio nudo") : String(localized: "Solo in foto")]
        switch r.strength {
        case "debole": parts.append(String(localized: "debole"))
        case "moderata": parts.append(String(localized: "moderata"))
        case "forte": parts.append(String(localized: "forte"))
        default: break
        }
        return parts.joined(separator: " · ")
    }

    private func reportButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.mono(11, .semibold)).tracking(0.6).lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Text(symbol).font(.mono(15, .semibold))
            }
            .foregroundStyle(Theme.text).padding(.horizontal, 14).frame(height: 42)
            .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func confirmationColor(_ status: AuroraConfirmation.Status) -> Color {
        switch status {
        case .confirmed, .likely: return Theme.aurora
        case .reported: return Theme.caution
        case .clearNegative, .noReports: return Theme.faint
        }
    }

    // MARK: 24 h

    @ViewBuilder private var dayMode: some View {
        let slots = model.auroraSlots.filter { $0.date.addingTimeInterval(3600) > Date() }.prefix(24)
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(index: "01", title: String(localized: "Ora per ora"), trailing: String(localized: "ORA LOCALE"))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    cellHead(String(localized: "ORA"), 34, .leading); cellHead(String(localized: "ATTIVITÀ"), 74, .leading); cellHead(String(localized: "NUVOLE"), 50); cellHead(String(localized: "BUIO"), 44); cellHead(String(localized: "LUNA"), 40)
                    cellHead(String(localized: "OSSERVABILITÀ"), nil, .leading).padding(.leading, 10)
                }
                .padding(.bottom, 5)
                Rule()
                ForEach(Array(slots)) { s in
                    HStack(spacing: 0) {
                        Text(Fmt.hour(s.date, in: zone)).font(.mono(10.5, .medium)).foregroundStyle(Theme.dim).frame(width: 34, alignment: .leading)
                        Text(s.activitySource == "OVATION" ? "OV \(Int(s.ovationValue ?? 0))" : "Kp \(Fmt.number(s.kp, decimals: 1))")
                            .font(.mono(10.5, .semibold)).foregroundStyle(s.activityFactor >= 0.4 ? Theme.aurora : Theme.text).frame(width: 74, alignment: .leading)
                        Text(s.clear.map { "\(Int(((1 - $0) * 100).rounded()))%" } ?? "–").font(.metric(16))
                            .foregroundStyle((s.clear ?? 0) < 0.3 ? Theme.faint : Theme.text).frame(width: 50, alignment: .trailing)
                        Text(darkShort(s.darkness)).font(.mono(9.5)).foregroundStyle(s.darkness >= .astronomical ? Theme.text : Theme.faint).frame(width: 44, alignment: .trailing)
                        Text(s.moonAltitude > 0 ? "\(Int((s.moonFraction * 100).rounded()))%" : "—").font(.mono(9.5)).foregroundStyle(Theme.dim).frame(width: 40, alignment: .trailing)
                        HStack(spacing: 6) {
                            classBar(s.observability)
                            Text(s.observability.label).font(.mono(9)).foregroundStyle(classColor(s.observability)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .padding(.leading, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 30)
                    Rule()
                }
            }
            Text("Nuvole: copertura efficace dagli strati bassi, medi e alti (le alte contano la metà). Buio: N = notte astronomica, A/NA = crepuscolo astronomico/nautico, C = civile, G = giorno. Dopo i ~90 minuti di validità di OVATION l'attività deriva dal Kp previsto e dalla posizione dell'ovale.")
                .font(.app(.caption)).foregroundStyle(Theme.dim)
        }
        sitesSection
    }

    private func darkShort(_ d: Astro.Darkness) -> String {
        switch d { case .night: return "N"; case .astronomical: return "A"; case .nautical: return "NA"; case .civil: return "C"; case .day: return "G" }
    }

    private func classBar(_ c: ObservabilityClass) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<4, id: \.self) { i in
                Rectangle().fill(i < c.rawValue ? classColor(c) : Theme.hairline).frame(width: 6, height: 10)
            }
        }
    }

    @ViewBuilder private var sitesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(index: "02", title: String(localized: "Località migliori · 12 h"), trailing: String(localized: "METEO MET NORWAY"))
            if model.siteRanking.isEmpty {
                ErrorNote(message: model.errors[.sites] ?? String(localized: "Classifica in caricamento"))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.siteRanking.prefix(8).enumerated()), id: \.element.id) { item in
                        let s = item.element
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(item.offset + 1)").font(.mono(10, .semibold)).foregroundStyle(Theme.faint).frame(width: 16, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.site.name).font(.app(.subheadline, .medium)).foregroundStyle(Theme.text)
                                Text([s.now.flatMap(\.clear).map { String(localized: "nuvole ora \(Int(((1 - $0) * 100).rounded()))%") },
                                      s.distanceKm.map { "\(Int($0)) km" }].compactMap { $0 }.joined(separator: " · "))
                                    .font(.mono(9)).foregroundStyle(Theme.faint)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(s.best?.observability.label.uppercased() ?? "–").font(.mono(9.5, .semibold)).foregroundStyle(classColor(s.best?.observability))
                                Text(s.best.map { String(localized: "verso le \(Fmt.time($0.date, in: zone))") } ?? "").font(.mono(9)).foregroundStyle(Theme.dim)
                            }
                        }
                        .padding(.vertical, 8)
                        Rule()
                    }
                }
                .overlay(alignment: .top) { Rule() }
                Text("Classifica per indice di osservabilità (euristico): attività prevista × cielo sereno × buio × Luna × luci artificiali (NASA Black Marble) × orizzonte del terreno. Non considera sicurezza e percorribilità delle strade: controlla sempre lo stato delle strade prima di muoverti di notte.")
                    .font(.app(.caption)).foregroundStyle(Theme.dim)
            }
        }
    }

    // MARK: 3 days

    @ViewBuilder private var threeDayMode: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(index: "01", title: String(localized: "Kp a blocchi di 3 ore"), trailing: String(localized: "OSSERVATO · STIMATO · PREVISTO"))
            if let blocks = state?.kp.blocks, !blocks.isEmpty {
                kpChart(blocks)
                VStack(spacing: 0) {
                    ForEach(blocks.filter { !$0.isObserved }.prefix(10)) { b in
                        HStack(spacing: 8) {
                            Text(b.start.map { Fmt.dayTime($0, in: zone) } ?? "").font(.mono(10)).foregroundStyle(Theme.dim).frame(width: 110, alignment: .leading)
                            Text(Fmt.number(b.value, decimals: 1)).font(.metric(18, .semibold)).foregroundStyle(b.value >= 5 ? Theme.warning : Theme.text).frame(width: 34, alignment: .trailing)
                            Text(b.driver).font(.mono(9)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .leading)
                            Text((b.reliability ?? "").uppercased()).font(.mono(8.5)).foregroundStyle(Theme.faint)
                            if b.enlilCloud == true { Text("CME").font(.mono(8.5, .semibold)).foregroundStyle(Theme.accent) }
                        }
                        .frame(height: 26)
                        Rule()
                    }
                }
            } else if !(model.kp?.value ?? []).isEmpty {
                Text("Backend non raggiungibile: Kp dalla previsione NOAA diretta.").font(.app(.caption)).foregroundStyle(Theme.dim)
            }
        }
        nightsSection
        enlilSection
        donkiSection
    }

    private func kpChart(_ blocks: [AuroraState.KpSection.Block]) -> some View {
        let now = Date()
        let shown = blocks.compactMap { b -> (Date, AuroraState.KpSection.Block)? in
            guard let s = b.start, s >= now.addingTimeInterval(-12 * 3600), s <= now.addingTimeInterval(72 * 3600) else { return nil }
            return (s, b)
        }
        return Chart {
            ForEach(Array(shown.enumerated()), id: \.offset) { entry in
                let item = entry.element
                BarMark(x: .value(String(localized: "Ora"), item.0, unit: .hour), y: .value("Kp", item.1.value), width: .fixed(9))
                    .foregroundStyle(item.1.isObserved ? Theme.dim : (item.1.nasa != nil && item.1.driver == "CME NASA" ? Theme.accent : Theme.text))
                if !item.1.isObserved {
                    PointMark(x: .value(String(localized: "Ora"), item.0, unit: .hour), y: .value(String(localized: "NOAA"), item.1.noaa)).symbolSize(14).foregroundStyle(Theme.aurora)
                }
            }
            RuleMark(x: .value(String(localized: "Adesso"), now)).foregroundStyle(Theme.accent).lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartYScale(domain: 0...9)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.hairline)
                AxisValueLabel { if let d = value.as(Date.self) { Text(Fmt.axis(d, hour: false).uppercased()).font(.mono(9)).foregroundStyle(Theme.faint) } }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 3, 5, 7, 9]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.hairline)
                AxisValueLabel { if let v = value.as(Int.self) { Text("\(v)").font(.mono(9)).foregroundStyle(Theme.faint) } }
            }
        }
        .frame(height: 150)
        .environment(\.locale, Fmt.italian)
    }

    /// Best hour of each of the next three nights.
    @ViewBuilder private var nightsSection: some View {
        let nights = nightBests()
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(index: "02", title: String(localized: "Notti"), trailing: String(localized: "ORA MIGLIORE PER NOTTE"))
            ForEach(nights, id: \.date) { s in
                HStack(spacing: 10) {
                    Text(Fmt.day(s.date, in: zone).uppercased()).font(.mono(10, .semibold)).foregroundStyle(Theme.text).frame(width: 96, alignment: .leading)
                    Text(Fmt.time(s.date, in: zone)).font(.mono(10)).foregroundStyle(Theme.dim)
                    classBar(s.observability)
                    Text(s.observability.label).font(.mono(9.5)).foregroundStyle(classColor(s.observability))
                    Spacer()
                    Text(s.reliability.label.uppercased()).font(.mono(8.5)).foregroundStyle(Theme.faint)
                }
                .frame(height: 28)
                Rule()
            }
            if nights.isEmpty { Text("Nessuna ora di buio nei prossimi 3 giorni.").font(.app(.caption)).foregroundStyle(Theme.dim) }
        }
    }

    private func nightBests() -> [AuroraSlot] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        // A night is labelled by the date of its evening: shift by 12 h.
        let groups = Dictionary(grouping: model.auroraSlots.filter { $0.darkness >= .nautical && $0.date > Date().addingTimeInterval(-3600) }) {
            calendar.startOfDay(for: $0.date.addingTimeInterval(-12 * 3600))
        }
        return groups.keys.sorted().prefix(3).compactMap { key in groups[key]?.max { $0.index < $1.index } }
    }

    @ViewBuilder private var enlilSection: some View {
        if let enlil = state?.enlil, !enlil.samples.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(index: "03", title: String(localized: "Vento solare previsto · WSA-ENLIL NOAA"))
                Chart {
                    ForEach(Array(enlil.samples.compactMap { s in s.date.map { ($0, s) } }.enumerated()), id: \.offset) { entry in
                        let item = entry.element
                        LineMark(x: .value(String(localized: "Ora"), item.0), y: .value("km/s", item.1.v)).foregroundStyle(Theme.text)
                        if item.1.cloud {
                            BarMark(x: .value(String(localized: "Ora"), item.0), yStart: .value("a", 250), yEnd: .value("b", 300)).foregroundStyle(Theme.accent)
                        }
                    }
                    RuleMark(x: .value(String(localized: "Adesso"), Date())).foregroundStyle(Theme.accent)
                }
                .chartYScale(domain: 250...max(700, (enlil.samples.map(\.v).max() ?? 600) + 50))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.hairline)
                        AxisValueLabel { if let d = value.as(Date.self) { Text(Fmt.axis(d, hour: false).uppercased()).font(.mono(9)).foregroundStyle(Theme.faint) } }
                    }
                }
                .frame(height: 110)
                Text(enlil.cmeArrivals.isEmpty
                     ? String(localized: "Il modello non prevede l'arrivo di materiale di CME sulla Terra fino al \(enlil.modelEnd.flatMap { DateParse.iso($0) }.map { Fmt.day($0, in: zone) } ?? String(localized: "termine del modello")). ENLIL prevede velocità e densità, non il Bz: da solo non può dire quanto sarà forte una tempesta.")
                     : String(localized: "Arrivo di materiale di CME previsto sulla Terra: \(enlil.cmeArrivals.compactMap { $0.date.map { Fmt.dayTime($0, in: zone) } }.joined(separator: ", ")) (barre arancioni). L'intensità dipenderà dal Bz all'arrivo, misurabile solo ~1 ora prima a L1."))
                    .font(.app(.caption)).foregroundStyle(Theme.dim)
            }
        }
    }

    @ViewBuilder private var donkiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(index: "04", title: String(localized: "NASA DONKI"), trailing: donkiTrailing.text, trailingColor: donkiTrailing.color)
            if let d = state?.donki {
                if d.upcoming.isEmpty {
                    Text("Nessuna CME diretta verso la Terra nelle simulazioni NASA degli ultimi 10 giorni.").font(.app(.caption)).foregroundStyle(Theme.dim)
                }
                ForEach(d.upcoming) { cme in
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle().fill(cme.glancing ? Theme.caution : Theme.accent).frame(width: 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(cme.glancing ? String(localized: "CME DI STRISCIO") : String(localized: "CME DIRETTA")) · ARRIVO \(cme.arrivalDate.map { Fmt.dayTime($0, in: zone).uppercased() } ?? "–") ±\(Int(cme.arrivalUncertaintyHours ?? 7)) H")
                                .font(.mono(9.5, .semibold)).foregroundStyle(Theme.text)
                            Text([cme.speed.map { "\(Int($0)) km/s" }, cme.kp.map { String(localized: "Kp atteso da NASA \(Fmt.number($0.min))–\(Fmt.number($0.max))") }, cme.durationHours.map { "~\(Int($0)) h" }]
                                .compactMap { $0 }.joined(separator: " · ")).font(.app(.caption)).foregroundStyle(Theme.dim)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                if !d.flares.isEmpty {
                    Text("BRILLAMENTI M/X 3 GIORNI: \(d.flares.prefix(6).map(\.classType).joined(separator: " · "))").font(.mono(9.5)).foregroundStyle(Theme.dim)
                }
                Text("Una CME non garantisce un'aurora: l'effetto dipende dall'orientamento del suo campo magnetico, noto solo all'arrivo.").font(.app(.caption)).foregroundStyle(Theme.dim)
            } else {
                Text("NASA DONKI (Goddard CCMC) non risponde: CME e tempeste NASA non sono incluse finché il servizio non torna disponibile. Restano attivi ENLIL di NOAA e gli avvisi NOAA.")
                    .font(.app(.caption)).foregroundStyle(Theme.dim)
            }
        }
    }

    private var donkiTrailing: (text: String, color: Color) {
        switch state?.source("donki")?.status {
        case "ok": return (String(localized: "AGGIORNATO"), Theme.dim)
        case "stale": return (String(localized: "ULTIMA COPIA SALVATA"), Theme.caution)
        default: return (String(localized: "NON DISPONIBILE"), Theme.warning)
        }
    }

    // MARK: 27 days

    @ViewBuilder private var longMode: some View {
        let days = state?.longTerm?.outlook27 ?? []
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(index: "01", title: String(localized: "Tendenza 27 giorni"), trailing: String(localized: "INDICAZIONE PRELIMINARE"))
            Text("NOAA pubblica ogni settimana il Kp massimo atteso per giorno, basato sulla rotazione solare di 27 giorni (ricorrenza dei buchi coronali). Non esiste una previsione affidabile di aurora o nuvole a queste distanze: qui trovi attività attesa, ore di buio e Luna. Il dettaglio aumenta avvicinandosi alla data.")
                .font(.app(.caption)).foregroundStyle(Theme.dim)
            if days.isEmpty {
                ErrorNote(message: String(localized: "Tendenza a 27 giorni non disponibile"))
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        cellHead(String(localized: "GIORNO"), 96, .leading); cellHead(String(localized: "KP MAX"), 52); cellHead("AP", 36); cellHead(String(localized: "BUIO"), 50); cellHead(String(localized: "LUNA"), nil)
                    }
                    .padding(.bottom, 5)
                    Rule()
                    ForEach(days.filter { $0.date >= todayISO }, id: \.date) { d in
                        let info = nightInfo(d.date)
                        HStack(spacing: 0) {
                            Text(info.label).font(.mono(10, .medium)).foregroundStyle(Theme.text).frame(width: 96, alignment: .leading)
                            Text(Fmt.number(d.kpMax)).font(.metric(17, .semibold)).foregroundStyle((d.kpMax ?? 0) >= 5 ? Theme.warning : (d.kpMax ?? 0) >= 4 ? Theme.aurora : Theme.text).frame(width: 52, alignment: .trailing)
                            Text(Fmt.number(d.ap)).font(.metric(15)).foregroundStyle(Theme.dim).frame(width: 36, alignment: .trailing)
                            Text(info.dark).font(.mono(10)).foregroundStyle(Theme.dim).frame(width: 50, alignment: .trailing)
                            Text(info.moon).font(.mono(10)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .frame(height: 26)
                        Rule()
                    }
                }
                Text("BUIO: ore con il Sole sotto −12° (crepuscolo nautico o più scuro). LUNA: illuminazione a mezzanotte locale.").font(.mono(8.5)).foregroundStyle(Theme.faint)
            }
        }
    }

    private var todayISO: String { String(ISO8601DateFormatter().string(from: Date()).prefix(10)) }

    private func nightInfo(_ iso: String) -> (label: String, dark: String, moon: String) {
        guard let day = DateParse.iso(iso + "T12:00:00Z") else { return (iso, "–", "–") }
        let dark = Astro.hoursBelow(-12, from: day, at: place)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let midnight = calendar.startOfDay(for: day).addingTimeInterval(24 * 3600)
        let moon = Astro.moon(midnight, at: place)
        return (Fmt.day(day, in: zone).uppercased(), "\(Fmt.number(dark, decimals: 0)) h", "\(Int((moon.illuminatedFraction * 100).rounded()))%\(moon.altitude > 0 ? " ↑" : "")")
    }

    // MARK: Sources & method

    // MARK: Colours

    private func classColor(_ c: ObservabilityClass?) -> Color {
        switch c {
        case .excellent, .good: return Theme.aurora
        case .moderate: return Theme.caution
        case .poor: return Theme.dim
        default: return Theme.faint
        }
    }

    private func reliabilityColor(_ r: Reliability?) -> Color {
        switch r { case .high: return Theme.text; case .medium: return Theme.dim; default: return Theme.caution }
    }
}

// MARK: - Sightings and backtest (nordur-api)

extension SightingsFeed {
    static func loadFetched(hours: Int = 3) async throws -> Fetched<SightingsFeed> {
        try await HTTP.json(SightingsFeed.self, from: URL(string: "https://nordur-api.vercel.app/api/sightings?hours=\(hours)")!,
                            cacheKey: "nordur_sightings_\(hours)")
    }
}

struct BacktestResponse: Decodable {
    struct Score: Decodable { let n: Int?; let mae: Double?; let bias: Double?; let rmse: Double? }
    struct Bucket: Decodable { let noaa: Score; let blend: Score }
    let verifiedPairs: Int
    let sufficient: Bool
    let note: String?
    let buckets: [String: Bucket]

    static func load() async throws -> BacktestResponse {
        try await HTTP.json(BacktestResponse.self, from: URL(string: "https://nordur-api.vercel.app/api/backtest")!, cacheKey: "nordur_backtest").value
    }
}

struct SightingSheet: View {
    enum Kind: String, Identifiable { case seen, notSeen; var id: String { rawValue } }

    let coordinate: Coordinate
    var kind: Kind = .seen
    @Environment(Account.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var nakedEye = true
    @State private var camera = false
    @State private var strength = "moderata"
    @State private var sky = "sereno"
    @State private var message: String?
    @State private var sending = false

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: kind == .seen ? String(localized: "Avvistamento") : String(localized: "Nessuna aurora"),
                             subtitle: Fmt.coordinate(coordinate))
                if kind == .seen {
                    Toggle("Visibile a occhio nudo", isOn: $nakedEye).font(.app(.subheadline))
                    Toggle("Visibile in foto", isOn: $camera).font(.app(.subheadline))
                    Picker("Intensità", selection: $strength) {
                        Text("Debole").tag("debole"); Text("Moderata").tag("moderata"); Text("Forte").tag("forte")
                    }
                    .pickerStyle(.segmented)
                } else {
                    Text("Stai guardando il cielo a nord e non vedi l'aurora? Dicci com'è il cielo: con cielo sereno la tua segnalazione aiuta gli altri a non uscire per niente.")
                        .font(.app(.subheadline)).foregroundStyle(Theme.text)
                    Picker("Cielo", selection: $sky) {
                        Text("Sereno").tag("sereno"); Text("In parte nuvoloso").tag("parziale"); Text("Coperto").tag("coperto")
                    }
                    .pickerStyle(.segmented)
                }
                Button {
                    sending = true
                    Task {
                        do {
                            if kind == .seen {
                                try await account.reportSighting(at: coordinate, seen: true, nakedEye: nakedEye, camera: camera, strength: strength, sky: nil)
                            } else {
                                try await account.reportSighting(at: coordinate, seen: false, nakedEye: false, camera: false, strength: nil, sky: sky)
                            }
                            message = String(localized: "Segnalazione registrata. Grazie.")
                            Haptics.result(true)
                        } catch { message = error.localizedDescription; Haptics.result(false) }
                        sending = false
                    }
                } label: {
                    HStack {
                        Text("INVIA").font(.mono(13, .semibold)).tracking(1)
                        Spacer()
                        if sending { ProgressView().tint(Theme.onAccent) } else { Text("→").font(.mono(15, .semibold)) }
                    }
                    .foregroundStyle(Theme.onAccent).padding(.horizontal, 14).frame(height: 48).background(Theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(sending || (kind == .seen && !nakedEye && !camera))
                if let message { Text(message.loc).font(.app(.footnote)).foregroundStyle(Theme.text) }
                Text("Posizione arrotondata a ~1 km. Una segnalazione ogni 20 minuti. Le segnalazioni sono anonime per gli altri utenti.")
                    .font(.app(.caption)).foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Theme.bg.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
